#!/usr/bin/env bash
# Everything this config and its init.el need outside Emacs: Doom's own tools,
# each enabled module's (language servers, formatters, linters), this
# config's (fonts, git-delta, ImageMagick...). Installed, or updated to their
# latest version when they are already (run it again to update).
#
#   scripts/tools.sh           install / update, then check
#   scripts/tools.sh --check   only check: what's there, what's missing
#
# What it installs is TOOLS below, one row per tool, read against init.el's
# doom! block (Emacs reads it, as Doom does): a row applies when its module is
# enabled (with its flag, if it names one). Every module init.el enables must
# be in TOOLS or NOTHING, and every +lsp module have its "+lsp" row: else the
# script fails, naming them, before installing anything (a language added to
# init.el needs its tools added here).
#
# macOS: Homebrew; Linux: apt (Debian, Ubuntu) or dnf (Fedora), see
# scripts/os.sh. DRY_RUN=1 prints the commands instead. DOOM_INIT (default:
# this config's init.el) and EMACS (default: emacs) are what it reads the
# modules with.
set -euo pipefail
# shellcheck source=scripts/os.sh
. "$(dirname "$0")/os.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
DOOM_INIT=${DOOM_INIT:-$ROOT/init.el}
EMACS=${EMACS:-emacs}
CHECK_ONLY=
case "${1:-}" in
  --check) CHECK_ONLY=1 ;;
  "") ;;
  *) echo "usage: $0 [--check]" >&2; exit 2 ;;
esac

# ====== THE TOOLS ======

