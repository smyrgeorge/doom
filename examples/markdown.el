;;; $DOOMDIR/examples/markdown.el -*- lexical-binding: t; -*-
;; Example: a Markdown file and its live preview (config/markdown.el,
;; docs/markdown.md). M-x +my/example-markdown writes a README to the temp
;; folder (headings, lists, a table, code, a quote, links) and opens it with
;; its preview beside it (SPC m p): it re-renders as you type and follows the
;; cursor. Try typing, moving down the file, a link in the preview. The file is
;; deleted once it's closed (its preview with it).

;; ====== VARIABLES ======

(defconst +my/example-markdown--text "# Fruit shop

A small shop's tools: its **inventory**, the **prices**, and a weekly
*report*. Written in Python, tested with `pytest`.

## Getting started

1. Install the dependencies: `pip install -r requirements.txt`
2. Fill `prices.toml` with this week's prices
3. Run the report:

```python
from shop.report import weekly

for line in weekly(\"2026-W45\"):
    print(line)
```

> Prices change every Monday: run the report after the delivery.

## What it sells

| Fruit   | Price (per kg) | In stock |
|---------|---------------:|:--------:|
| Apples  |           2.40 |    ✓     |
| Pears   |           3.10 |    ✓     |
| Plums   |           4.50 |    —     |
| Oranges |           2.90 |    ✓     |

## Tasks

- [x] Weekly report
- [x] Prices from a file
- [ ] Gift baskets
- [ ] An online shop

## Links

- [Prices](#what-it-sells), on this page
- The [Python docs](https://docs.python.org/3/)
"
  "The README.")

;; ====== CODE ======

(defun +my/example-markdown ()
  "Example: a Markdown file and its live preview (deleted once closed). See
examples/markdown.el."
  (interactive)
  (let* ((dir (+my/example-folder "markdown"))
         (file (+my/example-write dir "README.md" +my/example-markdown--text)))
    (delete-other-windows)
    (find-file file)
    (let ((buffer (current-buffer)))
      (if (+my/markdown-preview-live-p)
          (+my/markdown-preview-toggle)
        (message "No live preview here (it needs the GUI and pandoc): SPC m p shows markdown-mode's"))
      (when (window-live-p (get-buffer-window buffer))
        (select-window (get-buffer-window buffer)))
      (+my/example-delete-when-closed dir (list buffer))
      (when (+my/markdown-preview-live-p)
        (message "Markdown example: type, move down the file, click a link in the preview; SPC m p closes it"))
      buffer)))

(defun +my/example-markdown-ready ()
  "Non-nil once the example's preview has loaded."
  (when-let* ((source (seq-find (lambda (buffer)
                                  (and (buffer-local-value '+my/example--closing buffer)
                                       (buffer-local-value '+md-preview--buffer buffer)))
                                (buffer-list)))
              (preview (buffer-local-value '+md-preview--buffer source))
              ((buffer-live-p preview))
              (window (get-buffer-window preview t))
              (xwidget (with-current-buffer preview (+my/webkit-xwidget window))))
    (or (not (fboundp 'xwidget-webkit-estimated-load-progress))
        (>= (xwidget-webkit-estimated-load-progress xwidget) 1.0))))

(provide 'example-markdown)
