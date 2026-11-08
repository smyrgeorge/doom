#!/usr/bin/env bash
# Emacs, installed or updated to its latest release, then Doom synced against
# it: `doom sync --rebuild' when Emacs's version changed (its packages built
# for the new one), else `doom sync'. Run again, it updates.
#
# macOS: the prebuilt emacs-plus Emacs.app (Homebrew cask; arm64, macOS 15+):
# installed, or upgraded.
# Linux (apt: Debian, Ubuntu; dnf: Fedora): GNU's latest release (or
# EMACS_VERSION), built with GTK, tree-sitter and xwidgets (WebKitGTK: PDFs,
# drawings, the Markdown preview) into /usr/local; not built again if that
# version is already there. XWIDGETS=no leaves WebKit out (they fall back:
# DocView, the file, markdown-mode's preview).
#
# DRY_RUN=1 prints the commands instead. EMACS_BIN (the Emacs whose version is
# checked) and DOOM_BIN (Doom's command) are for the tests.
set -euo pipefail
# shellcheck source=scripts/os.sh
. "$(dirname "$0")/os.sh"

DOOM_BIN=${DOOM_BIN:-$HOME/.config/emacs/bin/doom}

# version_of BINARY: its Emacs version ("31.1"), or nothing if it isn't one.
version_of() {
  [ -x "$1" ] || command -v "$1" >/dev/null 2>&1 || return 0
  "$1" --batch -Q --eval '(princ emacs-version)' 2>/dev/null || true
}

if [ "$OS" = macos ]; then
  EMACS_BIN=${EMACS_BIN:-/Applications/Emacs.app/Contents/MacOS/Emacs}
  before=$(version_of "$EMACS_BIN")

  # The terminal-only core formula conflicts with emacs-plus.
  if brew list --formula emacs >/dev/null 2>&1; then
    run brew uninstall emacs
  fi
  # Old emacs-plus formulae symlinked /Applications/Emacs.app into the Cellar;
  # the cask refuses to install over it (even when the link is broken).
  if [ -L /Applications/Emacs.app ]; then
    run rm /Applications/Emacs.app
  fi

  ui_step "Emacs $(ui_dim "(emacs-plus-app${DRY_RUN:+, dry run})")"
  quiet brew tap d12frosted/emacs-plus
  quiet brew trust d12frosted/emacs-plus
  if ! brew list --cask emacs-plus-app >/dev/null 2>&1; then
    run brew install --cask emacs-plus-app
    ui_ok "Emacs $(ui_green installed)"
  elif brew outdated --cask --quiet 2>/dev/null | grep -qx emacs-plus-app; then
    run brew upgrade --cask emacs-plus-app
    ui_ok "Emacs ${before:-?} $(ui_green upgraded)"
  else
    ui_ok "Emacs ${before:-?} $(ui_dim 'up to date')"
  fi
  after=$(version_of "$EMACS_BIN")
