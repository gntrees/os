#!/usr/bin/env bash
# Shared helpers (kind: script, domain: shared).
set -euo pipefail

GNTREES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/build.conf
. "$GNTREES_ROOT/config/build.conf"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null 2>&1 || die "perintah '$cmd' tidak ditemukan"
  done
}

# Output: "name repo rev builder" for enabled components, in components.list order.
# versions.lock is read first so repo/rev/builder are populated when list is read.
enabled_components() {
  awk '
    FNR == 1 { file++ }
    file == 1 {
      if ($0 ~ /^[[:space:]]*#/ || NF < 4) next
      repo[$1] = $2; rev[$1] = $3; builder[$1] = $4; next
    }
    file == 2 {
      if ($0 ~ /^[[:space:]]*#/ || NF < 2) next
      if ($2 == "yes") print $1, repo[$1], rev[$1], builder[$1]
    }
  ' "$GNTREES_ROOT/config/versions.lock" "$GNTREES_ROOT/config/components.list"
}

# Cached path of an artifact pinned in config/vendor.lock. Output: absolute path.
vendor_file() {
  local name="$1" url
  url=$(awk -v name="$name" '$1 == name { print $3 }' "$GNTREES_ROOT/config/vendor.lock")
  [ -n "$url" ] || die "vendor.lock: entri '$name' tidak ditemukan"
  printf '%s/vendor/%s\n' "$GNTREES_CACHE_DIR" "$(basename "$url")"
}

# Default ISO path, shared by usb.sh and vm.sh so neither needs a path typed.
default_iso() {
  printf '%s/%s-%s-%s.iso\n' \
    "$GNTREES_OUT_DIR" "$GNTREES_NAME" "$GNTREES_VERSION" "$GNTREES_ARCH"
}

ensure_build_dirs() {
  mkdir -p "$GNTREES_SRC_DIR" "$GNTREES_CARGO_DIR" "$GNTREES_TARGET_DIR" \
           "$GNTREES_ROOTFS_DIR" "$GNTREES_LIVE_DIR" "$GNTREES_OUT_DIR"
}

# Remove a build tree. Containers run as root, so a tree left behind by an
# interrupted run is not deletable by the owner; fall back to a container that
# can remove it and keep the host scripts sudo-free.
remove_tree() {
  local dir="$1" img
  [ -e "$dir" ] || return 0
  rm -rf "$dir" 2>/dev/null && return 0

  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
    || die "tidak bisa menghapus $dir (milik root); jalankan: sudo rm -rf '$dir'"

  img="$GNTREES_ISO_IMAGE"
  docker image inspect "$img" >/dev/null 2>&1 || img="$GNTREES_BUILDER_IMAGE"
  docker image inspect "$img" >/dev/null 2>&1 || img="alpine:3"
  warn "menghapus $dir lewat container ($img)"
  docker run --rm -v "$dir:/target" "$img" \
    sh -c 'rm -rf /target/* /target/.[!.]* /target/..?*' \
    || die "gagal menghapus $dir"
  rmdir "$dir" 2>/dev/null || true
}

docker_ok() {
  require docker
  docker info >/dev/null 2>&1 || die "docker tidak bisa diakses (cek daemon dan grup 'docker')"
}

fs_type() {
  stat -f -c %T "$1" 2>/dev/null || echo unknown
}

# Content fingerprint of everything that ends up in the ISO. `just iso` compares
# it with the stamp written after the last successful build and skips the build
# when nothing changed. GNTREES_FORCE_ISO=1 bypasses the check.
iso_fingerprint() {
  local keyring="${GNTREES_KEYRING_FILE:-$GNTREES_BUILD_DIR/keys/gntrees-archive-keyring.asc}"
  {
    printf 'name=%s version=%s arch=%s\n' \
      "$GNTREES_NAME" "$GNTREES_VERSION" "$GNTREES_ARCH"
    printf 'apt=%s suite=%s\n' "$GNTREES_APT_URL" "$GNTREES_APT_SUITE"
    find "$GNTREES_ROOTFS_DIR" \( -type f -o -type l \) \
      -printf '%P %s %T@ %l\n' 2>/dev/null | sort || true
    find "$GNTREES_ROOT/profile" "$GNTREES_ROOT/config" "$GNTREES_ROOT/scripts" \
         "$GNTREES_ROOT/containers" "$GNTREES_ROOT/apps/launcher/data" \
         "$GNTREES_ROOT/apps/launcher/icons" \
         \( -type f -o -type l \) -printf '%P %s %T@ %l\n' 2>/dev/null | sort || true
    if [ -f "$GNTREES_APT_DIR/dists/$GNTREES_APT_SUITE/Release" ]; then
      sha256sum "$GNTREES_APT_DIR/dists/$GNTREES_APT_SUITE/Release"
    fi
    if [ -f "$keyring" ]; then
      sha256sum "$keyring"
    fi
  } | sha256sum | cut -d' ' -f1
}
