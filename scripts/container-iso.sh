#!/bin/sh
# Runs inside the ISO container. The live-build tree is mounted at /build.
set -eu

# live-build runs as root. Hand the tree back to the host user on the way out,
# including on failure, so `just clean` and the next rm -rf need no sudo.
hand_back() {
  if [ -n "${GNTREES_UID:-}" ] && [ -n "${GNTREES_GID:-}" ]; then
    chown -R "${GNTREES_UID}:${GNTREES_GID}" /build /var/cache/apt 2>/dev/null || true
  fi
}
trap hand_back EXIT

cd /build

lb config noauto \
  --mode ubuntu \
  --distribution "${GNTREES_SUITE:?}" \
  --architectures amd64 \
  --archive-areas "main restricted universe multiverse" \
  --mirror-bootstrap "${GNTREES_MIRROR:?}" \
  --mirror-chroot "${GNTREES_MIRROR:?}" \
  --mirror-binary "${GNTREES_MIRROR:?}" \
  --linux-packages linux-image \
  --linux-flavours generic \
  --binary-images iso \
  --bootloader grub2 \
  --initramfs live-boot \
  --initsystem systemd \
  --debian-installer false \
  --memtest none \
  --bootappend-live "components quiet splash noeject" \
  --iso-application "${GNTREES_NAME:-gntrees-os}" \
  --iso-preparer "gntrees-os build" \
  --iso-publisher "gntrees-os" \
  --iso-volume "GNTREES_OS" \
  --apt-source-archives false \
  --zsync false \
  --compression xz

lb build

# live-build 3.0~a57 only assembles BIOS El Torito images, and its isohybrid
# step rejects grub2. Rebuild from binary/ so the ISO is hybrid and boots on
# both BIOS and UEFI.
rm -f /build/*.iso
grub-mkrescue -o "/build/${GNTREES_NAME:?}-${GNTREES_VERSION:?}-amd64.iso" /build/binary \
  -- -volid GNTREES_OS
