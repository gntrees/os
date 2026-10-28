#!/usr/bin/env bash
# Runs inside the build container. Sources at /src, staging at /stage.
set -euo pipefail
. /gntress/scripts/lib.sh

# Stages run as root here. Hand /stage back to the host user on the way out,
# including on failure, so `just stage` and `just clean` need no sudo.
hand_back() {
  if [ -n "${GNTRESS_UID:-}" ] && [ -n "${GNTRESS_GID:-}" ]; then
    chown -R "${GNTRESS_UID}:${GNTRESS_GID}" /stage 2>/dev/null || true
  fi
}
trap hand_back EXIT

while read -r name repo rev builder; do
  log "$name: install -> /stage"
  ( cd "/src/$name" && just rootdir=/stage prefix=/usr install )
done < <(enabled_components)
