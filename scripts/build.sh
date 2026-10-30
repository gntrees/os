#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
ensure_build_dirs

log "build image: $GNTREES_BUILDER_IMAGE"
docker build -q -t "$GNTREES_BUILDER_IMAGE" \
  -f "$GNTREES_ROOT/containers/ubuntu.Dockerfile" "$GNTREES_ROOT/containers" >/dev/null

log "compile komponen (jobs=$GNTREES_JOBS)"
docker run --rm \
  -v "$GNTREES_ROOT:/gntrees:ro" \
  -v "$GNTREES_SRC_DIR:/src" \
  -v "$GNTREES_CARGO_DIR:/cargo" \
  -v "$GNTREES_TARGET_DIR:/target" \
  -e GNTREES_ROOT=/gntrees \
  -e CARGO_HOME=/cargo \
  -e CARGO_TARGET_DIR=/target \
  -e CARGO_BUILD_JOBS="$GNTREES_JOBS" \
  -e CARGO_NET_GIT_FETCH_WITH_CLI=true \
  -e GNTREES_UID="$(id -u)" \
  -e GNTREES_GID="$(id -g)" \
  "$GNTREES_BUILDER_IMAGE" \
  bash /gntrees/scripts/container-build.sh

log "selesai. target dir: $GNTREES_TARGET_DIR"