# One row per tool: WHEN | PROGRAM | MACOS | APT | DNF | WHAT FOR
#
# WHEN: doom (Doom itself), config (this config), or a module of init.el,
#   ":CATEGORY MODULE" (when it's enabled) or ":CATEGORY MODULE +FLAG" (when
#   it's enabled with FLAG).
# PROGRAM: what shows it's there, for the check: a command (a/b: either), or
#   font:NAME.
# MACOS, APT, DNF: how this system gets it, space-separated:
#   brew:NAME cask:NAME apt:NAME dnf:NAME   the system's packages
#   npm:NAME uv:NAME pipx:NAME              npm -g, uv tool, pipx
#   rustup:COMPONENT                        rustup's components
#   builtin                                 the system has it (Xcode's tools)
#   manual:WHERE                            no package: install it by hand
#   -                                       not needed on this system
TOOLS=(
  # Doom itself (`doom doctor')
  "doom              | git              | brew:git              | apt:git               | dnf:git                | Doom's packages, magit"
  "doom              | rg               | brew:ripgrep          | apt:ripgrep           | dnf:ripgrep            | file and project search, magit-todos"
  "doom              | fd/fdfind        | brew:fd               | apt:fd-find           | dnf:fd-find            | project files"
  "doom              | fc-list          | brew:fontconfig       | apt:fontconfig        | dnf:fontconfig         | Doom's font checks"

  # This config
  "config            | font:JetBrains Mono | cask:font-jetbrains-mono | apt:fonts-jetbrains-mono | dnf:jetbrains-mono-fonts | the font (config.el)"
  "config            | font:Symbols Nerd Font | cask:font-symbols-only-nerd-font | manual:M-x_nerd-icons-install-fonts | manual:M-x_nerd-icons-install-fonts | icons (nerd-icons)"
  "config            | delta            | brew:git-delta        | apt:git-delta         | dnf:git-delta          | magit's diffs (config/magit.el)"
  "config            | magick/convert   | brew:imagemagick      | apt:imagemagick       | dnf:ImageMagick        | images: crop; rotate, flip on Linux (config/image.el)"
  "config            | npm              | brew:node             | apt:nodejs apt:npm    | dnf:nodejs dnf:nodejs-npm | Claude Code's bridge, npm's servers"
  "config            | claude-agent-acp | npm:@agentclientprotocol/claude-agent-acp | npm:@agentclientprotocol/claude-agent-acp | npm:@agentclientprotocol/claude-agent-acp | Claude Code in Emacs (config/agent-shell.el)"
  "config            | python3          | builtin               | apt:python3           | dnf:python3            | treemacs's git status (config/treemacs.el)"
  "config            | xdg-open         | -                     | apt:xdg-utils         | dnf:xdg-utils          | other apps, the file manager (config/os.el)"
  "config            | lp               | -                     | apt:cups-client       | dnf:cups-client        | printing PDFs (config/os.el)"
  "config            | wl-copy          | -                     | apt:wl-clipboard      | dnf:wl-clipboard       | copying images, Wayland (config/os.el)"
  "config            | xclip            | -                     | apt:xclip             | dnf:xclip              | copying images, X11 (config/os.el)"
  "config            | mutool           | -                     | apt:mupdf-tools       | dnf:mupdf              | PDFs without xwidgets: DocView"

  # :emacs, :checkers, :tools
  ":emacs dired      | gls              | brew:coreutils        | -                     | -                      | GNU ls for dired (macOS's lacks its options)"
  ":checkers spell   | aspell           | brew:aspell           | apt:aspell apt:aspell-en | dnf:aspell dnf:aspell-en | spelling (spell-fu reads aspell's words)"
  ":tools docker     | docker           | manual:docker.com     | manual:docker.com     | manual:docker.com      | docker.el"
  ":tools docker +lsp | docker-langserver | npm:dockerfile-language-server-nodejs | npm:dockerfile-language-server-nodejs | npm:dockerfile-language-server-nodejs | Dockerfile's server (it formats too)"
  ":tools lsp        | npm              | brew:node             | apt:nodejs apt:npm    | dnf:nodejs dnf:nodejs-npm | lsp-mode installs some servers with npm"
  ":tools make       | make             | builtin               | apt:make              | dnf:make               | make tasks"
  ":tools tree-sitter | cc              | builtin               | apt:build-essential   | dnf:gcc dnf:gcc-c++    | building grammars (config/editor/tree-sitter.el)"

  # :lang
  ":lang cc          | clang-format     | brew:clang-format     | apt:clang-format      | dnf:clang-tools-extra  | formatting C, C++"
  ":lang cc +lsp     | clangd           | builtin               | apt:clangd            | dnf:clang-tools-extra  | C/C++'s server"
  ":lang data        | xmllint          | builtin               | apt:libxml2-utils     | dnf:libxml2            | formatting XML"
  ":lang gdscript    | gdformat         | uv:gdtoolkit          | uv:gdtoolkit          | uv:gdtoolkit           | formatting GDScript"
  ":lang java        | javac            | brew:openjdk          | apt:default-jdk       | dnf:java-21-openjdk-devel | the JDK, OpenJDK (lsp-java's jdtls runs on it)"
  ":lang java        | clang-format     | brew:clang-format     | apt:clang-format      | dnf:clang-tools-extra  | formatting Java"
  ":lang javascript +lsp | tsc          | npm:typescript        | npm:typescript        | npm:typescript         | TypeScript 7: its tsc is the server (config/lsp/typescript.el)"
  ":lang javascript +lsp | vscode-eslint-language-server | npm:vscode-langservers-extracted | npm:vscode-langservers-extracted | npm:vscode-langservers-extracted | ESLint's server"
  ":lang javascript  | prettier         | npm:prettier          | npm:prettier          | npm:prettier           | formatting (a project's own first)"
  ":lang json +lsp   | vscode-json-language-server | npm:vscode-langservers-extracted | npm:vscode-langservers-extracted | npm:vscode-langservers-extracted | JSON's server"
  ":lang kotlin      | ktlint           | brew:ktlint           | manual:github.com/pinterest/ktlint/releases | manual:github.com/pinterest/ktlint/releases | linting Kotlin"
  ":lang kotlin +lsp | kotlin-lsp/kotlin-lsp.sh | cask:kotlin-lsp | manual:github.com/Kotlin/kotlin-lsp/releases | manual:github.com/Kotlin/kotlin-lsp/releases | JetBrains' server (config/lsp/kotlin.el)"
  ":lang lua +lsp    | lua-language-server | brew:lua-language-server | manual:github.com/LuaLS/lua-language-server/releases | manual:github.com/LuaLS/lua-language-server/releases | Lua's server (it formats too)"
  ":lang markdown    | pandoc           | brew:pandoc           | apt:pandoc            | dnf:pandoc             | the live preview (config/markdown.el)"
  ":lang markdown +lsp | marksman       | brew:marksman         | manual:github.com/artempyanykh/marksman/releases | manual:github.com/artempyanykh/marksman/releases | Markdown's server"
  ":lang python      | python3          | builtin               | apt:python3           | dnf:python3            | Python"
  ":lang python      | black            | uv:black              | uv:black              | uv:black               | formatting Python"
  ":lang python      | isort            | uv:isort              | uv:isort              | uv:isort               | sorting imports"
  ":lang python +uv  | uv               | brew:uv               | apt:pipx pipx:uv      | dnf:uv                 | uv (and uv's tools here)"
  ":lang python +lsp | basedpyright     | uv:basedpyright       | uv:basedpyright       | uv:basedpyright        | Python's server (config/lsp/python.el)"
  ":lang rest +jq    | jq               | brew:jq               | apt:jq                | dnf:jq                 | restclient's jq"
  ":lang rust        | cargo            | manual:rustup.rs      | manual:rustup.rs      | manual:rustup.rs       | Rust (rustup: its components below)"
  ":lang rust +lsp   | rust-analyzer    | rustup:rust-analyzer rustup:rustfmt rustup:clippy | rustup:rust-analyzer rustup:rustfmt rustup:clippy | rustup:rust-analyzer rustup:rustfmt rustup:clippy | Rust's server, formatting, clippy on save"
  ":lang sh          | shellcheck       | brew:shellcheck       | apt:shellcheck        | dnf:ShellCheck         | linting shell scripts"
  ":lang sh          | shfmt            | brew:shfmt            | apt:shfmt             | dnf:shfmt              | formatting shell scripts"
  ":lang sh +lsp     | bash-language-server | npm:bash-language-server | npm:bash-language-server | npm:bash-language-server | shell's server"
  ":lang web         | js-beautify      | npm:js-beautify       | npm:js-beautify       | npm:js-beautify        | formatting HTML, CSS"
  ":lang web         | tidy             | brew:tidy-html5       | apt:tidy              | dnf:tidy               | formatting HTML"
  ":lang web         | stylelint        | npm:stylelint         | npm:stylelint         | npm:stylelint          | linting CSS"
  ":lang web         | prettier         | npm:prettier          | npm:prettier          | npm:prettier           | formatting (a project's own first)"
  ":lang web +lsp    | vscode-html-language-server | npm:vscode-langservers-extracted | npm:vscode-langservers-extracted | npm:vscode-langservers-extracted | HTML's and CSS's servers"
  ":lang yaml +lsp   | yaml-language-server | npm:yaml-language-server | npm:yaml-language-server | npm:yaml-language-server | YAML's server"
)

