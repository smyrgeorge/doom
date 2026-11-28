;;; $DOOMDIR/config/editor/package-lint.el -*- lexical-binding: t; -*-
;; Emacs Lisp packages checked (flycheck-package, package-lint): their
;; dependencies' installability only when package.el knows its archives.
;; Loaded from config/editor.el.

(defun +my/package-lint-archives-known-a (&rest _)
  "Non-nil when package.el has its archives' index or installed packages
\(`package-archive-contents', `package-alist'): under Doom, which installs
with straight, both are empty, and every dependency was \"not installable\"."
  (or package-archive-contents package-alist))

(after! package-lint
  (advice-add 'package-lint--check-packages-installable :before-while
              #'+my/package-lint-archives-known-a))
