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
#   pkg.sh update [--win|--linux|--macos|--all]   re-fetch + install (default: current OS)
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
	Windows) cygpath -u "$LOCALAPPDATA/vicinae/data/extensions" ;;
	*) echo "${XDG_DATA_HOME:-$HOME/.local/share}/vicinae/extensions" ;;
	esac
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
	filter=all
	[ $# -gt 0 ] && filter="$(echo "$1" | sed 's/^--//; s/^win$/Windows/; s/^linux$/Linux/; s/^macos$/macOS/')"
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

cmd_update() {
	mkdir -p cache pkgs # update may run before any fetch
	filter="$(os_now)"
	[ -n "$filter" ] || filter=all # unknown OS -> install everything
	[ $# -gt 0 ] && filter="$(echo "$1" | sed 's/^--//; s/^win$/Windows/; s/^linux$/Linux/; s/^macos$/macOS/')"
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

case "${1:-}" in
fetch) cmd_fetch ;;
list)
	shift
	cmd_list "$@"
	;;
update)
	shift
	cmd_update "$@"
	;;
*) die "usage: pkg.sh fetch | list [--win|--linux|--macos] | update [--win|--linux|--macos|--all]" ;;
esac