# Modules (and +lsp flags) that need nothing outside Emacs, or nothing more
# than TOOLS already has: they pass the check too.
NOTHING=(
  ":completion corfu" ":completion vertico"            # vertico: Doom's rg
  ":ui doom" ":ui dashboard" ":ui doom-quit" ":ui hl-todo" ":ui indent-guides"
  ":ui ligatures" ":ui modeline" ":ui ophints" ":ui popup" ":ui smooth-scroll"
  ":ui treemacs" ":ui treemacs +lsp" ":ui vc-gutter" ":ui vi-tilde-fringe"
  ":ui window-select" ":ui workspaces"
  ":editor evil" ":editor file-templates" ":editor fold" ":editor multiple-cursors"
  ":editor snippets" ":editor whitespace" ":editor word-wrap"
  ":editor format" ":editor format +lsp"               # each language's formatter is its row
  ":emacs electric" ":emacs ibuffer" ":emacs tramp" ":emacs undo" ":emacs vc"
  ":term ghostel"                                       # its native module: ghostel downloads it
  ":checkers syntax"                                    # each language's linter is its row
  ":tools debugger" ":tools debugger +lsp"              # adapters per language: M-x dap-*-setup
  ":tools editorconfig" ":tools eval" ":tools lookup" ":tools magit"
  ":os tty"
  ":lang emacs-lisp" ":lang org"
  ":lang gdscript +lsp"                                 # Godot's editor is the server, while open
  ":lang java +lsp"                                     # lsp-java downloads jdtls itself
  ":config default"
)

# ====== INIT.EL'S MODULES ======

if ! command -v "$EMACS" >/dev/null 2>&1; then
  echo "tools.sh: no Emacs to read init.el with (scripts/emacs.sh installs it; EMACS=...)" >&2
  exit 1
fi

# "CATEGORY MODULE FLAGS..." per enabled module of init.el's doom! block (its
# :if forms left out); Emacs reads it, as Doom does.
MODULES=$("$EMACS" --batch -Q --eval '
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
  "$DOOM_INIT")

