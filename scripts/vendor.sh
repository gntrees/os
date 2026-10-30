#!/usr/bin/env bash
# Downloads the external app artifacts pinned in config/vendor.lock (kind: script,
# domain: vendor). Idempotent: already-verified files are left alone.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require curl sha256sum
ensure_build_dirs
mkdir -p "$GNTREES_CACHE_DIR/vendor"

while read -r name type url sha; do
  [ -n "$url" ] && [ -n "$sha" ] || die "vendor.lock: entri '$name' tidak lengkap"
  case "$type" in
    deb | tar) ;;
    *) die "vendor.lock: tipe '$type' untuk '$name' tidak dikenal" ;;
  esac

  file="$(vendor_file "$name")"
  part="$file.part"

  if [ -f "$file" ] && [ "$(sha256sum "$file" | awk '{ print $1 }')" = "$sha" ]; then
    log "$name: sudah ada ($(basename "$file"))"
    continue
  fi

  log "$name: unduh $(basename "$file")"
  curl -fL --retry 3 --progress-bar -o "$part" "$url" || die "$name: unduh gagal"

  actual=$(sha256sum "$part" | awk '{ print $1 }')
  if [ "$actual" != "$sha" ]; then
    rm -f "$part"
    die "$name: sha256 tidak cocok (dapat $actual)"
  fi

  mv -f "$part" "$file"
  log "$name: sha256 ok"
done < <(awk '!/^[[:space:]]*#/ && NF >= 4 { print $1, $2, $3, $4 }' "$GNTREES_ROOT/config/vendor.lock")

log "artefak vendor siap di $GNTREES_CACHE_DIR/vendor"
