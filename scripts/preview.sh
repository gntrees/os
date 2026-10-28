#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker_ok
[ -x "$GNTRESS_ROOTFS_DIR/usr/bin/cosmic-session" ] \
  || die "rootfs belum siap; jalankan 'just stage' dulu"

args=(
  --rm -it
  -e "DISPLAY=${DISPLAY:-:0}"
  -e COSMIC_BACKEND=x11
  -e XDG_RUNTIME_DIR=/tmp/xdg
  -v /tmp/.X11-unix:/tmp/.X11-unix
  -v "$GNTRESS_ROOT:/gntress:ro"
  -v "$GNTRESS_ROOTFS_DIR:/stage:ro"
)

if [ -d /dev/dri ]; then
  args+=( --device /dev/dri )
fi

if [ -n "${XAUTHORITY:-}" ] && [ -f "$XAUTHORITY" ]; then
  args+=( -v "$XAUTHORITY:/root/.Xauthority:ro" )
elif [ -f "$HOME/.Xauthority" ]; then
  args+=( -v "$HOME/.Xauthority:/root/.Xauthority:ro" )
fi

log "preview COSMIC nested di DISPLAY=${DISPLAY:-:0}"
docker run "${args[@]}" "$GNTRESS_BUILDER_IMAGE" \
  bash /gntress/scripts/container-preview.sh
