#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
[ -x "$GNTREES_ROOTFS_DIR/usr/bin/cosmic-session" ] \
  || die "rootfs belum siap; jalankan 'just stage' dulu"
[ -x "$GNTREES_ROOTFS_DIR/usr/bin/gntrees-launcher" ] \
  || die "launcher belum dibangun; jalankan 'just app' dulu"
ensure_build_dirs
mkdir -p "$GNTREES_CACHE_DIR/apt"

target_iso="$(default_iso)"
stamp="$GNTREES_OUT_DIR/.iso-fingerprint"
# Skip the whole build when nothing that feeds the ISO changed. Set
# GNTREES_FORCE_ISO=1 to rebuild regardless.
if [ "${GNTREES_FORCE_ISO:-0}" != "1" ] && [ -f "$target_iso" ] && [ -f "$stamp" ] \
   && [ "$(cat "$stamp")" = "$(iso_fingerprint)" ]; then
  log "input ISO tidak berubah; lewati build ($target_iso)"
  exit 0
fi

log "build image: $GNTREES_ISO_IMAGE"
docker build -q -t "$GNTREES_ISO_IMAGE" \
  -f "$GNTREES_ROOT/containers/ubuntu-iso.Dockerfile" "$GNTREES_ROOT/containers" >/dev/null

live="$GNTREES_LIVE_DIR"
log "siapkan live-build tree di $live"
remove_tree "$live"
mkdir -p "$live"
cp -a "$GNTREES_ROOT/profile/ubuntu/." "$live/"

# --- gntrees package repository --------------------------------------------
# The ISO installs gntrees-os-release from the published repository (see the chroot
# hook) instead of copying loose files, so dpkg owns them from the first boot.
# Both inputs live outside the tree: the URL in config/build.conf and the
# keyring in the build cache.
[ -n "$GNTREES_APT_URL" ] || die "GNTREES_APT_URL kosong; set di config/build.conf"
keyring="${GNTREES_KEYRING_FILE:-$GNTREES_BUILD_DIR/keys/gntrees-archive-keyring.asc}"
[ -f "$keyring" ] || die "keyring tidak ditemukan: $keyring"
archives="$live/config/archives"
mkdir -p "$archives"
# No signed-by here: live-build copies the key below into trusted.gpg.d under
# the name gntrees.key.chroot.gpg, and apt reads every *.gpg in that directory.
# A signed-by pointing at a differently named file would fail verification.
printf 'deb %s %s main\n' \
  "$GNTREES_APT_URL" "$GNTREES_APT_SUITE" > "$archives/gntrees.list.chroot"
# live-build reads this file as a binary keyring, so dearmor ASCII armor.
if head -c 5 "$keyring" | grep -q -- '-----'; then
  gpg --batch --dearmor < "$keyring" > "$archives/gntrees.key.chroot"
else
  cp "$keyring" "$archives/gntrees.key.chroot"
fi
# GNTREES_DNS overrides the resolver for the build container, which is useful
# when the local router serves stale or partial answers. In that case the
# reachability check resolves through the same server instead of curl.
apt_host="${GNTREES_APT_URL#*://}"
apt_host="${apt_host%%/*}"
if [ -n "${GNTREES_DNS:-}" ] && command -v dig >/dev/null 2>&1; then
  dig +short "@$GNTREES_DNS" A "$apt_host" | grep -q '^[0-9]' \
    || die "repo tidak bisa diresolusi lewat $GNTREES_DNS: $apt_host"
elif command -v curl >/dev/null 2>&1; then
  curl -fsS -o /dev/null "$GNTREES_APT_URL/dists/$GNTREES_APT_SUITE/InRelease" \
    || die "repo tidak bisa diakses: $GNTREES_APT_URL"
fi

inc="$live/config/includes.chroot"
mkdir -p "$inc"
cp -a "$GNTREES_ROOTFS_DIR/." "$inc/"

# Keep the repository configured on the installed system. live-build deletes
# config/archives entries after package installation and names the build-time
# keyring gntrees.key.chroot.gpg, so ship a differently named source plus a
# properly named keyring through includes.chroot.
install -Dm0644 "$archives/gntrees.key.chroot" \
  "$inc/etc/apt/trusted.gpg.d/gntrees.gpg"
mkdir -p "$inc/etc/apt/sources.list.d"
printf 'deb [signed-by=/etc/apt/trusted.gpg.d/gntrees.gpg] %s %s main\n' \
  "$GNTREES_APT_URL" "$GNTREES_APT_SUITE" \
  > "$inc/etc/apt/sources.list.d/zz-gntrees.list"
# The live medium boots into the installer kiosk, not a desktop session.
install -Dm0644 "$GNTREES_ROOT/config/greetd-live.toml" "$inc/etc/greetd/config.toml"
# unpackfs copies the squashfs (including /etc/greetd/config.toml) to the target,
# so keep the desktop config alongside for postinstall.sh to restore.
install -Dm0644 "$GNTREES_ROOT/config/greetd.toml" \
  "$inc/usr/local/lib/gntrees/greetd-desktop.toml"

# --- desktop payload -------------------------------------------------------
wall="$GNTREES_ROOT/config/wallpaper"
install -Dm0644 "$wall/gntrees-genesis.jpg" \
  "$inc/usr/share/backgrounds/gntrees/genesis.jpg"
