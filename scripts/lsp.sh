#!/usr/bin/env bash
# The language servers (and formatters, linters) of the languages init.el
# enables with +lsp, read from its doom! block: a language turned off there
# gets nothing. Run again, it updates them to their latest versions (npm
# @latest, uv --upgrade, brew upgrade, apt / dnf upgrade, rustup update).
#
# macOS: Homebrew; Linux: apt (Debian, Ubuntu) or dnf (Fedora), see
# scripts/os.sh; npm and uv install most servers on both. What a system has no
# package for is listed at the end, to install by hand, as are +lsp modules
# this script knows no server for.
#
# DRY_RUN=1 prints the commands instead. DOOM_INIT (default: this config's
# init.el) and EMACS (default: emacs) are what it reads the modules with.
set -euo pipefail
# shellcheck source=scripts/os.sh
. "$(dirname "$0")/os.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOOM_INIT=${DOOM_INIT:-$ROOT/init.el}
EMACS=${EMACS:-emacs}

# ====== THE MODULES ======

# "CATEGORY MODULE FLAGS..." per enabled module of init.el's doom! block (its
# :if forms left out); Emacs reads it, as Doom does.
modules() {
  "$EMACS" --batch -Q --eval '
(let ((form nil) (category nil))
  (with-temp-buffer
    (insert-file-contents (car command-line-args-left))
    (goto-char (point-min))
    (while (and (not form) (ignore-errors (setq form (read (current-buffer)))))
      (unless (eq (car-safe form) (quote doom!)) (setq form nil))))
  (dolist (item (cdr form))
    (cond ((keywordp item) (setq category item))
          ((symbolp item) (princ (format "%s %s\n" category item)))
          ((and (consp item) (symbolp (car item)) (not (keywordp (car item))))
           (princ (format "%s %s %s\n" category (car item)
                          (mapconcat (function symbol-name) (cdr item) " ")))))))' \
    "$DOOM_INIT"
}

if ! command -v "$EMACS" >/dev/null 2>&1; then
  echo "lsp.sh: no Emacs to read init.el with (scripts/emacs.sh installs it; EMACS=...)" >&2
  exit 1
fi
MODULES=$(modules)

# lsp MODULE: non-nil if init.el enables MODULE with +lsp.
lsp() {
  grep -qE "^:[a-z]+ $1 (.* )?\+lsp( |$)" <<<"$MODULES"
}

# The languages: +lsp modules but those that aren't one (treemacs, format...).
LANGUAGES=$({ grep -E " \+lsp( |$)" <<<"$MODULES" || true; } | awk '$2 !~ /^(lsp|treemacs|format|debugger)$/ {print $2}' | tr '\n' ' ')
echo "Languages with +lsp in init.el: $LANGUAGES"

# What npm and uv install, gathered: each once, in one go.
NPM=()
UV=()
npm_add() { NPM+=("$@"); }
uv_add() { UV+=("$@"); }

pkg_update

# ====== PER LANGUAGE ======

# python: basedpyright, Pyright with inlay hints and semantic highlighting
# (config/lsp/python.el); black, isort format it.
if lsp python; then
  uv_add basedpyright black isort
fi

# sh: bash-language-server, with shellcheck (linter) and shfmt (formatter).
if lsp sh; then
  npm_add bash-language-server
  pkg "shellcheck shfmt" "shellcheck shfmt" "ShellCheck shfmt"
fi

# docker (:tools): the Dockerfile server.
if lsp docker; then
  npm_add dockerfile-language-server-nodejs
fi

# javascript: TypeScript 7 (native): its tsc is the language server too, for
# projects without TypeScript 7 of their own (config/lsp/typescript.el);
# ESLint's server comes with vscode-langservers-extracted; prettier formats
# (config/lsp/typescript.el, a project's own first).
if lsp javascript; then
  npm_add typescript vscode-langservers-extracted prettier
fi

# web (html, css) and json: vscode-langservers-extracted; js-beautify and
# prettier format what the servers don't.
if lsp web; then
  npm_add vscode-langservers-extracted js-beautify prettier
fi
if lsp json; then
  npm_add vscode-langservers-extracted
fi

# yaml
if lsp yaml; then
  npm_add yaml-language-server
fi

