;;; $DOOMDIR/examples/issues.el -*- lexical-binding: t; -*-
;; Example: a project's issues (config/beads.el, docs/issues.md). M-x
;; +my/example-issues starts tracking a small compiler's issues with bd in the
;; temp folder, and opens their list as SPC o i does: its statuses, priorities
;; and types as icons and badges, an epic's issues under it with its progress,
;; labels as tags, one issue blocked by a bug, the closed ones hidden (a notice
;; says how many). The folder is deleted once the list is closed. Needs bd.

;; ====== CODE ======

(defconst +my/example-issues--issues
  ;; (ID TITLE TYPE PRIORITY STATUS LABELS PARENT BLOCKED-BY)
  '(("demo-1"   "Parser rewrite"                        "epic"    1 "open"        ("parser"))
    ("demo-1.1" "Lexer: tokens with their positions"    "task"    2 "closed"      nil "demo-1")
    ("demo-1.2" "Parser: recover from syntax errors"    "feature" 1 "in_progress" nil "demo-1")
    ("demo-1.3" "Parser: precedence climbing"           "task"    2 "open"        nil "demo-1")
    ("demo-1.4" "Remove the old recursive parser"       "chore"   3 "open"        nil "demo-1")
    ("demo-2"   "Language server"                       "epic"    2 "open"        ("lsp"))
    ("demo-2.1" "Diagnostics as you type"               "feature" 2 "open"        nil "demo-2")
    ("demo-2.2" "Go to definition"                      "feature" 2 "closed"      nil "demo-2")
    ("demo-3"   "Crash on an empty file"                "bug"     0 "open"        ("crash" "parser"))
    ("demo-4"   "Error messages give the wrong line"    "bug"     1 "in_progress" ("errors"))
    ("demo-5"   "Release 2.0"                           "task"    2 "open"        nil nil "demo-3")
    ("demo-6"   "Formatter: keep comments in place"     "feature" 2 "open"        ("fmt"))
    ("demo-7"   "Typo in --help"                        "bug"     3 "open"        ("docs"))
    ("demo-8"   "Update the CI images"                  "chore"   4 "open"        nil)
    ("demo-9"   "Benchmark the lexer"                   "task"    2 "closed"      nil))
  "The example's issues (see above).")

(defun +my/example-issues--jsonl ()
  "The example's issues as bd imports them: a line of JSON each."
  (mapconcat
   (lambda (issue)
     (seq-let (id title type priority status labels parent blocker) issue
      (json-encode
      `((id . ,id) (title . ,title) (issue_type . ,type) (priority . ,priority) (status . ,status)
        (created_at . "2026-11-02T09:00:00Z") (updated_at . "2026-11-02T09:00:00Z")
        ,@(and (equal status "closed") '((closed_at . "2026-11-03T09:00:00Z")))
        ,@(and labels `((labels . ,(vconcat labels))))
        ,@(and (or parent blocker)
               `((dependencies
                  . ,(vconcat
                      (delq nil
                            (list (and parent `((issue_id . ,id) (depends_on_id . ,parent) (type . "parent-child")))
                                  (and blocker `((issue_id . ,id) (depends_on_id . ,blocker) (type . "blocks")))))))))))))
   +my/example-issues--issues "\n"))

(defun +my/example-issues--bd (&rest args)
  "bd run with ARGS in this folder; an error saying why if it failed."
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "bd" nil t nil args))
      (error "bd %s: %s" (string-join args " ") (string-trim (buffer-string))))))

(defun +my/example-issues ()
  "Example: a project's issues in their list (its folder deleted once the
list is closed). See examples/issues.el."
  (interactive)
  (unless (executable-find "bd")
    (user-error "The issues example needs bd (scripts/tools.sh installs it)"))
  (let* ((dir (+my/example-folder "issues"))
         (default-directory dir)
         (issues (make-temp-file "issues-example-" nil ".jsonl" (+my/example-issues--jsonl))))
    (unwind-protect
        (progn
          (+my/example-issues--bd "init" "--quiet" "--skip-agents" "--prefix" "demo")
          (+my/example-issues--bd "import" issues "--quiet"))
      (delete-file issues))
    (delete-other-windows)
    ;; As SPC o i: the list in its pane, alone in the frame.
    (cl-letf (((symbol-function 'doom-project-root) (lambda (&rest _) dir)))
      (+my/beads-project))
    (delete-other-windows)
    (+my/example-delete-when-closed dir (list (current-buffer)))
    (message "Issues example: RET opens one, Show closed shows the closed ones")
    (current-buffer)))

(provide 'example-issues)
