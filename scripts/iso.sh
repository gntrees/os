#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
[ -x "$GNTRESS_ROOTFS_DIR/usr/bin/cosmic-session" ] \
  || die "rootfs belum siap; jalankan 'just stage' dulu"
[ -x "$GNTRESS_ROOTFS_DIR/usr/bin/gntress-launcher" ] \
  || die "launcher belum dibangun; jalankan 'just app' dulu"
ensure_build_dirs
mkdir -p "$GNTRESS_CACHE_DIR/apt"

log "build image: $GNTRESS_ISO_IMAGE"
docker build -q -t "$GNTRESS_ISO_IMAGE" \
  -f "$GNTRESS_ROOT/containers/ubuntu-iso.Dockerfile" "$GNTRESS_ROOT/containers" >/dev/null

live="$GNTRESS_LIVE_DIR"
log "siapkan live-build tree di $live"
remove_tree "$live"
mkdir -p "$live"
cp -a "$GNTRESS_ROOT/profile/ubuntu/." "$live/"

inc="$live/config/includes.chroot"
mkdir -p "$inc"
cp -a "$GNTRESS_ROOTFS_DIR/." "$inc/"
install -Dm0644 "$GNTRESS_ROOT/config/greetd.toml" "$inc/etc/greetd/config.toml"

# --- desktop payload -------------------------------------------------------
wall="$GNTRESS_ROOT/config/wallpaper"
install -Dm0644 "$wall/gntress-genesis.jpg" \
  "$inc/usr/share/backgrounds/gntress/genesis.jpg"
# cosmic-bg's compiled-in fallback points at this path, so a broken config still
# leaves a wallpaper instead of a bare compositor colour.
install -Dm0644 "$wall/gntress-genesis.jpg" \
  "$inc/usr/share/backgrounds/cosmic/orion_nebula_nasa_heic0601a.jpg"
install -Dm0644 "$wall/cosmic-background.ron" \
  "$inc/usr/share/cosmic/com.system76.CosmicBackground/v1/all"

# Super and Super+/ must open our launcher; cosmic-launcher is not in this image.
shortcuts="$inc/usr/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions"
[ -f "$shortcuts" ] || die "system_actions tidak ada di rootfs; cek 'just stage'"
sed -i 's/^\([[:space:]]*\)Launcher: "cosmic-launcher",/\1Launcher: "gntress-launcher",/' "$shortcuts"
grep -q 'Launcher: "gntress-launcher"' "$shortcuts" \
  || die "gagal memetakan aksi Launcher ke gntress-launcher"

# --- disk installer --------------------------------------------------------
inst="$GNTRESS_ROOT/config/installer"
install -Dm0644 "$inst/settings.conf" "$inc/etc/calamares/settings.conf"
for conf in "$inst"/modules/*.conf; do
  install -Dm0644 "$conf" "$inc/etc/calamares/modules/$(basename "$conf")"
done

brand="$inc/etc/calamares/branding/gntress"
install -Dm0644 "$inst/branding/gntress/branding.desc" "$brand/branding.desc"
install -Dm0644 "$GNTRESS_ROOT/apps/launcher/icons/icon.png" "$brand/icon.png"
install -Dm0644 "$GNTRESS_ROOT/apps/launcher/icons/icon.png" "$brand/logo.png"
install -Dm0644 "$wall/gntress-genesis.jpg" "$brand/welcome.jpg"

install -Dm0755 "$GNTRESS_ROOT/scripts/installer/gntress-installer" \
  "$inc/usr/bin/gntress-installer"
install -Dm0755 "$GNTRESS_ROOT/scripts/installer/postinstall.sh" \
  "$inc/usr/local/lib/gntress/postinstall.sh"
install -Dm0644 "$inst/gntress-installer.desktop" \
  "$inc/usr/share/applications/gntress-installer.desktop"
# Hide Calamares' own entry so only one installer shows up in the launcher.
install -Dm0644 "$inst/calamares.desktop" \
  "$inc/usr/share/applications/calamares.desktop"

docker run --rm --privileged \
  -v "$live:/build" \
  -v "$GNTRESS_ROOT:/gntress:ro" \
  -v "$GNTRESS_CACHE_DIR/apt:/var/cache/apt" \
  -e GNTRESS_SUITE="$GNTRESS_SUITE" \
  -e GNTRESS_MIRROR="$GNTRESS_MIRROR" \
  -e GNTRESS_NAME="$GNTRESS_NAME" \
  -e GNTRESS_VERSION="$GNTRESS_VERSION" \
  -e GNTRESS_UID="$(id -u)" \
  -e GNTRESS_GID="$(id -g)" \
  "$GNTRESS_ISO_IMAGE" \
  sh /gntress/scripts/container-iso.sh

iso="$(find "$live" -maxdepth 1 -type f -name '*.iso' -print -quit)"
[ -n "$iso" ] || die "ISO tidak ditemukan setelah lb build (lihat log di $live)"

mkdir -p "$GNTRESS_OUT_DIR"
cp -f "$iso" "$GNTRESS_OUT_DIR/"
log "ISO: $GNTRESS_OUT_DIR/$(basename "$iso")"
