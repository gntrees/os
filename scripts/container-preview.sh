#!/usr/bin/env bash
# Runs inside the build container for a nested visual preview.
set -euo pipefail

export PATH="/stage/usr/bin:$PATH"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg}"
export XDG_CURRENT_DESKTOP=COSMIC
export XDG_SESSION_DESKTOP=COSMIC
export XDG_SESSION_TYPE=wayland

mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

# cosmic-session supervises the compositor, panel and notification daemon as one
# tree. start-cosmic is skipped here: it imports the environment into a running
# systemd user manager, which this container does not have.
exec dbus-run-session -- /stage/usr/bin/cosmic-session
