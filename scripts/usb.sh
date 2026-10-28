#!/usr/bin/env bash
# Copies the built ISO to the Ventoy partition and flushes it, with progress.
# Usage: scripts/usb.sh [mountpoint] [iso]
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mount_point="${1:-}"
iso="${2:-}"

bar() {
  local pct="$1" width=28 filled i out=
  filled=$(( pct * width / 100 ))
  for ((i = 0; i < width; i++)); do
    if [ "$i" -lt "$filled" ]; then out+="#"; else out+="."; fi
  done
  printf '%s' "$out"
}

human() {
  numfmt --to=iec --suffix=B --format='%.1f' "$1" 2>/dev/null || printf '%sB' "$1"
}

# Sum of pages waiting to be written plus pages under writeback.
dirty_kb() {
  awk '/^Dirty:/{d=$2} /^Writeback:/{w=$2} END{print d+w+0}' /proc/meminfo
}

# "MOUNTPOINT|LABEL|FSTYPE" for one line of `lsblk -P`.
lsblk_field() {
  local key="$1" line="$2"
  printf '%s\n' "$line" | sed -n "s/.*${key}=\"\([^\"]*\)\".*/\1/p"
}

detect_mount() {
  local line mp
  if command -v lsblk >/dev/null 2>&1; then
    while IFS= read -r line; do
      mp=$(lsblk_field MOUNTPOINT "$line")
      [ -n "$mp" ] && [ -d "$mp" ] \
        && [ "$(lsblk_field LABEL "$line")" = "Ventoy" ] \
        && { printf '%s\n' "$mp"; return 0; }
    done < <(lsblk -Pno MOUNTPOINT,LABEL,FSTYPE)
  fi
  for mp in /media/*/* /run/media/*/*; do
    [ -d "$mp/ventoy" ] && { printf '%s\n' "$mp"; return 0; }
  done
  return 1
}

copy_progress() {
  local src="$1" dst="$2" total start pid size=0 pct=0 rate=0 elapsed=0
  total=$(stat -c %s "$src")
  cp -- "$src" "$dst" &
  pid=$!
  start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    size=$(stat -c %s "$dst" 2>/dev/null || printf 0)
    elapsed=$(( $(date +%s) - start ))
    [ "$elapsed" -lt 1 ] && elapsed=1
    pct=$(( size * 100 / total ))
    rate=$(( size / elapsed ))
    printf '\r  [%s] %3d%%  %s / %s  %s/s  %ds  ' \
      "$(bar "$pct")" "$pct" "$(human "$size")" "$(human "$total")" "$(human "$rate")" "$elapsed"
    sleep 1
  done
  wait "$pid" || die "penyalinan gagal: $dst"
  printf '\r  [%s] 100%%  %s / %s  %ds  \n' \
    "$(bar 100)" "$(human "$total")" "$(human "$total")" "$elapsed"
}

sync_progress() {
  local total rem pct start pid elapsed=0
  total=$(dirty_kb)
  if [ "$total" -eq 0 ]; then
    printf '  [%s] 100%%  tidak ada data tertunda\n' "$(bar 100)"
    return 0
  fi
  sync &
  pid=$!
  start=$(date +%s)
  while kill -0 "$pid" 2>/dev/null; do
    rem=$(dirty_kb)
    [ "$rem" -gt "$total" ] && total=$rem
    pct=$(( (total - rem) * 100 / total ))
    [ "$pct" -lt 0 ] && pct=0
    elapsed=$(( $(date +%s) - start ))
    printf '\r  [%s] %3d%%  sisa %s  %ds  ' \
      "$(bar "$pct")" "$pct" "$(human $((rem * 1024)))" "$elapsed"
    sleep 1
  done
  wait "$pid" || die "sync gagal"
  printf '\r  [%s] 100%%  semua data sudah tertulis  %ds  \n' "$(bar 100)" "$elapsed"
}

[ -n "$iso" ] || iso="$GNTRESS_OUT_DIR/$GNTRESS_NAME-$GNTRESS_VERSION-$GNTRESS_ARCH.iso"
[ -f "$iso" ] || die "ISO tidak ditemukan: $iso (jalankan 'just iso' dulu)"

if [ -z "$mount_point" ]; then
  mount_point=$(detect_mount) \
    || die "partisi Ventoy tidak ditemukan; sebutkan manual: just usb /media/\$USER/Ventoy"
fi
[ -d "$mount_point" ] || die "bukan direktori: $mount_point"

dst="$mount_point/$(basename "$iso")"
part="$dst.part"
size=$(stat -c %s "$iso")
avail=$(df -Pk "$mount_point" | awk 'NR==2 { print $4 * 1024 }')
fstype=$(lsblk -no FSTYPE "$(findmnt -no SOURCE --target "$mount_point" 2>/dev/null)" 2>/dev/null | head -n 1)
[ -n "$fstype" ] || fstype=$(findmnt -no FSTYPE --target "$mount_point" 2>/dev/null || echo unknown)

[ "$avail" -ge "$size" ] \
  || die "ruang tidak cukup di $mount_point (butuh $(human "$size"), tersedia $(human "$avail"))"

log "sumber  : $iso ($(human "$size"))"
log "tujuan  : $mount_point ($fstype, tersedia $(human "$avail"))"
if [ -f "$dst" ]; then
  warn "menimpa ISO yang sudah ada di tujuan"
fi
case "$fstype" in
  *exfat*)
    warn "partisi exFAT: Ventoy 1.1.17 mengikuti rantai FAT dan bisa gagal boot;"
    warn "NTFS lebih aman untuk ISO ini."
    ;;
esac

log "menyalin"
copy_progress "$iso" "$part"
mv -f "$part" "$dst"

log "flush ke USB (jangan cabut, Ctrl+C tidak menghentikan flush)"
sync_progress

copied=$(stat -c %s "$dst")
[ "$copied" -eq "$size" ] || die "ukuran tidak cocok setelah sync ($copied != $size)"

log "selesai: $dst"
log "aman untuk dicabut"
