#!/usr/bin/env bash
set -euo pipefail

# latex
echo -e "Installing latex:"
brew install basictex
brew install tex-live-utility

# other tools
echo -e "\nInstalling other tools:"
brew install aspell bat curl editorconfig eza git-delta jq
brew install inetutils git vim qemu ripgrep wget k9s