else
  EMACS_BIN=${EMACS_BIN:-/usr/local/bin/emacs}
  XWIDGETS=${XWIDGETS:-yes}
  before=$(version_of "$EMACS_BIN")

  # The latest release, from GNU's list of them (EMACS_VERSION: that one).
  if [ -z "${EMACS_VERSION:-}" ]; then
    EMACS_VERSION=$(curl -fsSL https://ftp.gnu.org/gnu/emacs/ |
                      grep -oE 'emacs-[0-9]+(\.[0-9]+)+\.tar\.xz' |
                      sed -E 's/^emacs-(.*)\.tar\.xz$/\1/' |
                      sort -t. -k1,1n -k2,2n -k3,3n | tail -1) || true
    if [ -z "$EMACS_VERSION" ]; then
      ui_error "emacs.sh: couldn't read Emacs's latest release from ftp.gnu.org (EMACS_VERSION=...)"
      exit 1
    fi
  fi

  ui_step "Emacs $(ui_dim "(GNU's latest release: $EMACS_VERSION${DRY_RUN:+, dry run})")"
  if [ "$before" = "$EMACS_VERSION" ]; then
    ui_ok "Emacs $EMACS_VERSION $(ui_dim 'up to date')"
  else
    if [ -n "$before" ]; then
      ui_info "Updating Emacs $before to $EMACS_VERSION, built from source"
    else
      ui_info "Installing Emacs $EMACS_VERSION, built from source"
    fi
    # Build dependencies (what tests/linux's image builds it with).
    case "$OS" in
      apt)
        webkit=libwebkit2gtk-4.1-dev
        [ "$XWIDGETS" = no ] && webkit=
        pkg_update
        # shellcheck disable=SC2086
        run $SUDO apt-get install -y build-essential pkg-config curl ca-certificates xz-utils \
          libgtk-3-dev $webkit libtree-sitter-dev \
          libxpm-dev libpng-dev libjpeg-dev libgif-dev libtiff-dev libwebp-dev \
          librsvg2-dev libgnutls28-dev libxml2-dev libncurses-dev libharfbuzz-dev \
          libcairo2-dev libsqlite3-dev libgmp-dev libacl1-dev libdbus-1-dev \
          liblcms2-dev libsystemd-dev zlib1g-dev ;;
      dnf)
        webkit=webkit2gtk4.1-devel
        [ "$XWIDGETS" = no ] && webkit=
        run $SUDO dnf install -y dnf-plugins-core
        run $SUDO dnf builddep -y emacs
        # shellcheck disable=SC2086
        run $SUDO dnf install -y $webkit libtree-sitter-devel curl xz ;;
      *)
        ui_error "emacs.sh: no package manager it knows (apt, dnf): install Emacs $EMACS_VERSION," \
                 "built with GTK, tree-sitter (and xwidgets), then run: doom sync --rebuild"
        exit 1 ;;
    esac

    options=(--prefix=/usr/local --with-x-toolkit=gtk3 --with-tree-sitter
             --with-xpm --with-png --with-jpeg --with-gif --with-tiff --with-webp
             --with-rsvg --with-gnutls --with-xml2 --with-cairo --with-harfbuzz
             --with-sqlite3 --with-modules --with-dbus --with-native-compilation=no)
    [ "$XWIDGETS" != no ] && options+=(--with-xwidgets)

    build=$(mktemp -d "${TMPDIR:-/tmp}/emacs-build.XXXXXXXXXX")
    trap 'rm -rf "$build"' EXIT
    run curl -fsSL "https://ftpmirror.gnu.org/emacs/emacs-$EMACS_VERSION.tar.xz" -o "$build/emacs.tar.xz"
    run tar -xf "$build/emacs.tar.xz" -C "$build"
    if [ -z "${DRY_RUN:-}" ]; then
      cd "$build/emacs-$EMACS_VERSION"
    fi
    run ./configure "${options[@]}"
    run make -j"$(nproc 2>/dev/null || echo 4)"
    run $SUDO make install
    cd - >/dev/null 2>&1 || true
    ui_ok "Emacs $EMACS_VERSION $(ui_green installed)"
  fi
  after=$(version_of "$EMACS_BIN")
  [ -n "${DRY_RUN:-}" ] && after=$EMACS_VERSION
fi

# Doom's modules live in a git submodule (sources/doom+). `doom install`
# fetches it but `doom sync` doesn't; without it only Doom's core is installed.
echo
ui_step "Doom"
quiet git -C "$(dirname "$(dirname "$DOOM_BIN")")" submodule update --init --recursive
ui_ok "Doom's modules (sources/doom+)"

# Doom against this Emacs: its packages built again if Emacs changed.
if [ "$before" != "$after" ]; then
  ui_info "Emacs ${before:-(none)} -> ${after:-?}: rebuilding Doom's packages for it"
  run "$DOOM_BIN" sync --rebuild
  ui_ok "Doom synced, its packages rebuilt"
else
  run "$DOOM_BIN" sync
  ui_ok "Doom synced"
fi

echo
ui_step "$(ui_green "✔ Emacs ${after:-?} and Doom ready")"

# To re-install (macOS), uninstall first:
# brew uninstall --cask emacs-plus-app
