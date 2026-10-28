#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
ensure_build_dirs

log "bersihkan rootfs staging"
remove_tree "$GNTRESS_ROOTFS_DIR"
mkdir -p "$GNTRESS_ROOTFS_DIR"

log "install komponen ke $GNTRESS_ROOTFS_DIR"
docker run --rm \
  -v "$GNTRESS_ROOT:/gntress:ro" \
  -v "$GNTRESS_SRC_DIR:/src" \
  -v "$GNTRESS_TARGET_DIR:/target:ro" \
  -v "$GNTRESS_ROOTFS_DIR:/stage" \
  -e GNTRESS_ROOT=/gntress \
  -e CARGO_TARGET_DIR=/target \
  -e GNTRESS_UID="$(id -u)" \
  -e GNTRESS_GID="$(id -g)" \
  "$GNTRESS_BUILDER_IMAGE" \
  bash /gntress/scripts/container-stage.sh

log "rootfs: $(du -sh "$GNTRESS_ROOTFS_DIR" | cut -f1)"