# markdown: marksman; pandoc renders the live preview (config/markdown.el).
if lsp markdown; then
  pkg marksman - -
  [ "$OS" != macos ] && manual "marksman: github.com/artempyanykh/marksman/releases (its Linux binary, as marksman on PATH)"
  pkg pandoc pandoc pandoc
fi

# rust: rust-analyzer, rustfmt, clippy (on save, config/lsp/rust.el).
# Prefer rustup's components: rustup puts a rust-analyzer proxy in
# ~/.cargo/bin that errors out unless the component is installed; rustup
# update brings them (and the toolchain) to the latest.
if lsp rust; then
  if command -v rustup >/dev/null 2>&1; then
    run rustup component add rust-analyzer rustfmt clippy
    run rustup update
  else
    pkg rust-analyzer rust-analyzer rust-analyzer # Ubuntu has none: rustup.rs
  fi
fi

# kotlin: JetBrains' kotlin-lsp (accept its EULA on first launch), ktlint.
if lsp kotlin; then
  pkg "--cask kotlin-lsp" - -
  pkg ktlint - -
  if [ "$OS" != macos ]; then
    manual "kotlin-lsp: github.com/Kotlin/kotlin-lsp/releases (unzip; kotlin-lsp.sh on PATH)"
    manual "ktlint: github.com/pinterest/ktlint/releases (its ktlint file on PATH)"
  fi
fi

# java: lsp-java downloads Eclipse's server (jdtls) itself, the first time a
# Java file opens (M-x lsp-install-server to update it); it needs a JDK.
if lsp java; then
  if [ "$OS" = macos ]; then
    if /usr/libexec/java_home >/dev/null 2>&1; then
      run brew upgrade --cask temurin 2>/dev/null || true # if it's brew's
    else
      pkg "--cask temurin" - -
    fi
  else
    pkg - default-jdk java-21-openjdk-devel
  fi
fi

# lua
if lsp lua; then
  pkg lua-language-server - -
  [ "$OS" != macos ] && manual "lua-language-server: github.com/LuaLS/lua-language-server/releases"
fi

# cc: clangd (macOS's comes with Xcode's command line tools), clang-format;
# glslang for shaders.
if lsp cc; then
  pkg "glslang clang-format" "clangd glslang-tools clang-format" "glslang clang-tools-extra"
fi

# latex: texlab.
if lsp latex; then
  pkg texlab - -
  if [ "$OS" != macos ]; then
    if command -v cargo >/dev/null 2>&1; then
      run cargo install --locked texlab
    else
      manual "texlab: github.com/latex-lsp/texlab/releases, or cargo install --locked texlab"
    fi
  fi
fi

# gdscript: Godot's editor is the server (while open); gdtoolkit formats.
if lsp gdscript; then
  uv_add gdtoolkit
fi

# +lsp languages without a server here.
KNOWN="python sh docker javascript web json yaml markdown rust kotlin java lua cc latex gdscript"
while read -r category module _; do
  [ "$category" = ":lang" ] || continue
  lsp "$module" || continue
  case " $KNOWN " in
    *" $module "*) ;;
    *) manual "$module (+lsp): this script knows no server for it (see Doom's :lang $module docs)" ;;
  esac
done <<<"$MODULES"

# ====== NPM AND UV ======

if [ ${#NPM[@]} -gt 0 ] || [ ${#UV[@]} -gt 0 ]; then
  echo -e "\nInstalling or updating Node.js and uv:"
  pkg "node uv" "nodejs npm pipx" "nodejs nodejs-npm uv"
  if [ "$OS" = apt ] && [ ${#UV[@]} -gt 0 ]; then
    # Debian and Ubuntu have no uv package: pipx's, kept at its latest.
    run pipx upgrade uv 2>/dev/null || run pipx install uv
    export PATH="$HOME/.local/bin:$PATH"
  fi
fi

if [ ${#NPM[@]} -gt 0 ]; then
  echo -e "\nInstalling or updating npm's servers:"
  # Each once (web and json share one).
  # shellcheck disable=SC2046
  npm_global $(printf '%s\n' "${NPM[@]}" | awk '!seen[$0]++')
fi

if [ ${#UV[@]} -gt 0 ]; then
  echo -e "\nInstalling or updating uv's tools:"
  # shellcheck disable=SC2046
  uv_tool $(printf '%s\n' "${UV[@]}" | awk '!seen[$0]++')
fi

os_summary
