# Markdown

## Live Markdown preview

`config/markdown.el` renders Markdown in a WebKit side window (xwidgets) **inside Emacs**. `SPC m p` toggles it: it
opens on the right, half the window's width, as its own tab (`Preview: FILE`; no "WebKit: TITLE" row above the page),
and the cursor stays in the file; it closes with `SPC m p` again or when the file is closed. The page fills the pane,
edge to edge, in its own background (GitHub's dark `#0d1117` or white, following macOS). It opens without a white flash:
WebKit's view is white until its page has loaded (its stylesheet comes from a CDN), so until then the pane is covered in
that background (2 s at most). `SPC m P` previews in the browser instead. A Markdown file opens with a notice at the top
offering the preview (**Open preview**); it goes once the preview opens or with its `✕`, and doesn't come back for that
buffer (only where the live preview works; `+my/markdown-preview-notice` nil turns it off).

- **Updates as you type** (≈0.3 s after you stop), swapping the page content without reloading.
- **Scrolls to the cursor line**, using pandoc's `sourcepos` extension to map each element back to its source line.
- **Splits**: split its pane (`SPC w s`, `SPC w SPC`, the tab's menu...) and each half shows the preview, both following
  the cursor (a WebKit view per window, `config/webkit.el`, as for PDFs).
- **Links**: to a heading of the file (`#install`), it scrolls there; to a file, it opens in Emacs, in the Markdown
  file's pane; anything else opens in the browser. The preview stays on its page.
- **Keys** in its pane: `j` / `k`, `C-d` / `C-u`, `C-f` / `C-b`, `gg` / `G` scroll, `y` or `Cmd+C` copies the selected
  text, `q` closes it (as `SPC m p`; so does its tab's `✕`). A click only selects the pane; selecting text and
  following links are WebKit's.
- **GitHub look**: github-markdown-css plus highlight.js, following the macOS light/dark setting; as wide as the pane.
- Math is rendered as MathML; relative image links work.

Needs `pandoc` (`scripts/lsp.sh` installs it) and an Emacs with xwidgets (emacs-plus has them); otherwise, and in
terminal Emacs, `SPC m p` falls back to markdown-mode's `eww` preview (updates on save). Styles are loaded from a CDN,
so the preview is unstyled offline.

## Markdown links

Two false warnings from marksman are hidden when the link is a path to an existing file
(`config/markdown.el`): "Ambiguous link to document", when the linked file has more than one top-level `#` heading
(genuinely ambiguous links, like `[[README]]` matching several files, are still reported); and "Link to non-existent
document", for files git ignores, which marksman doesn't index (links to files that are really missing are still
reported).
