#!/usr/bin/env bash
# Runs inside the build container. Repo is mounted read-only at /gntress.
set -euo pipefail
. /gntress/scripts/lib.sh

# Cargo runs as root here. Hand the artifacts back to the host user on the way
# out, including on failure, so target/ and cargo/ stay deletable without sudo.
hand_back() {
  if [ -n "${GNTRESS_UID:-}" ] && [ -n "${GNTRESS_GID:-}" ]; then
    chown -R "${GNTRESS_UID}:${GNTRESS_GID}" /target /cargo /src 2>/dev/null || true
  fi
}
trap hand_back EXIT

mkdir -p /target

while read -r name repo rev builder; do
  # Some upstream justfiles reference ./target directly (cosmic-applets generates
  # desktop files under target/xdgen). Point it at the shared target directory.
  if [ -n "${CARGO_TARGET_DIR:-}" ] && [ ! -e "/src/$name/target" ]; then
    ln -s "$CARGO_TARGET_DIR" "/src/$name/target"
  fi
  case "$builder" in
    install-only)
      log "$name: tanpa compile"
      ;;
    just)
      log "$name: just build-release"
      ( cd "/src/$name" && just build-release )
      ;;
    *)
      die "$name: builder tidak dikenal '$builder'"
      ;;
  esac
done < <(enabled_components)
