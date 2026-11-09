#!/usr/bin/env bash
# The scripts' output, alike (sourced by scripts/*.sh, tests/run.sh,
# tests/linux/run.sh, cmd/diff):
#
#   ==> A step                     ui_step
#   ✔ done                        ui_ok
#   ✖ failed                      ui_fail
#   ⚠ to look at                   ui_warn
#   • a note                       ui_info
#   $ a command run                ui_cmd
#   ✖ script: what went wrong     ui_error (stderr)
#
# Colours only on a terminal, and not with NO_COLOR set (no-color.org): in a
# log or a test, the same lines, plain.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    UI_RESET=$'\e[0m' UI_BOLD=$'\e[1m' UI_DIM=$'\e[2m'
    UI_RED=$'\e[31m' UI_GREEN=$'\e[32m' UI_YELLOW=$'\e[33m' UI_BLUE=$'\e[34m'
else
    UI_RESET='' UI_BOLD='' UI_DIM='' UI_RED='' UI_GREEN='' UI_YELLOW='' UI_BLUE=''
fi
# stderr's own: it may be a terminal when stdout isn't, or the reverse.
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-dumb}" != dumb ]; then
    UI_ERR_RED=$'\e[31m' UI_ERR_RESET=$'\e[0m'
else
    UI_ERR_RED='' UI_ERR_RESET=''
fi

ui_step() { printf '%s==>%s %s%s%s\n' "$UI_BLUE$UI_BOLD" "$UI_RESET" "$UI_BOLD" "$*" "$UI_RESET"; }
ui_ok() { printf '  %s✔%s %s\n' "$UI_GREEN" "$UI_RESET" "$*"; }
ui_fail() { printf '  %s✖%s %s\n' "$UI_RED" "$UI_RESET" "$*"; }
ui_warn() { printf '  %s⚠%s %s\n' "$UI_YELLOW" "$UI_RESET" "$*"; }
ui_info() { printf '  %s•%s %s\n' "$UI_DIM" "$UI_RESET" "$*"; }
ui_cmd() { printf '  %s$ %s%s\n' "$UI_DIM" "$*" "$UI_RESET"; }
ui_error() { printf '%s✖ %s%s\n' "$UI_ERR_RED" "$*" "$UI_ERR_RESET" >&2; }

# ui_dim TEXT / ui_green TEXT...: TEXT coloured, for inside a line.
ui_dim() { printf '%s%s%s' "$UI_DIM" "$*" "$UI_RESET"; }
ui_green() { printf '%s%s%s' "$UI_GREEN" "$*" "$UI_RESET"; }
ui_red() { printf '%s%s%s' "$UI_RED" "$*" "$UI_RESET"; }
ui_yellow() { printf '%s%s%s' "$UI_YELLOW" "$*" "$UI_RESET"; }
ui_bold() { printf '%s%s%s' "$UI_BOLD" "$*" "$UI_RESET"; }
