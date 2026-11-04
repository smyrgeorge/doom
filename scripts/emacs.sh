#!/usr/bin/env bash
set -euo pipefail

# Remove the terminal-only core formula (conflicts with emacs-plus).
brew uninstall emacs 2>/dev/null || true

# Install emacs from emacs-plus formula.
brew tap d12frosted/emacs-plus
brew install emacs-plus

# Rebuild Doom against the new Emacs (native-comp).
~/.config/emacs/bin/doom sync --rebuild

# To re-install, uninstall first:
# brew uninstall emacs-plus
