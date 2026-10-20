set shell := ["sh", "-eu", "-c"]
# scripts are sh-only; on Windows just must call them through git bash too
set windows-shell := ["sh", "-eu", "-c"]

# Download bundles + metadata for every link in pkgs.txt
fetch:
    ./pkg.sh fetch

# List fetched pkgs: all by default, or only --win / --linux / --macos
list *args:
    ./pkg.sh list {{args}}

# Re-fetch and install into Vicinae: all links by default, or only the named pkgs.
# OS by default, or --win / --linux / --macos / --all
install *args:
    ./pkg.sh install {{args}}

# Uninstall pkgs and drop them from pkgs.txt: current OS by default, or --win / --linux / --macos / --all
uninstall *args:
    ./pkg.sh uninstall {{args}}
