#!/usr/bin/env bash
# Runs inside the build container. Sources at /apps, staging at /stage.
set -euo pipefail
. /gntress/scripts/lib.sh

# Cargo runs as root; hand the tree back so the host user can rebuild without sudo.
hand_back() {
  if [ -n "${GNTRESS_UID:-}" ] && [ -n "${GNTRESS_GID:-}" ]; then
    chown -R "${GNTRESS_UID}:${GNTRESS_GID}" /target /apps /stage 2>/dev/null || true
  fi
}
trap hand_back EXIT

cd /apps/launcher
cargo build --release

target="${CARGO_TARGET_DIR:-target}/release"
install -Dm0755 "$target/gntress-launcher" /stage/usr/bin/gntress-launcher
install -Dm0644 data/gntress-launcher.desktop /stage/usr/share/applications/gntress-launcher.desktop
