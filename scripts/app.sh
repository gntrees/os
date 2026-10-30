#!/usr/bin/env bash
# Builds the in-repo Tauri launcher and installs it into the staging rootfs.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
[ -x "$GNTREES_ROOTFS_DIR/usr/bin/cosmic-session" ] \
  || die "rootfs belum siap; jalankan 'just stage' dulu"
ensure_build_dirs

log "build image: $GNTREES_BUILDER_IMAGE"
docker build -q -t "$GNTREES_BUILDER_IMAGE" \
  -f "$GNTREES_ROOT/containers/ubuntu.Dockerfile" "$GNTREES_ROOT/containers" >/dev/null

log "compile launcher"
docker run --rm \
  -v "$GNTREES_ROOT:/gntrees:ro" \
  -v "$GNTREES_ROOT/apps:/apps" \
  -v "$GNTREES_CARGO_DIR:/cargo" \
  -v "$GNTREES_TARGET_DIR:/target" \
  -v "$GNTREES_ROOTFS_DIR:/stage" \
  -e GNTREES_ROOT=/gntrees \
  -e CARGO_HOME=/cargo \
  -e CARGO_TARGET_DIR=/target \
  -e CARGO_BUILD_JOBS="$GNTREES_JOBS" \
  -e CARGO_NET_GIT_FETCH_WITH_CLI=true \
  -e GNTREES_UID="$(id -u)" \
  -e GNTREES_GID="$(id -g)" \
  "$GNTREES_BUILDER_IMAGE" \
  bash /gntrees/scripts/container-app.sh

log "launcher: $GNTREES_ROOTFS_DIR/usr/bin/gntrees-launcher"
