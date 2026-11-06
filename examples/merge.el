;;; $DOOMDIR/examples/merge.el -*- lexical-binding: t; -*-
;; Example: conflicts resolved in three panes (config/merge.el, docs/git.md).
;; M-x +my/example-merge (or M-x +my/example, merge) makes a Git repository
;; in the temp folder where merging a branch conflicts in orders.py, every
;; way the panes handle, and opens it as Magit's e would. Try anything: the
;; repository is deleted once the merge is closed (Done or Abort), what Done
;; saved with it.

;; ====== VARIABLES ======

;; The file, as the branches have it. main (Yours): the tax rate 24%, a
;; bigger welcome discount, tax() given a rate, no code as "", the legacy
;; receipt removed. feature (Theirs): the tax rate 21%, a VIP discount, tax
;; rounded up, refunds, prices with two decimals. Both: the subtotal's
;; docstring reworded the same. So: a conflict over the same word (the rate:
;; keep one, or both), two the wand merges (discount(), tax()), a change of
;; each side alone, lines added, lines removed, the same change on both.
(defconst +my/example-merge--base "\"\"\"Orders: totals, discounts and receipts.\"\"\"

import math

TAX_RATE = 0.20


def subtotal(items):
    \"\"\"The sum of the items' prices times their quantities.\"\"\"
    return sum(item.price * item.quantity for item in items)


def discount(total, code):
    \"\"\"The discount a code gives on a total.\"\"\"
    if code == \"WELCOME\":
        return total * 0.10
    return 0


def tax(amount):
    return amount * TAX_RATE


def total(items, code=None):
    amount = subtotal(items)
    amount -= discount(amount, code)
    return round(amount + tax(amount), 2)


def receipt(items, code=None):
    lines = [f\"{item.name}: {item.price}\" for item in items]
    lines.append(f\"Total: {total(items, code)}\")
    return \"\\n\".join(lines)


def legacy_receipt(items):
    \"\"\"Kept for old callers.\"\"\"
    return receipt(items)
"
  "orders.py where both branches started.")

(defconst +my/example-merge--yours "\"\"\"Orders: totals, discounts and receipts.\"\"\"

import math

TAX_RATE = 0.24


def subtotal(items):
    \"\"\"Sum of price × quantity over the items.\"\"\"
    return sum(item.price * item.quantity for item in items)


def discount(total, code):
    \"\"\"The discount a code gives on a total.\"\"\"
    if code == \"WELCOME\":
        return total * 0.15
    return 0


def tax(amount, rate=TAX_RATE):
    return amount * TAX_RATE


def total(items, code=None):
    amount = subtotal(items)
    amount -= discount(amount, code or \"\")
    return round(amount + tax(amount), 2)


def receipt(items, code=None):
    lines = [f\"{item.name}: {item.price}\" for item in items]
    lines.append(f\"Total: {total(items, code)}\")
    return \"\\n\".join(lines)
"
  "orders.py on main (Yours).")

(defconst +my/example-merge--theirs "\"\"\"Orders: totals, discounts and receipts.\"\"\"

import math

TAX_RATE = 0.21


def subtotal(items):
    \"\"\"Sum of price × quantity over the items.\"\"\"
    return sum(item.price * item.quantity for item in items)


def discount(total, code):
    \"\"\"The discount a code gives on a total.\"\"\"
    if code == \"WELCOME\":
        return total * 0.10
    if code == \"VIP\":
        return total * 0.25
    return 0


def tax(amount):
    return math.ceil(amount * TAX_RATE * 100) / 100


def total(items, code=None):
    amount = subtotal(items)
    amount -= discount(amount, code)
    return round(amount + tax(amount), 2)


def refund(items, code=None):
    \"\"\"What a cancelled order gives back.\"\"\"
    return total(items, code)


def receipt(items, code=None):
    lines = [f\"{item.name}: {item.price:.2f}\" for item in items]
    lines.append(f\"Total: {total(items, code)}\")
    return \"\\n\".join(lines)


def legacy_receipt(items):
    \"\"\"Kept for old callers.\"\"\"
    return receipt(items)
"
  "orders.py on feature (Theirs).")

;; ====== CODE ======

(defvar +my/example-merge--repos nil
  "The example's repositories not deleted yet (their merges open).")

(defun +my/example-merge--git (&rest args)
  "Run git with ARGS in the current folder, as no one in particular (not
your name, hooks or signing): its exit status."
  (let ((process-environment (append '("GIT_EDITOR=true" "GIT_TERMINAL_PROMPT=0")
                                     process-environment)))
    (apply #'call-process "git" nil nil nil
           "-c" "user.name=Example" "-c" "user.email=example@example.invalid"
           "-c" "commit.gpgsign=false" "-c" "core.hooksPath=/dev/null"
           "-c" "init.defaultBranch=main" "-c" "merge.conflictStyle=merge"
           args)))

(defun +my/example-merge--write (text)
  (let ((coding-system-for-write 'utf-8-unix))
    (write-region text nil "orders.py" nil 'silent)))

(defun +my/example-merge--repo ()
  "A new repository in the temp folder, merging feature into main and in
conflict in orders.py; its folder."
  (let ((default-directory (file-name-as-directory
                            (file-truename (make-temp-file "merge-example-" t)))))
    (dolist (step `((init "-q")
                    (write ,+my/example-merge--base)
                    (git "add" "orders.py")
                    (git "commit" "-qm" "Orders")
                    (git "checkout" "-qb" "feature")
                    (write ,+my/example-merge--theirs)
                    (git "commit" "-qam" "VIP discount, refunds, tax rounded up, 21%")
                    (git "checkout" "-q" "main")
                    (write ,+my/example-merge--yours)
                    (git "commit" "-qam" "Tax at 24%, bigger welcome discount")))
      (pcase step
        (`(write ,text) (+my/example-merge--write text))
        (`(init . ,args) (apply #'+my/example-merge--git "init" args))
        (`(git . ,args)
         (unless (zerop (apply #'+my/example-merge--git args))
           (error "Example: git %s failed" (string-join args " "))))))
    ;; Conflicts: git merge says so (1).
    (+my/example-merge--git "merge" "-q" "feature")
    default-directory))

(defun +my/example-merge--cleanup (session)
  "A merge closed: its repository deleted if it's one of the example's."
  (let ((repo (+my/merge-toplevel session)))
    (when (member repo +my/example-merge--repos)
      (setq +my/example-merge--repos (delete repo +my/example-merge--repos))
      (unless +my/example-merge--repos
        (remove-hook '+my/merge-finished-functions #'+my/example-merge--cleanup))
      (ignore-errors (delete-directory repo t)))))

(defun +my/example-merge ()
  "Example: conflicts resolved in three panes, on a temp repository (deleted
once the merge is closed). See examples/merge.el."
  (interactive)
  (let* ((repo (+my/example-merge--repo))
         (default-directory repo))
    (push repo +my/example-merge--repos)
    (add-hook '+my/merge-finished-functions #'+my/example-merge--cleanup)
    (prog1 (condition-case err
               (+my/merge "orders.py")
             (error (+my/example-merge--cleanup (+my/merge--make :toplevel repo))
                    (signal (car err) (cdr err))))
      (message "Merge example (a temp repo, deleted when closed): the margins' >> << x, the ✨ wands on discount() and tax(), the bar's buttons; Done or Abort"))))

(provide 'example-merge)
