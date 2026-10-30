#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
ensure_build_dirs

log "bersihkan rootfs staging"
remove_tree "$GNTREES_ROOTFS_DIR"
remove_tree "$GNTREES_PKG_DIR"
mkdir -p "$GNTREES_ROOTFS_DIR" "$GNTREES_PKG_DIR"

log "install komponen ke $GNTREES_ROOTFS_DIR"
docker run --rm \
  -v "$GNTREES_ROOT:/gntrees:ro" \
  -v "$GNTREES_SRC_DIR:/src" \
  -v "$GNTREES_TARGET_DIR:/target:ro" \
  -v "$GNTREES_ROOTFS_DIR:/stage" \
  -v "$GNTREES_PKG_DIR:/pkg" \
  -e GNTREES_ROOT=/gntrees \
  -e CARGO_TARGET_DIR=/target \
  -e GNTREES_UID="$(id -u)" \
  -e GNTREES_GID="$(id -g)" \
  "$GNTREES_BUILDER_IMAGE" \
  bash /gntrees/scripts/container-stage.sh

log "rootfs: $(du -sh "$GNTREES_ROOTFS_DIR" | cut -f1)"
