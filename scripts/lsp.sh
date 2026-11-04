#!/usr/bin/env bash
set -euo pipefail

# python (uv)
echo -e "Installing python:"
npm i -g pyright
uv tool install black

# bash
echo -e "\nInstalling bash:"
npm i -g bash-language-server
brew install shfmt

# docker
echo -e "\nInstalling docker:"
npm i -g dockerfile-language-server-nodejs

# web (html/css)
echo -e "\nInstalling web:"
npm i -g vscode-langservers-extracted js-beautify

# rust
echo -e "\nInstalling rust:"
brew install rust-analyzer

# kotlin
echo -e "\nInstalling kotlin:"
# JetBrains' official Kotlin LSP (accept its EULA on first launch).
brew install --cask kotlin-lsp
brew install ktlint

# c
echo -e "\nInstalling c:"
brew install glslang clang-format

# latex
echo -e "\nInstalling latex:"
brew install texlab

# godot
echo -e "\nInstalling godot:"
uv tool install gdtoolkit
