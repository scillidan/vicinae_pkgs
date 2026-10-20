#!/bin/sh
# Vicinae pkg manager (sh-only; use git bash on Windows).
#
#   pkgs.txt           user list: one store link or author/name per line; '#' = ignored
#   cache/<name>.zip   downloaded bundle (kept on disk)
#   pkgs/<name>.json   metadata, minified package.json (name/platforms/title/...)
#
# Usage:
#   pkg.sh fetch                 download bundles + metadata for every link in pkgs.txt
#   pkg.sh list  [--win|--linux|--macos]   list fetched pkgs (default: all)
#   pkg.sh install [--win|--linux|--macos|--all]   re-fetch + install (default: current OS)
#   pkg.sh uninstall [--win|--linux|--macos|--all] <name>...   uninstall + drop from pkgs.txt
set -eu
cd "$(dirname "$0")"
API="https://api.vicinae.com/v1/store"

die() {
	echo "$*" >&2
	exit 1
}
[ -f pkgs.txt ] || die 'pkgs.txt not found'

os_now() {
	case "$(uname -s)" in
	MINGW* | MSYS* | CYGWIN*) echo Windows ;;
	Linux) echo Linux ;;
	Darwin) echo macOS ;;
	*) echo ;;
	esac
}

ext_dir_for() { # $1 = target OS -> that OS's Vicinae extension dir
	case "$1" in
	Windows)
		[ -n "${LOCALAPPDATA:-}" ] && command -v cygpath >/dev/null 2>&1 || return 0
		cygpath -u "$LOCALAPPDATA/vicinae/data/extensions"
		;;
	*) echo "${XDG_DATA_HOME:-$HOME/.local/share}/vicinae/extensions" ;;
	esac
}

os_filter() { # $1 = --win/--linux/--macos/--all flag (may be empty), $2 = fallback OS
	f="${2:-all}"
	[ -n "${1:-}" ] && f="$(echo "$1" | sed 's/^--//; s/^win$/Windows/; s/^linux$/Linux/; s/^macos$/macOS/')"
	echo "$f"
}

norm_id() { # store page URL / api URL / author/name -> author/name
	echo "$1" | tr -d '\r' | sed -E 's#https?://(www\.)?vicinae\.com/extensions/##; s#https?://api\.vicinae\.com/v1/store/##; s#/download/?$##; s#/*$##'
}

each_link() { grep -vE '^\s*(#|$)' pkgs.txt | tr -d '\r'; }

platforms_of() { # metadata file -> raw ["Linux",...] or empty (= all platforms)
	grep -o '"platforms":[[:space:]]*\[[^]]*\]' "$1" | tr -d '[:space:]' | head -n1
}

match_os() { # $1 = filter (all|Windows|Linux|macOS), $2 = platforms raw -> 0 if pkg runs there
	[ "$1" = all ] && return 0
	[ -z "$2" ] && return 0 # no platforms field = all platforms
	echo "$2" | grep -q "\"$1\""
}

fetch_one() { # $1 = link or author/name
	id="$(norm_id "$1")"
	name="${id##*/}"
	echo "fetch: $id"
	if ! curl -fsSL "$API/$id/download" -o "cache/$name.zip"; then
		echo "  FAILED (old cache kept if any)" >&2
		return 1
	fi
	if ! meta="$(unzip -p "cache/$name.zip" '*/package.json')"; then
		rm -f "cache/$name.zip" "pkgs/$name.json" # corrupt bundle: don't keep half-written data
		echo "  FAILED (corrupt bundle)" >&2
		return 1
	fi
	printf '%s' "$meta" | tr -d '\n\t' >"pkgs/$name.json"
}

cmd_fetch() {
	mkdir -p cache pkgs
	each_link | while read -r link; do
		fetch_one "$link" || true
	done
}

