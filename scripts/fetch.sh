#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require git
ensure_build_dirs

while read -r name repo rev builder; do
  [ -n "$repo" ] && [ -n "$rev" ] \
    || die "components.list: '$name' tidak punya pin lengkap di versions.lock"

  dir="$GNTREES_SRC_DIR/$name"

  if [ ! -d "$dir/.git" ]; then
    log "clone $repo"
    git clone --quiet "https://github.com/$repo.git" "$dir"
  fi

  git -C "$dir" fetch --quiet --tags --force origin
  git -C "$dir" cat-file -e "${rev}^{commit}" 2>/dev/null \
    || die "$name: commit $rev tidak ditemukan di $repo"
  # Only touch the worktree when the pin actually changed: a forced checkout
  # rewrites mtimes and makes cargo rebuild the whole component.
  if [ "$(git -C "$dir" rev-parse --verify HEAD 2>/dev/null || true)" != "$rev" ]; then
    git -C "$dir" checkout --quiet --force "$rev"
  fi

  if [ -f "$dir/.gitmodules" ]; then
    git -C "$dir" submodule update --init --recursive --quiet
  fi

  log "$name @ ${rev:0:12} (${builder})"
done < <(enabled_components)

log "source siap di $GNTREES_SRC_DIR"
