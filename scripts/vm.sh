#!/usr/bin/env bash
# Boots the live ISO or the installed disk in a KVM-accelerated VM.
#
# Everything is configured through optional GNTREES_VM_* variables; the two
# `just` recipes (vm-live, vm-installed) only set the ones that define intent.
#
#   GNTREES_VM_BOOT      live | installed          (default live)
#   GNTREES_VM_ISO       file ISO                  (default: same as `just usb`)
#   GNTREES_VM_MODE      uefi | bios               (default uefi)
#   GNTREES_VM_DISK      size in GiB               (default 24)
#   GNTREES_VM_FRESH     recreate the disk         (default 0)
#   GNTREES_VM_SECONDS   run time, 0 = until ^C    (default 900)
#   GNTREES_VM_VNC       publish 127.0.0.1:5901    (default 1)
#   GNTREES_VM_SHOTS     screenshots every 15 s    (default 0)
#   GNTREES_DNS          resolver for the guest, e.g. 1.1.1.1 (default: none)
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

as_bool() {
  case "${1,,}" in
    1 | yes | true | on) printf 1 ;;
    *) printf 0 ;;
  esac
}

boot="${GNTREES_VM_BOOT:-live}"
mode="${GNTREES_VM_MODE:-uefi}"
disk="${GNTREES_VM_DISK:-24}"
seconds="${GNTREES_VM_SECONDS:-900}"
vnc="$(as_bool "${GNTREES_VM_VNC:-1}")"
shots="$(as_bool "${GNTREES_VM_SHOTS:-0}")"
fresh="$(as_bool "${GNTREES_VM_FRESH:-0}")"

case "$boot" in
  live | installed) ;;
  *) die "GNTREES_VM_BOOT harus 'live' atau 'installed' (bukan '$boot')" ;;
esac
case "$mode" in
  uefi | bios) ;;
  *) die "GNTREES_VM_MODE harus 'uefi' atau 'bios' (bukan '$mode')" ;;
esac
case "$disk" in
  '' | *[!0-9]*) die "GNTREES_VM_DISK harus bilangan bulat GiB (contoh: 24)" ;;
esac
case "$seconds" in
  '' | *[!0-9]*) die "GNTREES_VM_SECONDS harus bilangan bulat (0 = sampai Ctrl+C)" ;;
esac

vm_out="$GNTREES_CACHE_DIR/vm"
mkdir -p "$vm_out"

iso=""
if [ "$boot" = "live" ]; then
  iso="${GNTREES_VM_ISO:-}"
  [ -n "$iso" ] || iso="$(default_iso)"
  [ -f "$iso" ] || die "ISO tidak ditemukan: $iso
  bangun dengan 'just iso', atau set GNTREES_VM_ISO=<file>"
else
  [ "$disk" -gt 0 ] || die "boot 'installed' butuh GNTREES_VM_DISK (GiB)"
  [ -f "$vm_out/disk.qcow2" ] || die "belum ada sistem terinstal di $vm_out/disk.qcow2
  jalankan 'just vm-live', instal ke /dev/vda, lalu ulangi"
fi

docker_ok

log "build image: $GNTREES_VM_IMAGE"
docker build -q -t "$GNTREES_VM_IMAGE" \
  -f "$GNTREES_ROOT/containers/vm.Dockerfile" "$GNTREES_ROOT/containers" >/dev/null

if [ "$seconds" -eq 0 ]; then
  log "boot $boot ($mode) sampai Ctrl+C"
else
  log "boot $boot ($mode) selama ${seconds}s"
fi
if [ "$disk" -gt 0 ]; then
  log "disk target: ${disk} GiB di $vm_out/disk.qcow2"
  [ "$fresh" = "1" ] && log "disk akan dibuat ulang (GNTREES_VM_FRESH=1)"
fi
[ "$shots" = "1" ] && log "screenshot: tiap 15s ke $vm_out"
[ "$vnc" = "1" ] && log "VNC: vncviewer 127.0.0.1:5901"

docker_args=(
  --rm
  --device /dev/kvm
  -v "$vm_out:/vm-out"
  -v "$GNTREES_ROOT:/gntrees:ro"
  -e "GNTREES_UID=$(id -u)"
  -e "GNTREES_GID=$(id -g)"
  -e "GNTREES_VM_SHOTS=$shots"
  -e "GNTREES_VM_VNC=$vnc"
  -e "GNTREES_VM_DISK=$disk"
  -e "GNTREES_VM_FRESH=$fresh"
)
if [ "$boot" = "live" ]; then
  iso_arg="/isos/$(basename "$iso")"
  docker_args+=(-v "$(dirname "$iso"):/isos:ro")
else
  iso_arg=""
fi
# QEMU always listens with `-vnc :1`; publishing is what makes it reachable.
[ "$vnc" = "1" ] && docker_args+=(-p 127.0.0.1:5901:5901)
# QEMU's user-mode DNS reads the container resolver, so --dns also fixes the
# guest when the local router serves stale answers.
[ -n "${GNTREES_DNS:-}" ] && docker_args+=(--dns "$GNTREES_DNS")

docker run "${docker_args[@]}" "$GNTREES_VM_IMAGE" \
  bash /gntrees/scripts/container-vm.sh "$iso_arg" "$mode" "$seconds"
