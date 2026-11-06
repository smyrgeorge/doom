# Code: language servers, actions, spelling

## Go to declaration or usages (`Cmd+B`)

On a use of a symbol, `Cmd+B` jumps to its declaration (`gd`); on the declaration itself, it lists the usages in the
peek (`gD`, see [Usages peek](#usages-peek)), like IntelliJ's Go to Declaration or Usages. Declarations come from the
language server (Emacs itself in Emacs Lisp); without one, Doom's lookup falls back to searching the project. Where the
server knows no declaration (e.g. a Markdown heading: links point to it), it lists the usages too. `Cmd+[` goes back
(`config/editor.el`).

## Context actions (Option+Enter)

`config/actions.el` gives `M-RET` (Option+Enter) one menu with everything that applies at point, like Alt+Enter in
JetBrains IDEs:

- **Spelling** (when the word at point is underlined): the top aspell suggestions (5,
  `+my/context-actions-max-suggestions`) and "Add to dictionary".
- **Code actions**: the LSP server's quick fixes and refactors for the point or the active region (same list as
  `SPC c a`).
- **Claude** (agent-shell): *Fix / Explain error with Claude* for the error or warning at point and *Explain selection
  with Claude* are sent straight away (queued if Claude is busy, a Claude Code shell is started if the project has
  none); *Add selection / file to Claude prompt* puts the context in the prompt for you to finish.
- **PDF** (in a [PDF](editor.md#pdfs-in-webkit), first): for the text selected in it, *Copy*, *Search the PDF for it*,
  *Search the web for it*, and the Claude actions on it (quoted, with the file and page); *Open in Preview*, *Print*.
- **Drawing** (last): in Markdown and Org, *Insert a new drawing*, linked at point as an image; on a link to a
  [drawing](editor.md#drawings-excalidraw), *Edit the drawing*, beside.

Works in visual state too, on the selection. Each section comes from a provider function listed in
`+my/context-action-providers`; new kinds of actions are added by writing another provider. Org keeps `M-RET` for "new
heading/item". In Markdown, `M-RET` was "new list item" (`M-x markdown-ts-insert-list-item`) and, in a table, "new row
below" (`M-x markdown-ts-table-insert-row-below`).

## Usages peek

`config/peek.el` reworks lsp-ui's peek, the inline panel that lists usages (`gD`, or `Cmd+B` on a declaration) and
definitions:

- a header that says what's listed (`Usages of HOLD1 · 22 in 1 file`) and a footer with the keys (`j`/`k`, `C-j`/`C-k`
  file, `RET` open, `M-RET` other window, `Esc` close);
- each usage shows the function/class it's in, grouped: the name on the first usage of each, with a count (`×21`);
  outside functions, the top-level variable it's in (e.g. a constant holding a big literal);
- usages don't include the declaration itself;
- the preview has line numbers, with the usage's line highlighted, and shows non-ASCII text (`–`, Greek) as such:
  lsp-ui read files that aren't open without decoding them (`\342\200\223`);
- it stands out from the code: an empty row above and below in the colour of its top and bottom bars, and a panel
  clearly darker than the editor (the preview more than the list), all following the theme; softer colours for the
  selection and the matches, and only as tall as the list needs (at least `+my/peek-min-height` rows, 10; at most
  `lsp-ui-peek-peek-height`, 20);
- the function/class names take up to `+my/peek-scope-width` columns (24).

## Code lenses

What the language server offers at the end of the line: rust-analyzer's "▶ Run", implementations
and reference counts; reference counts and implementations for TypeScript, reference counts for JavaScript;
marksman's reference counts on Markdown headings (pyright, for Python, sends none). (Rust's "Debug" lens is off until a
debugger is set up.) Placing them doesn't measure the line on screen first (see
[Opening files faster](performance.md#opening-files-faster)).

## LSP project import

Opening a file in a project starts its language server in the project root (the git
repository) without the "import project root?" prompt, like Zed. Files outside any project still ask, so a stray
file in `~` never makes a server scan your home folder (`config/lsp.el`).

## LSP file watchers

Lsp-mode watches every directory under the project root but doesn't read `.gitignore`;
`config/lsp.el` also skips what git ignores, so a root with big ignored folders (e.g. repositories cloned inside
it) needs a few dozen watches instead of thousands, without the "watch N directories?" prompt.

## Kotlin

JetBrains' official [`kotlin-lsp`](https://github.com/Kotlin/kotlin-lsp) instead of the community
`kotlin-language-server`; with `format +lsp`, Kotlin is formatted by IntelliJ's formatter.

## Spelling in code

Besides English and your personal dictionary, spell-fu knows ~40k programming words
(`rect`, `rgba`, `async`, `kotlin`, `stdout`, ...) from `dict/tech.txt`, built by `scripts/dict.sh` from
[cspell](https://github.com/streetsidesoftware/cspell-dicts)'s MIT-licensed dictionaries (only words English lacks).
CamelCase identifiers are checked word by word (`AgreementController` = `Agreement` + `Controller`). Words you add
with `zg` or Option+Enter still go to the personal dictionary, Doom's, under `~/.config/emacs/.local/etc/ispell/`
(created if missing: spell-fu ignored it until the file existed). `+my/spell-tech-words-file` is the word list.
