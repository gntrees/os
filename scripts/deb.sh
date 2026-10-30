#!/usr/bin/env bash
# Builds the gntrees .deb packages from the staged rootfs and repo sources.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
[ -x "$GNTREES_ROOTFS_DIR/usr/bin/gntrees-launcher" ] \
  || die "launcher belum dibangun; jalankan 'just app' dulu"
[ -f "$GNTREES_ROOTFS_DIR/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites" ] \
  || die "rootfs belum siap; jalankan 'just stage' dulu"
ensure_build_dirs

[ -d "$GNTREES_PKG_DIR/cosmic-comp" ] \
  || die "payload COSMIC belum ada; jalankan 'just stage' dulu"

log "build image: $GNTREES_BUILDER_IMAGE"
docker build -q -t "$GNTREES_BUILDER_IMAGE" \
  -f "$GNTREES_ROOT/containers/ubuntu.Dockerfile" "$GNTREES_ROOT/containers" >/dev/null

remove_tree "$GNTREES_DEB_DIR"
mkdir -p "$GNTREES_DEB_DIR"

log "bangun paket .deb"
docker run --rm \
  -v "$GNTREES_ROOT:/gntrees:ro" \
  -v "$GNTREES_ROOTFS_DIR:/rootfs:ro" \
  -v "$GNTREES_PKG_DIR:/pkg:ro" \
  -v "$GNTREES_DEB_DIR:/out/deb" \
  -e GNTREES_VERSION="$GNTREES_VERSION" \
  -e GNTREES_ARCH="$GNTREES_ARCH" \
  -e GNTREES_NAME="$GNTREES_NAME" \
  -e GNTREES_DISTRO="$GNTREES_DISTRO" \
  -e GNTREES_SUITE="$GNTREES_SUITE" \
  -e GNTREES_CODENAME="$GNTREES_CODENAME" \
  -e GNTREES_COSMIC_VERSION="$GNTREES_COSMIC_VERSION" \
  -e GNTREES_PKG_ROOT=/pkg \
  -e GNTREES_DEB_REV="${GNTREES_DEB_REV:-1}" \
  -e GNTREES_UID="$(id -u)" \
  -e GNTREES_GID="$(id -g)" \
  "$GNTREES_BUILDER_IMAGE" \
  bash /gntrees/scripts/container-deb.sh

log "paket: $GNTREES_DEB_DIR"
ls -1 "$GNTREES_DEB_DIR"
