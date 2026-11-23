;;; tests/unit/test-agent-workflow-pick.el -*- lexical-binding: t; -*-
;; config/agent-workflow/queue.el's issue picker (M-x agent-workflow-run-ticket's
;; "Run on:"), keys typed into it, vertico on as in Doom and without it: a
;; title with a comma picked with RET (the comma no longer cutting it in
;; two), several separated by what no title has, an epic for its issues;
;; each issue drawn as the issue list draws it (config/beads/look.el): its
;; status, priority and type before it, its labels after. Stand-in issues: no
;; bd.

(load (expand-file-name "beads-autoloads" (file-name-directory (locate-library "beads"))) nil t)
(let ((build (file-name-directory (directory-file-name (file-name-directory (locate-library "vertico"))))))
  (dolist (package '("vertico" "orderless"))
    (load (expand-file-name (format "%s/%s-autoloads" package package) build) t t)))
(+test-load "config/window" "config/tiling" "config/childframe" "config/banner" "config/beads"
            "config/agent-workflow")

(require 'vertico)
(require 'orderless)
(setq completion-styles '(orderless basic))  ; as Doom
(require 'beads-faces)
(require 'doom-themes)                  ; doom-blend
(require 'nerd-icons)                   ; the types' icons

;; ====== HELPERS ======

(defun +test-awk--issue (id title type &rest more)
  "A stand-in open issue ID, as `agent-workflow-open-issues' has it: MORE
bd's other keys (status, priority, labels...) as a plist."
  (list id title type
        (append `((id . ,id) (title . ,title) (issue_type . ,type))
                (let (alist)
                  (while more
                    (push (cons (intern (substring (symbol-name (pop more)) 1)) (pop more)) alist))
                  (nreverse alist)))))

(defconst +test-awk--issues
  (list (+test-awk--issue "demo-1" "Parser rewrite" "epic" :status "open" :priority 1 :labels '("parser"))
        (+test-awk--issue "demo-2" "Examples: the screenshots taken again, each as it looks today" "chore"
                          :status "open" :priority 3 :labels '("workflow:quick"))
        (+test-awk--issue "demo-3" "Crash on an empty file" "bug" :status "in_progress" :priority 0)
        (+test-awk--issue "demo-4" "Release 2.0" "task" :status "open" :priority 2
                          :dependencies '(((type . "blocks") (depends_on_id . "demo-3")))))
  "Open issues: a title with a comma, an epic, one blocked by another.")

(defmacro +test-awk (&rest body)
  "BODY with `+test-awk--issues' as the project's open issues, demo-1's
issues demo-11 and demo-12."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'agent-workflow-open-issues) (lambda (_) +test-awk--issues))
             ((symbol-function 'agent-workflow-epic-issues)
              (lambda (_ id) (and (equal id "demo-1") '("demo-11" "demo-12")))))
     ,@body))

(defun +test-awk--pick (keys &optional vertico)
  "The issues picked by typing KEYS (`kbd' syntax) in the picker, with
VERTICO on: their ids, or (error MESSAGE)."
  (let* ((picked nil)
         (map (define-keymap "<f5>" (lambda () (interactive)
                                      (setq picked (condition-case err (agent-workflow--read-issues "/tmp/")
                                                     (user-error (list 'error (cadr err)))))))))
    (with-current-buffer (switch-to-buffer (get-buffer-create "*awk*"))
      (use-local-map map)
      (when vertico (vertico-mode 1))
      (unwind-protect
          (+test-awk (execute-kbd-macro (vconcat (kbd "<f5>") (kbd keys))))
        (when vertico (vertico-mode -1))
        (use-local-map nil)))
    picked))

;; ====== PICKING ======

(ert-deftest agent-workflow-pick/a-title-with-a-comma-picked-with-ret ()
  "RET on an issue whose title has a comma picks it: the prompt closes (it
only filled the input, never a match, a comma separating several)."
  (should (equal (+test-awk--pick "screenshots RET" t) '("demo-2")))
  (should (equal (+test-awk--pick "empty SPC file RET" t) '("demo-3"))))

(ert-deftest agent-workflow-pick/several-separated-by-what-no-title-has ()
  "Several picked, separated by ; when a title has a comma (the prompt says
so), by a comma when none has; an epic for its open issues."
  (should (equal (+test-awk--pick "crash TAB ; screenshots RET" t) '("demo-3" "demo-2")))
  (should (equal (+test-awk--pick "parser TAB ; release RET" t) '("demo-11" "demo-12" "demo-4")))
  (let ((+test-awk--issues (list (nth 2 +test-awk--issues) (nth 3 +test-awk--issues))))
    (should (equal (+test-awk--pick "crash TAB , release RET" t) '("demo-3" "demo-4"))))
  (should (equal (agent-workflow--separator '("demo-2  a, b" "demo-3  c")) "[ \t]*;[ \t]*"))
  (should (equal (get-text-property 0 'separator (agent-workflow--separator '("a, b; c"))) "|"))
  (should (equal (get-text-property 0 'description (agent-workflow--separator '("a"))) "comma-separated list")))

(ert-deftest agent-workflow-pick/without-vertico ()
  "Emacs's own completion: an issue completed with TAB, RET picks it, a
title with a comma too."
  (should (equal (+test-awk--pick "demo-2 TAB RET") '("demo-2")))
  (should (equal (+test-awk--pick "demo-3 TAB ; demo-2 TAB RET") '("demo-3" "demo-2"))))

(ert-deftest agent-workflow-pick/nothing-picked ()
  "RET on nothing typed, with vertico off: no issue, said."
  (should (equal (+test-awk--pick "RET") '(error "No issue picked"))))

;; ====== THE LOOK ======

(defun +test-awk--affixes ()
  "Each candidate's (NAME PREFIX SUFFIX), as the picker draws them, in its
order."
  (let (seen)
    (+test-awk
      (cl-letf (((symbol-function 'completing-read-multiple)
                 (lambda (_prompt table &rest _)
                   (let* ((names (all-completions "" table))
                          (metadata (completion-metadata "" table nil)))
                     (setq seen (funcall (completion-metadata-get metadata 'affixation-function) names))
                     (list (car names))))))
        (agent-workflow--read-issues "/tmp/")))
    seen))

(defun +test-awk--faces (string)
  "The faces in STRING, flattened (inherited ones too, as given)."
  (let (faces)
    (dotimes (i (length string))
      (let ((face (get-text-property i 'face string)))
        (dolist (face (if (and (listp face) (not (keywordp (car face)))) face (list face)))
          (when face (push face faces)))))
    faces))

(ert-deftest agent-workflow-pick/drawn-as-the-issue-list ()
  "Each issue as the list draws it: its status (blocked by an open issue:
⊘1), its priority (P0 a badge), its type's icon before its id and title (the
ids padded: the titles in a column); its labels as tags after, an epic said;
in bd's order."
  (let ((rows (+test-awk--affixes)))
    (should (equal (mapcar #'car rows)
                   '("demo-1  Parser rewrite"
                     "demo-2  Examples: the screenshots taken again, each as it looks today"
                     "demo-3  Crash on an empty file"
                     "demo-4  Release 2.0")))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 0 rows)))
      (should (string-match-p "\\`○  P1 " (substring-no-properties prefix)))
      (should (string-match-p "(epic: its issues)" suffix))
      (should (string-match-p " parser \\'" suffix))
      (should (+test-awk--faces suffix)))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 1 rows)))
      (should (string-match-p "\\`○  P3 " (substring-no-properties prefix)))
      (should (memq 'shadow (+test-awk--faces prefix)))
      (should (string-match-p " workflow:quick \\'" suffix)))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 2 rows)))
      (should (string-match-p "\\`◔  P0 " (substring-no-properties prefix)))
      (should (memq 'beads-status-in-progress (+test-awk--faces prefix)))
      (should (equal suffix "")))
    (pcase-let ((`(,_ ,prefix ,_) (nth 3 rows)))
      (should (string-match-p "\\`⊘1 P2 " (substring-no-properties prefix)))
      (should (memq 'beads-status-blocked (+test-awk--faces prefix))))))

(ert-deftest agent-workflow-pick/without-the-issue-list ()
  "config/beads/look.el not loaded: no status, priority or type before an
issue; its labels after, muted."
  (cl-letf (((symbol-function '+my/beads-format-status) nil))
    (pcase-let ((`(,_ ,prefix ,suffix) (nth 1 (+test-awk--affixes))))
      (should (equal prefix ""))
      (should (equal (substring-no-properties suffix) "  workflow:quick"))
      (should (memq 'shadow (+test-awk--faces suffix))))))
