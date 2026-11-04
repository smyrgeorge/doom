#!/usr/bin/env bash
set -euo pipefail

# Remove the terminal-only core formula (conflicts with emacs-plus).
brew uninstall emacs 2>/dev/null || true

# Install prebuilt Emacs.app from the emacs-plus tap (arm64, macOS 15+).
brew tap d12frosted/emacs-plus
brew trust d12frosted/emacs-plus
brew install --cask emacs-plus-app

# Rebuild Doom against the new Emacs (native-comp).
~/.config/emacs/bin/doom sync --rebuild

# To re-install, uninstall first:
# brew uninstall --cask emacs-plus-app
