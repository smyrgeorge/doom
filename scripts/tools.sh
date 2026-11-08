#!/usr/bin/env bash
# CLI tools, fonts and LaTeX the config uses. macOS: Homebrew; Linux: apt
# (Debian, Ubuntu) or dnf (Fedora), see scripts/os.sh. DRY_RUN=1 prints the
# commands instead.
set -euo pipefail
# shellcheck source=scripts/os.sh
. "$(dirname "$0")/os.sh"

pkg_update

# latex
echo -e "Installing latex:"
pkg basictex texlive-latex-base texlive-scheme-basic # its installer asks for an admin password (macOS)
pkg "--cask tex-live-utility" - -

# other tools
echo -e "\nInstalling other tools:"
pkg "aspell" "aspell aspell-en" "aspell aspell-en" # spelling (config/editor/spell.el)
pkg "bat curl editorconfig eza jq" "bat curl editorconfig eza jq" "bat curl editorconfig eza jq"
pkg fd fd-find fd-find
pkg git-delta git-delta git-delta # magit's diffs (config/magit.el)
pkg "--cask font-jetbrains-mono" fonts-jetbrains-mono jetbrains-mono-fonts
# Icons (nerd-icons: treemacs, dirvish, modeline, completion). Linux: no package;
# M-x nerd-icons-install-fonts puts them in ~/.local/share/fonts.
pkg "--cask font-symbols-only-nerd-font" - -
[ "$OS" != macos ] && manual "Nerd Fonts' symbols: M-x nerd-icons-install-fonts, in Emacs"
pkg "git vim ripgrep wget" "git vim ripgrep wget" "git vim-enhanced ripgrep wget2-wget"
pkg "inetutils qemu k9s" - - # macOS only: not the config's
# Images: cropping (c), rotating and flipping on Linux, copying SVGs as PNGs
# (config/image.el).
pkg imagemagick imagemagick ImageMagick

# Linux: what macOS has built in.
if [ "$OS" != macos ]; then
  echo -e "\nInstalling Linux's counterparts of macOS's own:"
  # Other apps, the file manager (config/os.el); printing (lp).
  pkg - "xdg-utils cups-client" "xdg-utils cups-client"
  # The clipboard's images: Wayland, X11.
  pkg - "wl-clipboard xclip" "wl-clipboard xclip"
  # Building tree-sitter grammars (config/editor/tree-sitter.el).
  pkg - build-essential "gcc gcc-c++ make"
  # PDFs without xwidgets: DocView (mutool).
  pkg - mupdf-tools mupdf
  # The Markdown preview.
  pkg - pandoc pandoc
fi

# agent-shell (Claude Code in Emacs via ACP)
echo -e "\nInstalling agent-shell bridge:"
if command -v npm >/dev/null 2>&1 || [ -n "${DRY_RUN:-}" ]; then
  npm_global @agentclientprotocol/claude-agent-acp
else
  manual "npm (Node.js), then: npm install -g @agentclientprotocol/claude-agent-acp (scripts/lsp.sh installs Node)"
fi

os_summary