trim() {
  local s=$1
  s=${s#"${s%%[![:space:]]*}"}
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

# enabled WHEN: does WHEN (doom, config, ":CATEGORY MODULE [+FLAG]") apply?
enabled() {
  local category module flag
  case "$1" in doom|config) return 0 ;; esac
  read -r category module flag <<<"$1"
  awk -v c="$category" -v m="$module" -v f="${flag:-}" '
    $1 == c && $2 == m { if (f == "") ok = 1; else for (i = 3; i <= NF; i++) if ($i == f) ok = 1 }
    END { exit !ok }' <<<"$MODULES"
}

# listed CATEGORY MODULE [FLAG]: is it in TOOLS's or NOTHING's WHENs?
listed() {
  local want="$1 $2${3:+ $3}" row when
  for row in "${TOOLS[@]}" "${NOTHING[@]}"; do
    when=$(trim "${row%%|*}")
    if [ -n "${3:-}" ]; then
      [ "$when" = "$want" ] && return 0
    else
      case "$when" in "$want"|"$want "*) return 0 ;; esac
    fi
  done
  return 1
}

# ====== VALIDATION ======

# Every enabled module has its row(s), every +lsp module its +lsp row.
problems=()
while read -r category module flags; do
  [ -n "$module" ] || continue
  listed "$category" "$module" ||
    problems+=("$category $module: no row in TOOLS or NOTHING (what it needs outside Emacs)")
  case " ${flags:-} " in
    *" +lsp "*)
      listed "$category" "$module" +lsp ||
        problems+=("$category $module +lsp: no \"$category $module +lsp\" row (its language server)") ;;
  esac
done <<<"$MODULES"
if [ ${#problems[@]} -gt 0 ]; then
  echo "tools.sh: init.el enables modules this script doesn't know; add them to TOOLS (or NOTHING):" >&2
  printf '  %s\n' "${problems[@]}" >&2
  exit 2
fi

# ====== WHAT APPLIES HERE ======

case "$OS" in
  macos) column=3 ;;
  apt|linux) column=4 ;;
  dnf) column=5 ;;
  *) echo "tools.sh: unknown system ($(uname -s))" >&2; exit 1 ;;
esac

# Per installer, what to install; the rows that apply here.
BREW=() CASK=() SYSTEM=() PIPX=() RUSTUP=() NPM=() UV=() APPLIES=()

for row in "${TOOLS[@]}"; do
  IFS='|' read -r when program macos apt dnf why <<<"$row"
  when=$(trim "$when")
  enabled "$when" || continue
  case $column in 3) cell=$macos ;; 4) cell=$apt ;; 5) cell=$dnf ;; esac
  cell=$(trim "$cell")
  [ "$cell" = - ] && continue
  APPLIES+=("$(trim "$program")|$cell|$(trim "$why")")
  for spec in $cell; do
    case "$spec" in
      brew:*) BREW+=("${spec#*:}") ;;
      cask:*) CASK+=("${spec#*:}") ;;
      apt:*|dnf:*) SYSTEM+=("${spec#*:}") ;;
      pipx:*) PIPX+=("${spec#*:}") ;;
      rustup:*) RUSTUP+=("${spec#*:}") ;;
      npm:*) NPM+=("${spec#*:}") ;;
      uv:*) UV+=("${spec#*:}") ;;
      builtin|manual:*) ;;
      *) echo "tools.sh: bad installer \"$spec\" in TOOLS ($(trim "$program"))" >&2; exit 2 ;;
    esac
  done
done

# Each once (rows share packages: web, json and javascript's servers), in the
# order first named.
once() {
  local name
  while read -r name; do
    if [ -n "$name" ]; then printf '%s\n' "$name"; fi
  done < <(printf '%s\n' "$@" | awk '!seen[$0]++')
}
dedupe() { # dedupe ARRAY: its values, each once (word list)
  case "$1" in
    BREW) once ${BREW[@]+"${BREW[@]}"} ;;
    CASK) once ${CASK[@]+"${CASK[@]}"} ;;
    SYSTEM) once ${SYSTEM[@]+"${SYSTEM[@]}"} ;;
    PIPX) once ${PIPX[@]+"${PIPX[@]}"} ;;
    RUSTUP) once ${RUSTUP[@]+"${RUSTUP[@]}"} ;;
    NPM) once ${NPM[@]+"${NPM[@]}"} ;;
    UV) once ${UV[@]+"${UV[@]}"} ;;
  esac
}
# shellcheck disable=SC2207  # package names: no spaces
{
  BREW=($(dedupe BREW)) CASK=($(dedupe CASK)) SYSTEM=($(dedupe SYSTEM)) PIPX=($(dedupe PIPX))
  RUSTUP=($(dedupe RUSTUP)) NPM=($(dedupe NPM)) UV=($(dedupe UV))
}

