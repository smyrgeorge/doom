#!/usr/bin/env bash
# Sourced by the installers (emacs.sh, tools.sh, lsp.sh): which system this is
# and how it installs packages. Run again, they update: a package installed
# already is upgraded to its latest version.
#
#   macOS               Homebrew
#   Debian, Ubuntu      apt (sudo)
#   Fedora              dnf (sudo)
#   another Linux       the packages are listed, to install by hand
#
# DRY_RUN=1 prints what would run instead of running it. OS=macos|apt|dnf
# picks the system (tests/unit/test-lsp-script.el).

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

# run CMD...: run it (or print it, DRY_RUN=1).
run() {
  if [ -n "${DRY_RUN:-}" ]; then
    echo "+ $*"
  else
    "$@"
  fi
}

# pkg BREW APT DNF: install this system's packages (a word list each; "-":
# none there), or upgrade them if they're installed: brew upgrade, else brew
# install; apt-get install (it upgrades); dnf install, then dnf upgrade. A
# failure is noted, not fatal: the other tools still install.
pkg() {
  local names
  case "$OS" in
    macos) names=$1 ;;
    apt) names=$2 ;;
    dnf) names=$3 ;;
    *) names=$2 ;;
  esac
  [ "$names" = - ] && return 0
  # shellcheck disable=SC2086  # a word list: "--cask font-x", "aspell aspell-en"
  case "$OS" in
    macos) run brew upgrade $names 2>/dev/null || run brew install $names || OS_SKIPPED+=("$names") ;;
    apt) run $SUDO apt-get install -y $names || OS_SKIPPED+=("$names") ;;
    dnf) { run $SUDO dnf install -y $names && run $SUDO dnf upgrade -y $names; } || OS_SKIPPED+=("$names") ;;
    *) OS_SKIPPED+=("$names") ;;
  esac
}

# pkg_update: refresh apt's package lists (once per script).
pkg_update() {
  [ "$OS" = apt ] && run $SUDO apt-get update
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
      echo "npm's global folder ($prefix) isn't writable: using ~/.local (npm config set prefix ~/.local)"
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
  run npm install -g "${packages[@]}"
}

# uv_tool TOOL...: uv tool install --upgrade, each (installed already: its
# latest).
uv_tool() {
  local tool
  for tool in "$@"; do
    run uv tool install --upgrade "$tool"
  done
}

# os_summary: what's left to install by hand, if anything.
os_summary() {
  if [ ${#OS_SKIPPED[@]} -gt 0 ]; then
    echo -e "\nNot installed (install by hand):"
    printf '  %s\n' "${OS_SKIPPED[@]}"
  fi
}
