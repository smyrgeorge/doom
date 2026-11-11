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
# image. The image (tests/linux/Dockerfile: Emacs by scripts/emacs.sh, the
# tools by scripts/tools.sh) is built, or brought up to date from its cached
# layers, each run: the first time Emacs compiles (~15 minutes).
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
xwidgets=${XWIDGETS:-yes}
[ "$xwidgets" = no ] && image=doom-config-tests:no-xwidgets
# SKIP_BUILD=1: the image as it is (CI built it already).
if [ -z "${SKIP_BUILD:-}" ]; then
  ui_step "The $image image $(ui_dim "(cached layers; Emacs from source the first time: ~15 minutes)")"
  docker build --build-arg "XWIDGETS=$xwidgets" -t "$image" -f "$HERE/Dockerfile" "$ROOT"
fi

# Doom's straight folder links into its repos by their absolute path: Doom's
# folder is mounted there too. The container runs as root; mounted on Linux
# (CI), the config's folder is its owner's, and git refuses a repository
# another user owns ("dubious ownership"): any is safe here (set in git's
# command scope, which the tests' own GIT_CONFIG_GLOBAL doesn't replace).
args=(--rm --init
      -v "$ROOT:/root/.config/doom:ro"
      -v "$DOOM_EMACS:/root/.config/emacs:ro"
      -v "$DOOM_EMACS:$DOOM_EMACS:ro"
      -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*'
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
