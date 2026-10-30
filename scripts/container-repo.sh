#!/usr/bin/env bash
# Runs inside the build container. Packages at /in/deb (read-only), APT tree at
# /out/apt. Paths can be overridden to exercise the script on the host.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

deb_dir="${GNTREES_DEB_IN:-/in/deb}"
apt="${GNTREES_APT_OUT:-/out/apt}"
arch="${GNTREES_ARCH:-amd64}"
suite="${GNTREES_APT_SUITE:-stable}"
codename="${GNTREES_CODENAME:-genesis}"
index="dists/$suite/main/binary-$arch"

found="$(find "$deb_dir" -maxdepth 1 -name '*.deb' -print -quit 2>/dev/null || true)"
[ -n "$found" ] || die "tidak ada .deb di $deb_dir; jalankan 'just deb' dulu"

mkdir -p "$apt"
# $apt is a mount point inside the container, so clear its contents instead.
find "$apt" -mindepth 1 -delete
mkdir -p "$apt/pool/main" "$apt/$index"

for deb in "$deb_dir"/*.deb; do
  name="$(dpkg-deb --field "$deb" Package)"
  install -Dm0644 "$deb" "$apt/pool/main/$name/$(basename "$deb")"
done

cd "$apt"

# --multiversion keeps old versions in the index so a downgrade stays possible.
dpkg-scanpackages --multiversion pool /dev/null > "$index/Packages"
gzip -9 -n -c "$index/Packages" > "$index/Packages.gz"

grep -q '^Package: gntrees-os-release$' "$index/Packages" \
  || die "index Packages tidak memuat gntrees-os-release"

# Rebuilt on every run, so drop anything a previous signing step left behind.
rm -f "$apt/dists/$suite/InRelease" "$apt/dists/$suite/Release.gpg"

valid_until="$(date -u -d '+7 days' '+%a, %d %b %Y %H:%M:%S UTC')"
apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=Gntrees \
  -o APT::FTPArchive::Release::Label=Gntrees \
  -o "APT::FTPArchive::Release::Suite=$suite" \
  -o "APT::FTPArchive::Release::Codename=$codename" \
  -o "APT::FTPArchive::Release::Architectures=$arch" \
  -o APT::FTPArchive::Release::Components=main \
  -o APT::FTPArchive::Release::Description="Gntrees OS packages" \
  release "dists/$suite" > "$apt/Release.tmp"
mv "$apt/Release.tmp" "dists/$suite/Release"
# apt-ftparchive ignores Release::Valid-Until, so stamp it before signing.
printf 'Valid-Until: %s\n' "$valid_until" >> "dists/$suite/Release"

if [ -n "${GNTREES_SIGN_KEYFILE:-}" ]; then
  export GNUPGHOME=/tmp/gntrees-gnupg
  rm -rf "$GNUPGHOME"
  mkdir -p "$GNUPGHOME"
  chmod 0700 "$GNUPGHOME"
  gpg --batch --quiet --import "$GNTREES_SIGN_KEYFILE"

  key="${GNTREES_SIGN_KEY:-}"
  if [ -z "$key" ]; then
    key="$(gpg --batch --with-colons --list-secret-keys \
      | awk -F: '/^fpr:/ { print $10; exit }')"
  fi
  [ -n "$key" ] || die "tidak ada kunci rahasia untuk menandatangani repo"

  sign_opts=(--batch --yes --local-user "$key")
  if [ -n "${GNTREES_SIGN_PASSPHRASE_FILE:-}" ]; then
    sign_opts+=(--pinentry-mode loopback \
      --passphrase-file "$GNTREES_SIGN_PASSPHRASE_FILE")
  fi

  gpg "${sign_opts[@]}" \
    --clearsign -o "dists/$suite/InRelease" "dists/$suite/Release"
  gpg "${sign_opts[@]}" \
    --detach-sign -o "dists/$suite/Release.gpg" "dists/$suite/Release"
  gpg --armor --export "$key" > "$apt/gntrees-archive-keyring.asc"

  gpg --batch --verify "dists/$suite/InRelease" >/dev/null 2>&1 \
    || die "InRelease tidak bisa diverifikasi"
  log "repo ditandatangani: $key"
else
  warn "repo tanpa tanda tangan; set GNTREES_SIGN_KEYFILE untuk menandatangani"
fi

if [ -n "${GNTREES_UID:-}" ] && [ -n "${GNTREES_GID:-}" ]; then
  chown -R "${GNTREES_UID}:${GNTREES_GID}" "$apt"
fi

log "repo: $(find "$apt" -type f | wc -l) file di $apt"
