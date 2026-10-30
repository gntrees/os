#!/usr/bin/env bash
# Runs inside the build container. Sources at /apps, staging at /stage.
set -euo pipefail
. /gntrees/scripts/lib.sh

# Cargo runs as root; hand the tree back so the host user can rebuild without sudo.
hand_back() {
  if [ -n "${GNTREES_UID:-}" ] && [ -n "${GNTREES_GID:-}" ]; then
    chown -R "${GNTREES_UID}:${GNTREES_GID}" /target /apps /stage 2>/dev/null || true
  fi
}
trap hand_back EXIT

cd /apps/launcher
cargo build --release

target="${CARGO_TARGET_DIR:-target}/release"
install -Dm0755 "$target/gntrees-launcher" /stage/usr/bin/gntrees-launcher
install -Dm0644 data/gntrees-launcher.desktop /stage/usr/share/applications/gntrees-launcher.desktop
install -Dm0644 icons/icon.png /stage/usr/share/icons/hicolor/512x512/apps/gntrees-launcher.png
install -Dm0644 icons/icon.png /stage/usr/share/icons/hicolor/256x256/apps/gntrees-launcher.png
