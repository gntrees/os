#!/usr/bin/env bash
# Builds the APT repository tree from the .deb files produced by `just deb`.
# Refuses to build unsigned unless GNTREES_ALLOW_UNSIGNED=1, because an unsigned
# repository can only be used with trusted=yes, which disables package
# authentication. The private key never lives in this repository.
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# An unsigned repository must never be published by accident.
if [ -z "${GNTREES_SIGN_KEYFILE:-}" ]; then
  [ "${GNTREES_ALLOW_UNSIGNED:-0}" = "1" ] \
    || die "repo tanpa tanda tangan ditolak; set GNTREES_SIGN_KEYFILE, atau GNTREES_ALLOW_UNSIGNED=1 untuk build lokal"
fi

docker_ok
found="$(find "$GNTREES_DEB_DIR" -maxdepth 1 -name '*.deb' -print -quit 2>/dev/null || true)"
[ -n "$found" ] || die "paket .deb belum ada; jalankan 'just deb' dulu"
ensure_build_dirs

sign_args=()
if [ -n "${GNTREES_SIGN_KEYFILE:-}" ]; then
  keyfile="$(realpath "$GNTREES_SIGN_KEYFILE")" || die "keyfile tidak ditemukan"
  [ -f "$keyfile" ] || die "keyfile tidak ditemukan: $keyfile"
  sign_args=(-v "$keyfile:/signing/key:ro" -e GNTREES_SIGN_KEYFILE=/signing/key)
  if [ -n "${GNTREES_SIGN_KEY:-}" ]; then
    sign_args+=(-e "GNTREES_SIGN_KEY=$GNTREES_SIGN_KEY")
  fi
  if [ -n "${GNTREES_SIGN_PASSPHRASE_FILE:-}" ]; then
    passfile="$(realpath "$GNTREES_SIGN_PASSPHRASE_FILE")" \
      || die "passphrase file tidak ditemukan"
    [ -f "$passfile" ] || die "passphrase file tidak ditemukan: $passfile"
    sign_args+=(-v "$passfile:/signing/passphrase:ro" \
      -e GNTREES_SIGN_PASSPHRASE_FILE=/signing/passphrase)
  fi
else
  warn "GNTREES_ALLOW_UNSIGNED=1: repo dibuat TANPA TANDA TANGAN"
fi

log "build image: $GNTREES_BUILDER_IMAGE"
docker build -q -t "$GNTREES_BUILDER_IMAGE" \
  -f "$GNTREES_ROOT/containers/ubuntu.Dockerfile" "$GNTREES_ROOT/containers" >/dev/null

remove_tree "$GNTREES_APT_DIR"
mkdir -p "$GNTREES_APT_DIR"

log "bangun repo APT ($GNTREES_APT_SUITE/$GNTREES_CODENAME)"
docker run --rm \
  -v "$GNTREES_ROOT:/gntrees:ro" \
  -v "$GNTREES_DEB_DIR:/in/deb:ro" \
  -v "$GNTREES_APT_DIR:/out/apt" \
  -e GNTREES_ARCH="$GNTREES_ARCH" \
  -e GNTREES_APT_SUITE="$GNTREES_APT_SUITE" \
  -e GNTREES_CODENAME="$GNTREES_CODENAME" \
  -e GNTREES_UID="$(id -u)" \
  -e GNTREES_GID="$(id -g)" \
  "${sign_args[@]}" \
  "$GNTREES_BUILDER_IMAGE" \
  bash /gntrees/scripts/container-repo.sh

[ -s "$GNTREES_APT_DIR/dists/$GNTREES_APT_SUITE/Release" ] \
  || die "Release tidak terbentuk di $GNTREES_APT_DIR"

log "repo: $GNTREES_APT_DIR"
find "$GNTREES_APT_DIR" -type f | sort
