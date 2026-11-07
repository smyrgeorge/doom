;;; $DOOMDIR/examples/tiling.el -*- lexical-binding: t; -*-
;; Example: tiling (config/tiling.el, docs/editor.md). M-x +my/example-tiling
;; writes a small project to the temp folder and opens its files in panes as
;; SPC w SPC opens them: the tiling strategy (tall) puts the first on the left,
;; the others stacked on the right. Try SPC w SPC for one more, SPC w a to
;; arrange them again after splits of your own. The files are deleted once
;; their buffers are all closed.

;; ====== VARIABLES ======

(defconst +my/example-tiling--files
  '(("shop/app.py" . "\"\"\"The shop: a cart, its prices, a receipt.\"\"\"

from shop.cart import Cart
from shop.prices import price_of


def main():
    cart = Cart()
    cart.add(\"apple\", 3)
    cart.add(\"pear\", 2)
    cart.add(\"plum\", 6)
    for line in cart.receipt(price_of):
        print(line)


if __name__ == \"__main__\":
    main()
")
    ("shop/cart.py" . "\"\"\"A cart: what's in it, how many of each.\"\"\"

from collections import Counter


class Cart:
    def __init__(self):
        self.items = Counter()

    def add(self, name, quantity=1):
        self.items[name] += quantity

    def remove(self, name, quantity=1):
        self.items[name] -= quantity
        if self.items[name] <= 0:
            del self.items[name]

    def total(self, price_of):
        return sum(price_of(name) * n for name, n in self.items.items())

    def receipt(self, price_of):
        for name, n in sorted(self.items.items()):
            yield f\"{name:<8} {n:>3} x {price_of(name):5.2f}\"
        yield f\"{'total':<14} {self.total(price_of):7.2f}\"
")
    ("shop/prices.py" . "\"\"\"Prices, per piece.\"\"\"

PRICES = {
    \"apple\": 0.40,
    \"pear\": 0.55,
    \"plum\": 0.25,
    \"cherry\": 0.05,
}


def price_of(name):
    return PRICES[name]
")
    ("tests/test_cart.py" . "from shop.cart import Cart


def test_total():
    cart = Cart()
    cart.add(\"apple\", 2)
    cart.add(\"pear\")
    assert cart.total({\"apple\": 1.0, \"pear\": 2.0}.get) == 4.0


def test_remove_all():
    cart = Cart()
    cart.add(\"plum\", 3)
    cart.remove(\"plum\", 3)
    assert not cart.items
"))
  "The project's files: (NAME . TEXT), the first the main pane's.")

;; ====== CODE ======

(defun +my/example-tiling ()
  "Example: a project's files in panes laid out by the tiling strategy, as
SPC w SPC opens them (deleted once closed). See examples/tiling.el."
  (interactive)
  (let* ((dir (+my/example-folder "tiling"))
         (files (mapcar (lambda (file) (+my/example-write dir (car file) (cdr file)))
                        +my/example-tiling--files))
         (buffers nil))
    (delete-other-windows)
    (find-file (car files))
    (push (current-buffer) buffers)
    (let ((main (selected-window)))
      (dolist (file (cdr files))
        ;; SPC w SPC: a new pane where the strategy puts it, then the file.
        (select-window (+my/tiling-split))
        (find-file file)
        ;; Its file its only tab (the pane opened on the current one).
        (set-window-prev-buffers nil nil)
        (set-window-next-buffers nil nil)
        (set-window-parameter nil 'tab-line-buffers nil)
        (push (current-buffer) buffers))
      (select-window main))
    (+my/example-delete-when-closed dir buffers)
    (message "Tiling example: SPC w SPC opens another pane where the strategy puts it, SPC w a arranges them")
    (nreverse buffers)))

(provide 'example-tiling)
