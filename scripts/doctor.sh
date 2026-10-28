#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "gntress-os doctor"

printf 'repo             : %s\n' "$GNTRESS_ROOT"
printf 'filesystem repo  : %s\n' "$(fs_type "$GNTRESS_ROOT")"
printf 'build dir        : %s\n' "$GNTRESS_BUILD_DIR"
printf 'suite            : %s\n' "$GNTRESS_SUITE"
printf 'cpu              : %s jobs (host: %s threads)\n' "$GNTRESS_JOBS" "$(nproc 2>/dev/null || echo '?')"
printf 'ram              : %s\n' "$(awk '/^MemTotal:/ {printf "%.1f GiB", $2/1048576}' /proc/meminfo)"
printf 'swap             : %s\n' "$(awk '/^SwapTotal:/ {if ($2 == 0) print "0 (tidak ada)"; else printf "%.1f GiB", $2/1048576}' /proc/meminfo)"

case "$(fs_type "$GNTRESS_ROOT")" in
  ntfs*|fuseblk)
    warn "repo ada di NTFS. Jangan build di sini; artefak sudah diarahkan ke build dir." ;;
esac

mkdir -p "$GNTRESS_BUILD_DIR"
room="$(df -Pk "$GNTRESS_BUILD_DIR" | awk 'NR == 2 {print int($4 / 1048576)}')"
printf 'free build dir   : %s GiB\n' "${room:-0}"
[ "${room:-0}" -ge 25 ] || warn "ruang < 25 GiB; compile COSMIC + ISO butuh ~25-40 GiB"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  log "docker: ok"
else
  warn "docker belum siap; install docker dan pastikan user ada di grup 'docker'"
fi

if command -v just >/dev/null 2>&1; then
  log "just di host: $(just --version 2>/dev/null || echo '?')"
else
  log "just di host: tidak ada (container memakai just sendiri)"
fi

log "selesai"
