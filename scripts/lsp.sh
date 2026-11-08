#!/usr/bin/env bash
set -euo pipefail

# prerequisites (npm and uv install most of the servers below)
echo -e "Installing prerequisites:"
brew install node uv

# python (uv)
echo -e "\nInstalling python:"
# basedpyright: Pyright with inlay hints and semantic highlighting (config/lsp/python.el)
uv tool install --upgrade basedpyright
uv tool install --upgrade black
uv tool install --upgrade isort # import sorting (py-isort)

# bash
echo -e "\nInstalling bash:"
npm i -g bash-language-server
brew install shellcheck shfmt # bash-language-server's linter

# docker
echo -e "\nInstalling docker:"
npm i -g dockerfile-language-server-nodejs

# javascript / typescript
echo -e "\nInstalling javascript:"
# TypeScript 7 (native): its tsc is the language server too, for projects
# without TypeScript 7 of their own (config/lsp.el, TYPESCRIPT). ESLint's
# server comes with vscode-langservers-extracted (web, below).
npm i -g typescript@latest

# web (html/css/json)
echo -e "\nInstalling web:"
npm i -g vscode-langservers-extracted js-beautify
# Format-on-save fallback (js/css/html/json/yaml/markdown) when the LSP server
# doesn't format.
npm i -g prettier

# yaml
echo -e "\nInstalling yaml:"
npm i -g yaml-language-server

# markdown
echo -e "\nInstalling markdown:"
brew install marksman
brew install pandoc # live preview (config/markdown.el)

# rust
echo -e "\nInstalling rust:"
# Prefer rustup's component: rustup puts a rust-analyzer proxy in ~/.cargo/bin
# that errors out unless the component is installed.
if command -v rustup >/dev/null; then
    rustup component add rust-analyzer rustfmt
else
    brew install rust-analyzer
fi

# kotlin
echo -e "\nInstalling kotlin:"
# JetBrains' official Kotlin LSP (accept its EULA on first launch).
brew install --cask kotlin-lsp
brew install ktlint

# java
echo -e "\nInstalling java:"
# lsp-java downloads Eclipse's language server (jdtls) itself, the first time
# a Java file opens (M-x lsp-install-server to update it); it needs a JDK.
/usr/libexec/java_home >/dev/null 2>&1 || brew install --cask temurin

# lua
echo -e "\nInstalling lua:"
brew install lua-language-server

# c
echo -e "\nInstalling c:"
brew install glslang clang-format

# latex
echo -e "\nInstalling latex:"
brew install texlab

# godot
echo -e "\nInstalling godot:"
uv tool install --upgrade gdtoolkit
