#!/usr/bin/env bash
# Runs inside the build container. Staged rootfs at /rootfs, per-component COSMIC
# trees at /pkg, packages to /out/deb. Every path can be overridden, so the same
# script works on the host for a quick check without Docker.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

src="$GNTREES_ROOT"
root="${GNTREES_STAGE_ROOT:-/rootfs}"
pkg_root="${GNTREES_PKG_ROOT:-/pkg}"
out="${GNTREES_DEB_OUT:-/out/deb}"
version="${GNTREES_VERSION}-gntrees${GNTREES_DEB_REV:-1}"
arch="${GNTREES_ARCH:-amd64}"
work="${TMPDIR:-/tmp}/gntrees-deb"
# Filled in for the release metapackage; empty for every other control template.
deps=""

[ -x "$root/usr/bin/gntrees-launcher" ] \
  || die "launcher tidak ada di rootfs; jalankan 'just app' dulu"
[ -f "$root/usr/share/cosmic/com.system76.CosmicAppList/v1/favorites" ] \
  || die "rootfs belum siap; jalankan 'just stage' dulu"

rm -rf "$work"
mkdir -p "$work" "$out"
rm -f "$out"/*.deb

# build_pkg <package> <template domain>: payload is $work/<package>/root.
build_pkg() {
  local name="$1" domain="$2" dir size
  dir="$work/$name/root"
  size="$(du -sk "$dir" | cut -f1)"
  mkdir -p "$dir/DEBIAN"
  sed -e "s/@VERSION@/$version/g" \
      -e "s/@ARCH@/$arch/g" \
      -e "s/@INSTALLED_SIZE@/$size/g" \
      -e "s/@DEPENDS@/$deps/g" \
      "$src/packaging/$domain/control" > "$dir/DEBIAN/control"
  chmod 0644 "$dir/DEBIAN/control"
  if [ -f "$src/packaging/$domain/postinst" ]; then
    install -Dm0755 "$src/packaging/$domain/postinst" "$dir/DEBIAN/postinst"
  fi
  if [ -f "$src/packaging/$domain/triggers" ]; then
    install -Dm0644 "$src/packaging/$domain/triggers" "$dir/DEBIAN/triggers"
  fi
  dpkg-deb --root-owner-group --build "$dir" \
    "$out/${name}_${version}_${arch}.deb" >/dev/null
  log "$(basename "$out/${name}_${version}_${arch}.deb")"
}

# --- launcher: binary, desktop entry, icons --------------------------------
p="$work/gntrees-os-launcher/root"
install -Dm0755 "$root/usr/bin/gntrees-launcher" "$p/usr/bin/gntrees-launcher"
install -Dm0644 "$src/apps/launcher/data/gntrees-launcher.desktop" \
  "$p/usr/share/applications/gntrees-launcher.desktop"
for px in 256 512; do
  install -Dm0644 "$src/apps/launcher/icons/icon.png" \
    "$p/usr/share/icons/hicolor/${px}x${px}/apps/gntrees-launcher.png"
done
build_pkg gntrees-os-launcher launcher

# --- desktop: COSMIC defaults that point the session at the launcher --------
p="$work/gntrees-os-desktop/root"
wall="$src/config/wallpaper"
install -Dm0644 "$wall/gntrees-genesis.jpg" \
  "$p/usr/share/backgrounds/gntrees/genesis.jpg"
# cosmic-bg's compiled-in fallback points at this path.
install -Dm0644 "$wall/gntrees-genesis.jpg" \
  "$p/usr/share/backgrounds/cosmic/orion_nebula_nasa_heic0601a.jpg"
# system_actions, favorites, and CosmicBackground/v1/all belong to the COSMIC
# packages. Shipping them here would conflict and block their upgrades, so the
# postinst/triggers in packaging/desktop apply our values after unpack instead.
install -Dm0644 "$wall/cosmic-background.ron" \
  "$p/usr/share/gntrees-os/defaults/cosmic-background-all"
# The Dock launcher button execs the entry id com.system76.CosmicLauncher, which
# belongs to cosmic-launcher (not shipped); point that id at our launcher.
install -Dm0644 "$src/apps/launcher/data/gntrees-launcher.desktop" \
  "$p/usr/share/applications/com.system76.CosmicLauncher.desktop"
build_pkg gntrees-os-desktop desktop

# --- config: greeter carried from the live medium to the installed system ---
p="$work/gntrees-os-config/root"
install -Dm0644 "$src/config/greetd.toml" \
  "$p/usr/local/lib/gntrees/greetd-desktop.toml"
build_pkg gntrees-os-config system

# --- release: metapackage plus the release stamp ---------------------------
# Our own packages share one exact version; the COSMIC components stay
# unversioned so a single component can be upgraded from the repository.
deps="gntrees-os-launcher (= $version), gntrees-os-desktop (= $version), gntrees-os-config (= $version)"
while read -r cosmic repo rev builder; do
  deps="$deps, $cosmic"
done < <(enabled_components)

p="$work/gntrees-os-release/root"
{
  printf 'GNTREES_NAME=%s\n' "$GNTREES_NAME"
  printf 'GNTREES_VERSION=%s\n' "$version"
  printf 'GNTREES_CODENAME=%s\n' "$GNTREES_CODENAME"
  printf 'GNTREES_BASE=%s %s\n' "$GNTREES_DISTRO" "$GNTREES_SUITE"
} > "$work/gntrees-os-release.stamp"
install -Dm0644 "$work/gntrees-os-release.stamp" "$p/etc/gntrees-release"
build_pkg gntrees-os-release release

# --- COSMIC components -----------------------------------------------------
# `just stage` installs each component into its own /pkg/<name> tree, so that
# tree is the payload here. Names stay upstream (cosmic-comp, cosmic-session,
# ...) so an installed system can update one component on its own.
cosmic_version="${GNTREES_COSMIC_VERSION:?}-gntrees${GNTREES_DEB_REV:-1}"
while read -r name repo rev builder; do
  payload="$pkg_root/$name"
  [ -d "$payload" ] \
    || die "payload COSMIC tidak ada: $payload (jalankan 'just stage' dulu)"
  p="$work/$name/root"
  mkdir -p "$p"
  cp -a "$payload/." "$p/"
  size="$(du -sk "$p" | cut -f1)"
  mkdir -p "$p/DEBIAN"
  sed -e "s/@PACKAGE@/$name/g" \
      -e "s/@VERSION@/$cosmic_version/g" \
      -e "s/@ARCH@/$arch/g" \
      -e "s/@INSTALLED_SIZE@/$size/g" \
      -e "s/@SECTION@/x11/g" \
      -e "s|@REPO@|$repo|g" \
      -e "s/@COMMIT@/${rev:0:12}/g" \
      -e "s|@DESCRIPTION@|COSMIC desktop component $name for gntrees-os|g" \
      "$src/packaging/cosmic/control" > "$p/DEBIAN/control"
  chmod 0644 "$p/DEBIAN/control"
  dpkg-deb --root-owner-group --build "$p" \
    "$out/${name}_${cosmic_version}_${arch}.deb" >/dev/null
  log "$(basename "$out/${name}_${cosmic_version}_${arch}.deb")"
done < <(enabled_components)

if [ -n "${GNTREES_UID:-}" ] && [ -n "${GNTREES_GID:-}" ]; then
  chown -R "${GNTREES_UID}:${GNTREES_GID}" "$out"
fi
