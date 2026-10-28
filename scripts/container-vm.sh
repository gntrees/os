#!/usr/bin/env bash
# Runs inside the VM container: boots the ISO, screenshots it, then stops.
set -euo pipefail

iso="${1:?iso}"
mode="${2:-uefi}"
seconds="${3:-120}"

mkdir -p /vm-out
rm -f /vm-out/shot-*.ppm /vm-out/shot-*.png

args=(
  -m 4096 -smp 2 -vga std -boot d -no-reboot
  -cdrom "$iso"
  -display none -vnc :1
  -monitor unix:/tmp/qmon,server,nowait
)

# Optional blank target disk so Calamares has a device to install onto.
disk="${GNTRESS_VM_DISK:-0}"
case "$disk" in
  '' | *[!0-9]*) disk=0 ;;
esac
if [ "$disk" -gt 0 ]; then
  # Always start from an empty disk; the point is to exercise partitioning.
  rm -f /vm-out/disk.qcow2
  qemu-img create -f qcow2 /vm-out/disk.qcow2 "${disk}G" >/dev/null
  args+=(-drive "file=/vm-out/disk.qcow2,if=virtio,format=qcow2")
  echo "== disk target: ${disk} GiB (/vm-out/disk.qcow2)"
fi

if [ -w /dev/kvm ]; then
  args+=(-enable-kvm)
else
  echo "warn: /dev/kvm tidak bisa diakses, QEMU jalan tanpa akselerasi"
fi

if [ "$mode" = uefi ]; then
  code=
  for f in /usr/share/OVMF/OVMF_CODE_4M.fd /usr/share/OVMF/OVMF_CODE.fd; do
    [ -f "$f" ] && { code="$f"; break; }
  done
  vars=
  for f in /usr/share/OVMF/OVMF_VARS_4M.fd /usr/share/OVMF/OVMF_VARS.fd; do
    [ -f "$f" ] && { vars="$f"; break; }
  done
  [ -n "$code" ] && [ -n "$vars" ] || { echo "OVMF tidak ditemukan"; exit 1; }

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

# GRUB waits for a key press; boot the default entry once the menu is up.
sleep 12
printf 'sendkey ret\n' | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true

# Optional: authenticate into the live session (user / live) so the harness can
# verify the desktop, panel and launcher rather than just the greeter.
if [ "${GNTRESS_VM_LOGIN:-0}" = "1" ]; then
  sleep 45
  for key in u s e r ret; do
    printf 'sendkey %s\n' "$key" | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
    sleep 0.4
  done
  sleep 1
  for key in l i v e ret; do
    printf 'sendkey %s\n' "$key" | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
    sleep 0.4
  done
fi

shot=0
elapsed=0
while [ "$elapsed" -lt "$seconds" ]; do
  sleep 15
  elapsed=$((elapsed + 15))
  shot=$((shot + 1))
  printf 'screendump /vm-out/shot-%02d.ppm\n' "$shot" \
    | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
done

# Press Super once the session is up: the launcher should appear.
printf 'sendkey meta_l\n' | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
# WebKit needs a moment to paint its first frame, especially under emulation.
sleep 20
printf 'screendump /vm-out/shot-launcher.ppm\n' \
  | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
sleep 10
printf 'screendump /vm-out/shot-launcher2.ppm\n' \
  | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true

# Optional: launch the installer from the launcher and capture the result.
if [ "${GNTRESS_VM_INSTALL:-0}" = "1" ]; then
  type_text() {
    local text="$1" ch key i
    for ((i = 0; i < ${#text}; i++)); do
      ch="${text:i:1}"
      case "$ch" in
        ' ') key=spc ;;
        '-') key=minus ;;
        '/') key=slash ;;
        '.') key=dot ;;
        '=') key=equal ;;
        ';') key=semicolon ;;
        *) key="$ch" ;;
      esac
      printf 'sendkey %s\n' "$key" | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
      sleep 0.15
    done
    printf 'sendkey ret\n' | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
  }

  if [ "${GNTRESS_VM_DEBUG:-0}" = "1" ]; then
    # Bisect: does the launcher spawn at all, and what does Calamares say?
    type_text "alacritty"
    sleep 20
    printf 'screendump /vm-out/shot-terminal.ppm\n' \
      | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
    type_text "gntress-installer"
    sleep 30
    printf 'screendump /vm-out/shot-installer.ppm\n' \
      | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
  else
    type_text "gntress"
    # Calamares is Qt: give it time to open its first window.
    sleep 35
    printf 'screendump /vm-out/shot-installer.ppm\n' \
      | socat - UNIX-CONNECT:/tmp/qmon >/dev/null 2>&1 || true
  fi
fi

kill "$qemu_pid" 2>/dev/null || true
wait "$qemu_pid" 2>/dev/null || true

echo "== qemu log:"
tail -n 8 /tmp/qemu.log || true

chown -R "${GNTRESS_UID:-0}:${GNTRESS_GID:-0}" /vm-out 2>/dev/null || true
echo "== tangkapan layar:"
ls -1 /vm-out
