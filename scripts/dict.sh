#!/usr/bin/env bash
set -euo pipefail

# Build dict/tech.txt: programming words (rect, rgba, kotlin, stdout, ...) for
# the spell checker, from cspell's MIT-licensed dictionaries
# (https://github.com/streetsidesoftware/cspell-dicts). config/spell.el loads it
# next to English. Re-run to update; the result is committed.
#
# Needs npm and aspell. `npm pack` only downloads the packages (no scripts run).

DICTS=(
  software-terms fullstack companies public-licenses filetypes
  css html markdown fonts lorem-ipsum
  python rust kotlin java cpp gdscript
  shell docker k8s sql typescript node
  git makefile redis aws google terraform
  gaming-terms
)

# Words no cspell dictionary has. Add more here, then re-run.
EXTRA_WORDS=(
  # build tools
  gradle gradlew kts buildscript
  # file formats and extensions
  yml jsonl tgz tbz txz zst dmg msix whl aar qcow ovf mts pyi ejs styl otf svgz
  mkv jfif adoc srt vtt cer jks keystore xcconfig
  # config files
  nvmrc yarnrc pnpmrc browserslist helmignore
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dict/tech.txt"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"

echo "Downloading ${#DICTS[@]} cspell dictionaries:"
for d in "${DICTS[@]}"; do
  npm pack --silent "@cspell/dict-$d" >/dev/null
  echo "  @cspell/dict-$d"
done

for tgz in *.tgz; do
  mkdir -p "${tgz%.tgz}"
  tar -xzf "$tgz" -C "${tgz%.tgz}"
done

# Word lists are plain text (some gzipped), one entry per line, under dict/ or
# at the package root. cspell syntax: '#' comments, '!' forbidden words
# (dropped), '~' '+' '*' markers (stripped).
{
  find . \( -name '*.txt' -o -name '*.txt.gz' \) -print0 |
    while IFS= read -r -d '' f; do
      case "$f" in *.gz) gzip -dc "$f" ;; *) cat "$f" ;; esac
    done
  printf '%s\n' "${EXTRA_WORDS[@]}"
} |
  sed -e 's/#.*//' |
  grep -v '^[[:space:]]*!' |
  tr -d '~+*' |
  # spell-fu checks runs of letters, so split entries into those
  tr -cs '[:alpha:]' '\n' |
  awk 'length($0) >= 2' |
  tr '[:upper:]' '[:lower:]' |
  sort -u >words.txt

# Keep only what English doesn't already know.
aspell --lang=en list <words.txt | sort -u >"$OUT"

echo "Wrote $(wc -l <"$OUT" | tr -d ' ') words to ${OUT#"$ROOT"/} (from $(wc -l <words.txt | tr -d ' ') entries)."
