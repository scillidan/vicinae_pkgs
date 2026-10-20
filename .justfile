set shell := ["sh", "-eu", "-c"]
# scripts are sh-only; on Windows just must call them through git bash too
set windows-shell := ["sh", "-eu", "-c"]

default:
    @just --list

# Download bundles + metadata for every link in pkgs.txt
fetch:
    ./pkg.sh fetch

# List fetched pkgs: all by default, or only --win / --linux / --macos
list *args:
    ./pkg.sh list {{args}}

# Re-fetch and install into Vicinae: current OS by default, or --win / --linux / --macos / --all
update *args:
    ./pkg.sh update {{args}}
