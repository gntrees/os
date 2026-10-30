#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

remove_tree "$GNTREES_ROOTFS_DIR"
remove_tree "$GNTREES_LIVE_DIR"
remove_tree "$GNTREES_OUT_DIR"
remove_tree "$GNTREES_PKG_DIR"
remove_tree "$GNTREES_DEB_DIR"
remove_tree "$GNTREES_APT_DIR"
log "rootfs, payload komponen, live build tree, output ISO, paket deb, dan repo APT dihapus (source + cache dipertahankan)"
