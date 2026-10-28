#!/usr/bin/env bash
# Boots the built ISO in a KVM-accelerated VM and captures screenshots.
# Usage: scripts/vm.sh [iso] [uefi|bios] [seconds] [login] [install] [disk-gb] [vnc]
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

iso="${1:-$GNTRESS_OUT_DIR/$GNTRESS_NAME-$GNTRESS_VERSION-$GNTRESS_ARCH.iso}"
mode="${2:-uefi}"
seconds="${3:-120}"
login="${4:-0}"
install="${5:-0}"
disk="${6:-0}"
vnc="${7:-0}"

docker_ok
[ -f "$iso" ] || die "ISO tidak ditemukan: $iso (jalankan 'just iso' dulu)"
case "$mode" in
  uefi | bios) ;;
  *) die "mode harus 'uefi' atau 'bios'" ;;
esac
case "$disk" in
  '' | 0) disk=0 ;;
  *[!0-9]*) die "ukuran disk harus bilangan bulat GiB (contoh: 16)" ;;
esac

vm_out="$GNTRESS_CACHE_DIR/vm"
mkdir -p "$vm_out"

log "build image: $GNTRESS_VM_IMAGE"
docker build -q -t "$GNTRESS_VM_IMAGE" \
  -f "$GNTRESS_ROOT/containers/vm.Dockerfile" "$GNTRESS_ROOT/containers" >/dev/null

log "boot $mode selama ${seconds}s; tangkapan layar di $vm_out"
[ "$disk" -gt 0 ] || disk=0
[ "$disk" -gt 0 ] && log "disk target: ${disk} GiB kosong (dibuat ulang tiap run)"
[ "$vnc" = "1" ] && log "VNC: vncviewer 127.0.0.1:5901 (hanya localhost)"

docker_args=(
  --rm
  --device /dev/kvm
  -v "$(dirname "$iso"):/isos:ro"
  -v "$vm_out:/vm-out"
  -v "$GNTRESS_ROOT:/gntress:ro"
  -e "GNTRESS_UID=$(id -u)"
  -e "GNTRESS_GID=$(id -g)"
  -e "GNTRESS_VM_LOGIN=$login"
  -e "GNTRESS_VM_INSTALL=$install"
  -e "GNTRESS_VM_DEBUG=${GNTRESS_VM_DEBUG:-0}"
  -e "GNTRESS_VM_DISK=$disk"
)
# QEMU already runs with `-vnc :1`; publish it only when asked so the default
# run stays headless.
[ "$vnc" = "1" ] && docker_args+=(-p 127.0.0.1:5901:5901)

docker run "${docker_args[@]}" "$GNTRESS_VM_IMAGE" \
  bash /gntress/scripts/container-vm.sh "/isos/$(basename "$iso")" "$mode" "$seconds"