# ====== INSTALL OR UPDATE ======

if [ -z "$CHECK_ONLY" ]; then
  echo "Installing or updating (init.el: $(grep -c . <<<"$MODULES") modules):"
  case "$OS" in
    macos)
      [ ${#BREW[@]} -gt 0 ] && brew_latest "${BREW[@]}"
      [ ${#CASK[@]} -gt 0 ] && brew_latest --cask "${CASK[@]}" ;;
    apt)
      pkg_update
      [ ${#SYSTEM[@]} -gt 0 ] && { run $SUDO apt-get install -y "${SYSTEM[@]}" || OS_SKIPPED+=("${SYSTEM[*]}"); } ;;
    dnf)
      [ ${#SYSTEM[@]} -gt 0 ] && { { run $SUDO dnf install -y "${SYSTEM[@]}" &&
                                     run $SUDO dnf upgrade -y "${SYSTEM[@]}"; } || OS_SKIPPED+=("${SYSTEM[*]}"); } ;;
    linux)
      [ ${#SYSTEM[@]} -gt 0 ] && manual "your distribution's packages: ${SYSTEM[*]}" ;;
  esac
  for tool in ${PIPX[@]+"${PIPX[@]}"}; do
    run pipx upgrade "$tool" 2>/dev/null || run pipx install "$tool" || OS_SKIPPED+=("$tool (pipx)")
  done
  [ ${#PIPX[@]} -gt 0 ] && export PATH="$HOME/.local/bin:$PATH"
  if [ ${#RUSTUP[@]} -gt 0 ]; then
    if command -v rustup >/dev/null 2>&1 || [ -n "${DRY_RUN:-}" ]; then
      run rustup component add "${RUSTUP[@]}" || OS_SKIPPED+=("${RUSTUP[*]} (rustup)")
      run rustup update || true
    else
      manual "rustup (rustup.rs), then: rustup component add ${RUSTUP[*]}"
    fi
  fi
  [ ${#NPM[@]} -gt 0 ] && { npm_global "${NPM[@]}" || OS_SKIPPED+=("${NPM[*]} (npm)"); }
  [ ${#UV[@]} -gt 0 ] && uv_tool "${UV[@]}"
fi

# ====== CHECK ======

# found PROGRAM: a command (a/b: either), or font:NAME.
found() {
  local program=$1 alternative
  case "$program" in
    font:*)
      local name=${program#font:}
      # grep reads all (not -q): an early exit would kill fc-list, failing the
      # pipeline (pipefail).
      if command -v fc-list >/dev/null 2>&1; then
        fc-list : family | grep -i "$name" >/dev/null
      else
        find ~/Library/Fonts /Library/Fonts -maxdepth 1 2>/dev/null | tr -d ' ' | grep -i "${name// /}" >/dev/null
      fi ;;
    *)
      for alternative in ${program//\// }; do
        command -v "$alternative" >/dev/null 2>&1 && return 0
      done
      return 1 ;;
  esac
}

echo -e "\nChecking:"
missing=0
checked=" "
for entry in "${APPLIES[@]}"; do
  IFS='|' read -r program cell why <<<"$entry"
  # Each program once (rows share some: npm, python3, prettier...).
  case "$checked" in *" $program "*) continue ;; esac
  checked="$checked$program "
  if found "$program"; then
    printf '  ok       %-30s %s\n' "$program" "$why"
  else
    missing=$((missing + 1))
    case "$cell" in
      *manual:*) how=" (by hand: $(sed -E 's/.*manual:([^ ]*).*/\1/; s/_/ /g' <<<"$cell"))" ;;
      *) how= ;;
    esac
    printf '  MISSING  %-30s %s%s\n' "$program" "$why" "$how"
  fi
done

os_summary
if [ "$missing" -gt 0 ]; then
  echo -e "\n$missing missing (see above)."
fi
