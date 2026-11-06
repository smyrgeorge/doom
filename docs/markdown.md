# Markdown

## Live Markdown preview

`config/markdown.el` renders Markdown in a WebKit side window (xwidgets) **inside Emacs**:

- **Updates as you type** (≈0.3 s after you stop), swapping the page content without reloading.
- **Scrolls to the cursor line**, using pandoc's `sourcepos` extension to map each element back to its source line.
- **GitHub look**: github-markdown-css plus highlight.js, following the macOS light/dark setting; as wide as the pane.
- Math is rendered as MathML; relative image links work.
- In terminal Emacs it falls back to markdown-mode's `eww` preview (updates on save).

Requires `pandoc`. Styles are loaded from a CDN, so the preview is unstyled offline.

## Markdown links

Two false warnings from marksman are hidden when the link is a path to an existing file
(`config/markdown.el`): "Ambiguous link to document", when the linked file has more than one top-level `#` heading
(genuinely ambiguous links, like `[[README]]` matching several files, are still reported); and "Link to non-existent
document", for files git ignores, which marksman doesn't index (links to files that are really missing are still
reported).
