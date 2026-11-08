#!/usr/bin/env bash
# The language servers (and formatters, linters) of init.el's languages.
# macOS: Homebrew; Linux: apt (Debian, Ubuntu) or dnf (Fedora), see
# scripts/os.sh; npm and uv install most of them on both. What a system has no
# package for is listed at the end, to install by hand. DRY_RUN=1 prints the
# commands instead.
set -euo pipefail
# shellcheck source=scripts/os.sh
. "$(dirname "$0")/os.sh"

pkg_update

# prerequisites (npm and uv install most of the servers below)
echo -e "Installing prerequisites:"
pkg "node uv" "nodejs npm pipx" "nodejs nodejs-npm uv"
if [ "$OS" = apt ] && ! command -v uv >/dev/null 2>&1; then
  run pipx install uv # Debian and Ubuntu have no uv package
  export PATH="$HOME/.local/bin:$PATH"
fi

# python (uv)
echo -e "\nInstalling python:"
# basedpyright: Pyright with inlay hints and semantic highlighting (config/lsp/python.el)
run uv tool install --upgrade basedpyright
run uv tool install --upgrade black
run uv tool install --upgrade isort # import sorting (py-isort)

# bash
echo -e "\nInstalling bash:"
npm_global bash-language-server
pkg "shellcheck shfmt" "shellcheck shfmt" "ShellCheck shfmt" # bash-language-server's linter

# docker
echo -e "\nInstalling docker:"
npm_global dockerfile-language-server-nodejs

# javascript / typescript
echo -e "\nInstalling javascript:"
# TypeScript 7 (native): its tsc is the language server too, for projects
# without TypeScript 7 of their own (config/lsp/typescript.el). ESLint's
# server comes with vscode-langservers-extracted (web, below).
npm_global typescript@latest

# web (html/css/json)
echo -e "\nInstalling web:"
npm_global vscode-langservers-extracted js-beautify
# Format-on-save fallback (js/css/html/json/yaml/markdown) when the LSP server
# doesn't format.
npm_global prettier

# yaml
echo -e "\nInstalling yaml:"
npm_global yaml-language-server

# markdown
echo -e "\nInstalling markdown:"
pkg marksman - -
[ "$OS" != macos ] && manual "marksman: github.com/artempyanykh/marksman/releases (its Linux binary, as marksman on PATH)"
pkg pandoc pandoc pandoc # live preview (config/markdown.el)

# rust
echo -e "\nInstalling rust:"
# Prefer rustup's component: rustup puts a rust-analyzer proxy in ~/.cargo/bin
# that errors out unless the component is installed.
if command -v rustup >/dev/null 2>&1; then
  run rustup component add rust-analyzer rustfmt clippy
else
  pkg rust-analyzer rust-analyzer rust-analyzer # Ubuntu has none: rustup.rs
fi

# kotlin
echo -e "\nInstalling kotlin:"
# JetBrains' official Kotlin LSP (accept its EULA on first launch).
pkg "--cask kotlin-lsp" - -
pkg ktlint - -
if [ "$OS" != macos ]; then
  manual "kotlin-lsp: github.com/Kotlin/kotlin-lsp/releases (unzip; kotlin-lsp.sh on PATH)"
  manual "ktlint: github.com/pinterest/ktlint/releases (its ktlint file on PATH)"
fi

# java
echo -e "\nInstalling java:"
# lsp-java downloads Eclipse's language server (jdtls) itself, the first time
# a Java file opens (M-x lsp-install-server to update it); it needs a JDK.
if [ "$OS" = macos ]; then
  /usr/libexec/java_home >/dev/null 2>&1 || pkg "--cask temurin" - -
elif ! command -v javac >/dev/null 2>&1; then
  pkg - default-jdk java-21-openjdk-devel
fi

# lua
echo -e "\nInstalling lua:"
pkg lua-language-server - -
[ "$OS" != macos ] && manual "lua-language-server: github.com/LuaLS/lua-language-server/releases"

# c
echo -e "\nInstalling c:"
pkg "glslang clang-format" "glslang-tools clang-format" "glslang clang-tools-extra"

# latex
echo -e "\nInstalling latex:"
pkg texlab - -
if [ "$OS" != macos ]; then
  if command -v cargo >/dev/null 2>&1; then
    run cargo install --locked texlab
  else
    manual "texlab: github.com/latex-lsp/texlab/releases, or cargo install --locked texlab"
  fi
fi

# godot
echo -e "\nInstalling godot:"
run uv tool install --upgrade gdtoolkit

os_summary
