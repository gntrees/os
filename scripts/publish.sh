#!/usr/bin/env bash
# Uploads the signed APT tree and the built ISOs to Cloudflare R2 via rclone.
#
# Required:
#   GNTREES_PUBLISH_REMOTE   rclone destination, e.g. r2:gntrees-os-packages
# Optional:
#   GNTREES_APT_URL          public base URL, printed at the end
#   GNTREES_PUBLISH_DRY_RUN  1 passes --dry-run to every rclone call
#   GNTREES_PUBLISH_ISO      0 uploads only the repository, skipping ISOs
#
# Upload order matters: pool first, then the package index, and InRelease last,
# so a client never sees a signed index pointing at packages that are not there
# yet. Cache policy lives at the edge (Cloudflare): bypass for apt/dists/*,
# long immutable TTL for apt/pool/*, apt/*.asc, and iso/*.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require rclone

remote="${GNTREES_PUBLISH_REMOTE:-}"
[ -n "$remote" ] || die "set GNTREES_PUBLISH_REMOTE, contoh: r2:gntrees-os-packages"

suite="$GNTREES_APT_SUITE"
dists="$GNTREES_APT_DIR/dists/$suite"
[ -s "$dists/InRelease" ] \
  || die "repo belum ditandatangani; jalankan 'just repo' dengan GNTREES_SIGN_KEYFILE"
grep -q '^Valid-Until:' "$dists/Release" \
  || die "Release tanpa Valid-Until; jalankan ulang 'just repo'"

dry=()
[ "${GNTREES_PUBLISH_DRY_RUN:-0}" = "1" ] && dry+=(--dry-run)

log "publish repo: $GNTREES_APT_DIR -> $remote/$GNTREES_APT_PREFIX"
rclone copy "$GNTREES_APT_DIR/pool" "$remote/$GNTREES_APT_PREFIX/pool" \
  --checksum --s3-no-check-bucket "${dry[@]}"
rclone copy "$dists/main" "$remote/$GNTREES_APT_PREFIX/dists/$suite/main" \
  --checksum --s3-no-check-bucket "${dry[@]}"
for meta in Release Release.gpg InRelease; do
  rclone copyto "$dists/$meta" "$remote/$GNTREES_APT_PREFIX/dists/$suite/$meta" \
    --checksum --s3-no-check-bucket "${dry[@]}"
done
rclone copyto "$GNTREES_APT_DIR/gntrees-archive-keyring.asc" \
  "$remote/$GNTREES_APT_PREFIX/gntrees-archive-keyring.asc" \
  --checksum --s3-no-check-bucket "${dry[@]}"

if [ "${GNTREES_PUBLISH_ISO:-1}" = "1" ]; then
  log "publish ISO: $GNTREES_OUT_DIR -> $remote/iso"
  rclone copy "$GNTREES_OUT_DIR" "$remote/iso" \
    --include '*.iso' --include '*.zsync' --checksum \
    --s3-no-check-bucket "${dry[@]}"
else
  log "ISO tidak dipublikasikan (GNTREES_PUBLISH_ISO=0)"
fi

if [ "${GNTREES_PUBLISH_DRY_RUN:-0}" != "1" ]; then
  rclone lsf "$remote/$GNTREES_APT_PREFIX/dists/$suite/" \
    | grep -qx InRelease \
    || die "InRelease tidak terlihat di remote setelah upload"
fi

if [ -n "${GNTREES_APT_URL:-}" ]; then
  log "repo publik: $GNTREES_APT_URL"
  log "keyring: $GNTREES_APT_URL/gntrees-archive-keyring.asc"
fi
