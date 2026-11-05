#!/usr/bin/env bash
set -euo pipefail

# latex
echo -e "Installing latex:"
brew install basictex
brew install tex-live-utility

# other tools
echo -e "\nInstalling other tools:"
brew install aspell bat curl editorconfig eza fd git-delta jq
brew install --cask font-jetbrains-mono
# Icons (nerd-icons: treemacs, dirvish, modeline, completion).
brew install --cask font-symbols-only-nerd-font
brew install inetutils git vim qemu ripgrep wget k9s

# pdf-tools builds its epdfinfo server on first use.
echo -e "\nInstalling pdf-tools build deps:"
brew install poppler autoconf automake pkgconf


# agent-shell (Claude Code in Emacs via ACP)
echo -e "\nInstalling agent-shell bridge:"
npm install -g @agentclientprotocol/claude-agent-acp
