#!/usr/bin/env bash
# Runs inside the VM container: boots the ISO (live) or the installed disk and
# optionally saves screenshots. The live medium reaches the installer on its own,
# so the guest is never driven from here.
#
# Arguments: <iso|""> <uefi|bios> <seconds>
# Configuration comes from GNTREES_VM_* environment variables set by vm.sh.
set -euo pipefail

iso="${1:-}"
mode="${2:-uefi}"
seconds="${3:-900}"

as_bool() {
  case "${1,,}" in
    1 | yes | true | on) printf 1 ;;
    *) printf 0 ;;
  esac
}

shots="$(as_bool "${GNTREES_VM_SHOTS:-0}")"
fresh="$(as_bool "${GNTREES_VM_FRESH:-0}")"
disk="${GNTREES_VM_DISK:-24}"
case "$disk" in '' | *[!0-9]*) disk=0 ;; esac
case "$seconds" in '' | *[!0-9]*) seconds=900 ;; esac

mkdir -p /vm-out
# Drop screenshots from the previous run so the output directory only ever
# reflects this run, whether or not capturing is enabled.
rm -f /vm-out/shot-*.ppm /vm-out/shot-*.png

sendkey() {
  printf 'sendkey %s\n' "$1" | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
}

screendump() {
  printf 'screendump %s\n' "$1" | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
}

args=(
  -m 4096 -smp 2 -vga std -no-reboot
  -display none -vnc :1
  -monitor unix:/tmp/qmon,server,nowait
)

# Installed mode boots the disk only; live mode boots the ISO and can offer the
# same disk as the installation target.
if [ -n "$iso" ]; then
  args+=(-cdrom "$iso" -boot d)
else
  args+=(-boot c)
fi

if [ "$disk" -gt 0 ]; then
  disk_path=/vm-out/disk.qcow2
  [ "$fresh" = "1" ] && rm -f "$disk_path"
  if [ ! -f "$disk_path" ]; then
    qemu-img create -f qcow2 "$disk_path" "${disk}G" >/dev/null
    echo "== disk target baru: ${disk} GiB"
  else
    echo "== disk target dipakai ulang: $disk_path"
  fi
  args+=(-drive "file=$disk_path,if=virtio,format=qcow2")
fi

if [ -w /dev/kvm ]; then
  args+=(-enable-kvm)
else
  echo "warn: /dev/kvm tidak bisa diakses, QEMU jalan tanpa akselerasi"
fi

if [ "$mode" = "uefi" ]; then
  code=
  for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [ -f "$f" ] && { code="$f"; break; }
  done
  vars=
  for f in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [ -f "$f" ] && { vars="$f"; break; }
  done
  [ -n "$code" ] && [ -n "$vars" ] || { echo "OVMF tidak ditemukan" >&2; exit 1; }

  cp "$vars" /tmp/vars.fd
  args+=(
    -machine q35
    -drive "if=pflash,format=raw,readonly=on,file=$code"
    -drive "if=pflash,format=raw,file=/tmp/vars.fd"
  )
else
  args+=(-machine pc)
fi

qemu-system-x86_64 "${args[@]}" >/tmp/qemu.log 2>&1 &
qemu_pid=$!
trap 'kill "$qemu_pid" 2>/dev/null || true; exit 0' INT TERM

# GRUB pauses at the menu; pick the default entry once it is up. After that the
# live medium goes straight into the installer kiosk, so there is nothing left
# to type on the guest.
sleep 12
sendkey ret

# --- keep the VM alive, optionally capturing screenshots -------------------
if [ "$(as_bool "${GNTREES_VM_VNC:-0}")" = "1" ]; then
  echo "== VNC: vnc://127.0.0.1:5901 (Ctrl+C untuk berhenti)"
else
  echo "== VM berjalan tanpa VNC (Ctrl+C untuk berhenti)"
fi
elapsed=0
shot=0
while [ "$seconds" -eq 0 ] || [ "$elapsed" -lt "$seconds" ]; do
  sleep 15
  elapsed=$((elapsed + 15))
  if [ "$shots" = "1" ]; then
    shot=$((shot + 1))
    screendump "$(printf '/vm-out/shot-%02d.png' "$shot")"
  fi
done

kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true

echo "== qemu log:"
tail -n 8 /tmp/qemu.log || true

chown -R "${GNTREES_UID:-0}:${GNTREES_GID:-0}" /vm-out 2>/dev/null || true
echo "== isi /vm-out:"
ls -1 /vm-out
