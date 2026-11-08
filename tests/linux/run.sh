#!/usr/bin/env bash
# Runs this config's tests on Linux, in Docker (docs/tests.md): Debian with
# Emacs 31.1 built from source, the config and Doom's folder mounted
# read-only (Doom's packages as `doom sync' built them; native modules, e.g.
# ghostel's, are the host's, so tests needing them skip).
#
#   tests/linux/run.sh unit [names...]   unit tests (emacs --batch)
#   tests/linux/run.sh e2e [names...]    end-to-end tests: a GUI Emacs under Xvfb
#   tests/linux/run.sh all               both
#   tests/linux/run.sh shell             a shell in the container
#
# XWIDGETS=no: an Emacs without xwidgets (most distributions'): its own
# image. The image is built the first time (Emacs compiles: ~10 minutes).
# DOOM_EMACS (default ~/.config/emacs) is Doom's folder; E2E_TIMEOUT and
# E2E_WINDOW are passed on.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
# shellcheck source=scripts/ui.sh
. "$ROOT/scripts/ui.sh"
DOOM_EMACS=${DOOM_EMACS:-$HOME/.config/emacs}
KIND=${1:-unit}
[ $# -gt 0 ] && shift

image=doom-config-tests
build_args=()
if [ "${XWIDGETS:-yes}" = no ]; then
  image=doom-config-tests:no-xwidgets
  build_args=(--build-arg EMACS_CONFIGURE_EXTRA=)
fi
if ! docker image inspect "$image" >/dev/null 2>&1; then
  ui_step "Building the $image image $(ui_dim "(Emacs from source: ~10 minutes, once)")"
  docker build ${build_args[@]+"${build_args[@]}"} -t "$image" "$HERE"
fi

# Doom's straight folder links into its repos by their absolute path: Doom's
# folder is mounted there too.
args=(--rm --init
      -v "$ROOT:/root/.config/doom:ro"
      -v "$DOOM_EMACS:/root/.config/emacs:ro"
      -v "$DOOM_EMACS:$DOOM_EMACS:ro"
      -e TMPDIR=/tmp -e "E2E_TIMEOUT=${E2E_TIMEOUT:-180}" -e "E2E_WINDOW=${E2E_WINDOW:-}")
[ -t 1 ] && args+=(-t)

case "$KIND" in
  unit)
    exec docker run "${args[@]}" "$image" tests/run.sh unit "$@" ;;
  e2e|all)
    # One X server for the run; a session D-Bus for WebKitGTK.
    exec docker run "${args[@]}" --shm-size=1g -e EMACS_GUI=emacs "$image" \
      dbus-run-session -- xvfb-run -a -s '-screen 0 1920x1200x24' tests/run.sh "$KIND" "$@" ;;
  shell)
    exec docker run "${args[@]}" -i "$image" bash ;;
  *)
    ui_error "usage: $0 unit|e2e|all|shell [names...]"
    exit 2 ;;
esac
