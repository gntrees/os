#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
ensure_build_dirs

log "build image: $GNTRESS_BUILDER_IMAGE"
docker build -q -t "$GNTRESS_BUILDER_IMAGE" \
  -f "$GNTRESS_ROOT/containers/ubuntu.Dockerfile" "$GNTRESS_ROOT/containers" >/dev/null

log "compile komponen (jobs=$GNTRESS_JOBS)"
docker run --rm \
  -v "$GNTRESS_ROOT:/gntress:ro" \
  -v "$GNTRESS_SRC_DIR:/src" \
  -v "$GNTRESS_CARGO_DIR:/cargo" \
  -v "$GNTRESS_TARGET_DIR:/target" \
  -e GNTRESS_ROOT=/gntress \
  -e CARGO_HOME=/cargo \
  -e CARGO_TARGET_DIR=/target \
  -e CARGO_BUILD_JOBS="$GNTRESS_JOBS" \
  -e CARGO_NET_GIT_FETCH_WITH_CLI=true \
  -e GNTRESS_UID="$(id -u)" \
  -e GNTRESS_GID="$(id -g)" \
  "$GNTRESS_BUILDER_IMAGE" \
  bash /gntress/scripts/container-build.sh

log "selesai. target dir: $GNTRESS_TARGET_DIR"
