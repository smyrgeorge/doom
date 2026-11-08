#!/usr/bin/env bash
# Sourced by the installers (emacs.sh, tools.sh): which system this is and
# how it installs packages; their output's look (scripts/ui.sh). Run again,
# they update: a package installed already is upgraded to its latest version.
#
#   macOS               Homebrew
#   Debian, Ubuntu      apt (sudo)
#   Fedora              dnf (sudo)
#   another Linux       the packages are listed, to install by hand
#
# DRY_RUN=1 shows what would run instead of running it. OS=macos|apt|dnf
# picks the system (tests/unit/test-tools-script.el).

# shellcheck source=scripts/ui.sh
. "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

case "${OS:-$(uname -s)}" in
  macos|apt|dnf|linux) ;;
  Darwin) OS=macos ;;
  Linux)
    if command -v apt-get >/dev/null 2>&1; then OS=apt
    elif command -v dnf >/dev/null 2>&1; then OS=dnf
    else OS=linux
    fi ;;
  *) OS=unknown ;;
esac

# Root (a container) needs no sudo.
SUDO=sudo
[ "$(id -u)" -eq 0 ] && SUDO=

# What couldn't be installed, said at the end (`os_summary').
OS_SKIPPED=()

# run CMD...: show it ($ CMD), then run it (DRY_RUN=1: only show it).
run() {
  ui_cmd "$*"
  [ -n "${DRY_RUN:-}" ] || "$@"
}

# quiet CMD...: show it, run it with its output kept back: shown (its end)
# only if it fails.
quiet() {
  local output
  ui_cmd "$*"
  [ -z "${DRY_RUN:-}" ] || return 0
  if output=$("$@" 2>&1); then
    return 0
  fi
  printf '%s\n' "$output" | tail -8 | sed 's/^/      /'
  return 1
}

# brew_latest [--cask] NAME...: each installed if it isn't, upgraded if it's
# outdated, else said to be up to date (Homebrew asked once what's installed
# and what's outdated). A failure is noted (`os_summary'), not fatal.
brew_latest() {
  local cask=() name installed outdated
  if [ "${1:-}" = --cask ]; then
    cask=(--cask)
    shift
  fi
  installed=$(brew list ${cask[@]+"${cask[@]}"} -1 2>/dev/null || true)
  outdated=$(brew outdated ${cask[@]+"${cask[@]}"} --quiet 2>/dev/null || true)
  for name in "$@"; do
    if ! grep -qx "$name" <<<"$installed"; then
      if run brew install ${cask[@]+"${cask[@]}"} "$name"; then
        ui_ok "$(printf '%-30s' "$name") $(ui_green installed)"
      else
        ui_fail "$name: couldn't install it"
        OS_SKIPPED+=("$name")
      fi
    elif grep -qx "$name" <<<"$outdated"; then
      if run brew upgrade ${cask[@]+"${cask[@]}"} "$name"; then
        ui_ok "$(printf '%-30s' "$name") $(ui_green upgraded)"
      else
        ui_fail "$name: couldn't upgrade it"
        OS_SKIPPED+=("$name")
      fi
    else
      ui_ok "$(printf '%-30s' "$name") $(ui_dim 'up to date')"
    fi
  done
}

# pkg_update: refresh apt's package lists (once per script).
pkg_update() {
  [ "$OS" = apt ] && run $SUDO apt-get update -q
  return 0
}

# manual WHAT: something to install by hand, said at the end.
manual() {
  OS_SKIPPED+=("$*")
}

# npm_global PACKAGE...: npm install -g, each at its latest version (installed
# already: upgraded). On Linux, where npm's global folder is root's
# (/usr/local), into ~/.local instead (its bin on PATH).
npm_global() {
  if [ "$OS" != macos ] && [ -z "${DRY_RUN:-}" ]; then
    local prefix
    prefix=$(npm prefix -g)
    if [ "$prefix" != "$HOME/.local" ] && [ ! -w "$prefix" ]; then
      ui_info "npm's global folder ($prefix) isn't writable: using ~/.local"
      npm config set prefix "$HOME/.local"
    fi
    mkdir -p "$HOME/.local"
  fi
  local packages=() package
  for package in "$@"; do
    case "$package" in
      @*@*|[!@]*@*) packages+=("$package") ;; # a version given
      *) packages+=("$package@latest") ;;
    esac
  done
  run npm install -g --no-fund --no-audit "${packages[@]}"
}

# uv_tool TOOL...: uv tool install --upgrade, each (installed already: its
# latest).
uv_tool() {
  local tool
  for tool in "$@"; do
    quiet uv tool install --upgrade "$tool"
  done
}

# os_summary: what's left to install by hand, if anything.
os_summary() {
  if [ ${#OS_SKIPPED[@]} -gt 0 ]; then
    echo
    ui_step "To install by hand"
    local item
    for item in "${OS_SKIPPED[@]}"; do
      ui_warn "$item"
    done
  fi
}
