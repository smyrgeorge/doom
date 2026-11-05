#!/usr/bin/env bash
set -euo pipefail

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

# Doom's modules live in a git submodule (sources/doom+). `doom install`
# fetches it but `doom sync` doesn't; without it only Doom's core is installed.
git -C ~/.config/emacs submodule update --init --recursive

# Rebuild Doom against the new Emacs (native-comp).
~/.config/emacs/bin/doom sync --rebuild

# To re-install, uninstall first:
# brew uninstall --cask emacs-plus-app
