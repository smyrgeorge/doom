#!/usr/bin/env bash
# Emacs 31, then Doom built against it (`doom sync --rebuild').
#
# macOS: the prebuilt emacs-plus Emacs.app (Homebrew; arm64, macOS 15+).
# Linux (apt: Debian, Ubuntu; dnf: Fedora): built from GNU's release, with
# GTK, tree-sitter and xwidgets (WebKitGTK: PDFs, drawings, the Markdown
# preview), installed in /usr/local. XWIDGETS=no leaves WebKit out (they fall
# back: DocView, the file, markdown-mode's preview); EMACS_VERSION picks the
# release (default 31.1). DRY_RUN=1 prints the commands instead.
set -euo pipefail
# shellcheck source=scripts/os.sh
. "$(dirname "$0")/os.sh"

if [ "$OS" = macos ]; then
  # Remove the terminal-only core formula (conflicts with emacs-plus).
  brew uninstall emacs 2>/dev/null || true

  # Old emacs-plus formulae symlinked /Applications/Emacs.app into the Cellar;
  # the cask refuses to install over it (even when the link is broken).
  if [ -L /Applications/Emacs.app ]; then
    rm /Applications/Emacs.app
  fi

  # Install prebuilt Emacs.app from the emacs-plus tap (arm64, macOS 15+).
  brew tap d12frosted/emacs-plus
  brew trust d12frosted/emacs-plus
  brew install --cask emacs-plus-app
else
  EMACS_VERSION=${EMACS_VERSION:-31.1}
  XWIDGETS=${XWIDGETS:-yes}

  # Build dependencies (what scripts' test image, a Debian, builds it with).
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
      echo "emacs.sh: no package manager it knows (apt, dnf): install Emacs $EMACS_VERSION," \
           "built with GTK, tree-sitter (and xwidgets), then run: doom sync --rebuild" >&2
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
  run make -j"$(nproc)"
  run $SUDO make install
  cd - >/dev/null 2>&1 || true
fi

# Doom's modules live in a git submodule (sources/doom+). `doom install`
# fetches it but `doom sync` doesn't; without it only Doom's core is installed.
run git -C ~/.config/emacs submodule update --init --recursive

# Rebuild Doom against the new Emacs (native-comp).
run ~/.config/emacs/bin/doom sync --rebuild

# To re-install (macOS), uninstall first:
# brew uninstall --cask emacs-plus-app