cmd_list() {
	filter="$(os_filter "${1:-}" all)"
	ls pkgs/*.json >/dev/null 2>&1 || die 'nothing fetched yet — run: pkg.sh fetch'
	printf '%-20s %-18s %s\n' PKG PLATFORMS TITLE
	for meta in pkgs/*.json; do
		name="$(basename "$meta" .json)"
		line="$(cat "$meta")"
		raw="$(platforms_of "$meta")"
		plats="$raw"
		[ -z "$plats" ] || plats="$(echo "$raw" | sed -e 's/^"platforms"://' -e 's/[][]//g' -e 's/"//g')"
		[ -n "$plats" ] || plats='(all)'
		match_os "$filter" "$raw" || continue
		title="$(echo "$line" | grep -o '"title":[[:space:]]*"[^"]*"' | head -n1 | cut -d'"' -f4)"
		printf '%-20s %-18s %s\n' "$name" "$plats" "$title"
	done
}

cmd_install() {
	mkdir -p cache pkgs # install may run before any fetch
	filter="$(os_filter "${1:-}" "$(os_now)")"
	ext="${EXT_DIR:-$(ext_dir_for "$([ "$filter" = all ] && os_now || echo "$filter")")}"
	mkdir -p "$ext"
	echo "target: $filter  ->  $ext"
	each_link | while read -r link; do
		name="$(norm_id "$link" | awk -F/ '{print $NF}')"
		[ -n "$name" ] && [ "$name" != ".." ] || {
			echo "  skip bad line: $link"
			continue
		}
		fetch_one "$link" || true
		[ -f "pkgs/$name.json" ] || {
			echo "  skip $name: no metadata"
			continue
		}
		if ! match_os "$filter" "$(platforms_of "pkgs/$name.json")"; then
			echo "  skip $name: $(platforms_of "pkgs/$name.json")"
			continue
		fi
		rm -rf "$ext/$name" # replace old version if present
		unzip -oq "cache/$name.zip" -d "$ext"
		echo "install: $name"
	done
	echo 'restart Vicinae to pick up changes'
}

cmd_uninstall() { # $1 = optional OS flag, rest = name / author/name / link
	[ $# -gt 0 ] || die 'usage: pkg.sh uninstall [--win|--linux|--macos|--all] <name>...'
	case "$1" in
	--*)
		filter="$(os_filter "$1" "$(os_now)")"
		shift
		;;
	*) filter="$(os_filter "" "$(os_now)")" ;;
	esac
	[ $# -gt 0 ] || die 'usage: pkg.sh uninstall [--win|--linux|--macos|--all] <name>...'

	if [ -n "${EXT_DIR:-}" ]; then
		dirs="$EXT_DIR"
	elif [ "$filter" = all ]; then
		dirs="$(
			ext_dir_for Windows
			ext_dir_for Linux
		)" # macOS shares the XDG dir
	else
		dirs="$(ext_dir_for "$filter")"
	fi

	names=""
	for arg in "$@"; do
		name="$(norm_id "$arg")"
		name="${name##*/}"
		[ -n "$name" ] || continue
		names="$names $name"
		echo "uninstall: $name"
		for d in $dirs; do rm -rf "$d/$name"; done
		rm -f "cache/$name.zip" "pkgs/$name.json"
	done
	[ -n "$names" ] || return 0

	# drop the lines too, else the next install puts them right back
	tmp=pkgs.txt.new
	awk -v list="$names" '
		BEGIN { n = split(list, a, " ") }
		{
			line = $0; sub(/\r$/, "", line)
			if (line !~ /^[[:space:]]*#/)
				for (i = 1; i <= n; i++) if (line ~ ("/" a[i] "$")) next
			print
		}' pkgs.txt >"$tmp" && mv "$tmp" pkgs.txt
}

case "${1:-}" in
fetch) cmd_fetch ;;
list)
	shift
	cmd_list "$@"
	;;
install)
	shift
	cmd_install "$@"
	;;
uninstall)
	shift
	cmd_uninstall "$@"
	;;
*) die "usage: pkg.sh fetch | list [--win|--linux|--macos] | install [--win|--linux|--macos|--all] | uninstall [--win|--linux|--macos|--all] <name>..." ;;
esac
