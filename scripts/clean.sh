#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

remove_tree "$GNTRESS_ROOTFS_DIR"
remove_tree "$GNTRESS_LIVE_DIR"
remove_tree "$GNTRESS_OUT_DIR"
log "rootfs, live build tree, dan output ISO dihapus (source + cache dipertahankan)"