# cosmic-bg's compiled-in fallback points at this path, so a broken config still
# leaves a wallpaper instead of a bare compositor colour.
install -Dm0644 "$wall/gntrees-genesis.jpg" \
  "$inc/usr/share/backgrounds/cosmic/orion_nebula_nasa_heic0601a.jpg"
install -Dm0644 "$wall/cosmic-background.ron" \
  "$inc/usr/share/cosmic/com.system76.CosmicBackground/v1/all"

# Super and Super+/ must open our launcher; cosmic-launcher is not in this image.
shortcuts="$inc/usr/share/cosmic/com.system76.CosmicSettings.Shortcuts/v1/system_actions"
[ -f "$shortcuts" ] || die "system_actions tidak ada di rootfs; cek 'just stage'"
sed -i 's/^\([[:space:]]*\)Launcher: "cosmic-launcher",/\1Launcher: "gntrees-launcher",/' "$shortcuts"
grep -q 'Launcher: "gntrees-launcher"' "$shortcuts" \
  || die "gagal memetakan aksi Launcher ke gntrees-launcher"

# COSMIC has no wallpaper icons; the visible shortcuts are the Dock button and the
# App Tray. The Dock launcher button execs the desktop entry named
# com.system76.CosmicLauncher, which belongs to cosmic-launcher (not in this
# image), so the applet fails to start. Point that id at our launcher.
launcher_desktop="$GNTREES_ROOT/apps/launcher/data/gntrees-launcher.desktop"
install -Dm0644 "$launcher_desktop" \
  "$inc/usr/share/applications/gntrees-launcher.desktop"
install -Dm0644 "$launcher_desktop" \
  "$inc/usr/share/applications/com.system76.CosmicLauncher.desktop"
for size in 256 512; do
  install -Dm0644 "$GNTREES_ROOT/apps/launcher/icons/icon.png" \
    "$inc/usr/share/icons/hicolor/${size}x${size}/apps/gntrees-launcher.png"
done

# Pin it in the App Tray too, so it stays reachable when the Dock button is hidden.
favorites="$inc/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites"
[ -f "$favorites" ] || die "favorites tidak ada di rootfs; cek 'just stage'"
if ! grep -q '"gntrees-launcher"' "$favorites"; then
  sed -i '/^[[:space:]]*]/i\    "gntrees-launcher",' "$favorites"
fi
grep -q '"gntrees-launcher"' "$favorites" \
  || die "gagal menambahkan gntrees-launcher ke App Tray"

# --- disk installer --------------------------------------------------------
inst="$GNTREES_ROOT/config/installer"
install -Dm0644 "$inst/settings.conf" "$inc/etc/calamares/settings.conf"
for conf in "$inst"/modules/*.conf; do
  install -Dm0644 "$conf" "$inc/etc/calamares/modules/$(basename "$conf")"
done

brand="$inc/etc/calamares/branding/gntrees"
install -Dm0644 "$inst/branding/gntrees/branding.desc" "$brand/branding.desc"
install -Dm0644 "$GNTREES_ROOT/apps/launcher/icons/icon.png" "$brand/icon.png"
install -Dm0644 "$GNTREES_ROOT/apps/launcher/icons/icon.png" "$brand/logo.png"
install -Dm0644 "$wall/gntrees-genesis.jpg" "$brand/welcome.jpg"

install -Dm0755 "$GNTREES_ROOT/scripts/installer/gntrees-installer" \
  "$inc/usr/bin/gntrees-installer"
install -Dm0755 "$GNTREES_ROOT/scripts/installer/live-session" \
  "$inc/usr/bin/gntrees-live-session"
install -Dm0755 "$GNTREES_ROOT/scripts/installer/postinstall.sh" \
  "$inc/usr/local/lib/gntrees/postinstall.sh"
install -Dm0755 "$GNTREES_ROOT/scripts/installer/grub-install" \
  "$inc/usr/local/lib/gntrees/grub-install"
install -Dm0644 "$inst/gntrees-installer.desktop" \
  "$inc/usr/share/applications/gntrees-installer.desktop"
# Hide Calamares' own entry so only one installer shows up in the launcher.
install -Dm0644 "$inst/calamares.desktop" \
  "$inc/usr/share/applications/calamares.desktop"

dns_args=()
[ -n "${GNTREES_DNS:-}" ] && dns_args+=(--dns "$GNTREES_DNS")

docker run --rm --privileged \
  "${dns_args[@]}" \
  -v "$live:/build" \
  -v "$GNTREES_ROOT:/gntrees:ro" \
  -v "$GNTREES_CACHE_DIR/apt:/var/cache/apt" \
  -e GNTREES_SUITE="$GNTREES_SUITE" \
  -e GNTREES_MIRROR="$GNTREES_MIRROR" \
  -e GNTREES_NAME="$GNTREES_NAME" \
  -e GNTREES_VERSION="$GNTREES_VERSION" \
  -e GNTREES_UID="$(id -u)" \
  -e GNTREES_GID="$(id -g)" \
  "$GNTREES_ISO_IMAGE" \
  sh /gntrees/scripts/container-iso.sh

iso="$(find "$live" -maxdepth 1 -type f -name '*.iso' -print -quit)"
[ -n "$iso" ] || die "ISO tidak ditemukan setelah lb build (lihat log di $live)"

mkdir -p "$GNTREES_OUT_DIR"
cp -f "$iso" "$GNTREES_OUT_DIR/"
iso_fingerprint > "$stamp"
log "ISO: $GNTREES_OUT_DIR/$(basename "$iso")"
