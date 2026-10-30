#!/usr/bin/env bash
# Runs inside the build container. Sources at /src, per-component trees at /pkg,
# merged staging rootfs at /stage.
set -euo pipefail
. /gntrees/scripts/lib.sh

# Stages run as root here. Hand the trees back to the host user on the way out,
# including on failure, so `just stage` and `just clean` need no sudo.
hand_back() {
  if [ -n "${GNTREES_UID:-}" ] && [ -n "${GNTREES_GID:-}" ]; then
    chown -R "${GNTREES_UID}:${GNTREES_GID}" /stage /pkg 2>/dev/null || true
  fi
}
trap hand_back EXIT

mkdir -p /stage /pkg

# Install each component into its own tree first: `just deb` uses that tree as
# the .deb payload, and the union below is the rootfs the ISO is built from.
while read -r name repo rev builder; do
  log "$name: install -> /pkg/$name"
  ( cd "/src/$name" && just rootdir="/pkg/$name" prefix=/usr install )
  log "$name: merge -> /stage"
  cp -a "/pkg/$name/." /stage/
done < <(enabled_components)
