;;; $DOOMDIR/config/beads/file.el -*- lexical-binding: t; -*-
;; Filing a bug from code into a project's issues: Agent UI's own bugs
;; (config/agent-ui.el), from any session, into this config's. Loaded from
;; config/beads.el.
;;
;; The issues are found from a folder (the code's), never from the session's
;; directory, and bd runs there without the session's BEADS_DIR / BEADS_DB
;; (they may name another project's). A similar open bug (its title's words
;; mostly the same, of the same labels) gets the report added to its notes
;; instead of a duplicate. Never bd init, never a sync or push: the issues
;; stay where they are.

(defconst +my/beads--title-noise
  '("a" "an" "the" "is" "are" "its" "it" "of" "in" "on" "to" "and" "or" "s" "when" "with")
  "Words two titles may share without looking the same.")

(defun +my/beads--title-words (title)
  "TITLE's words that tell it apart: its lead (\"Agent UI: \"), case and
small words aside."
  (seq-uniq (seq-remove (lambda (word) (member word +my/beads--title-noise))
                        (split-string (downcase (replace-regexp-in-string "\\`[^:]\\{1,30\\}: " "" title))
                                      "[^[:alnum:]]+" t))))

(defun +my/beads-similar-titles-p (a b)
  "Whether titles A and B look the same: most of their words shared (60%)."
  (let ((wa (+my/beads--title-words a))
        (wb (+my/beads--title-words b)))
    (and wa wb
         (>= (/ (float (length (seq-intersection wa wb))) (length (seq-union wa wb))) 0.6))))

(defun +my/beads--bd (dir input &rest args)
  "bd ARGS run in DIR, INPUT (or nil) on its stdin, without the caller's
BEADS_DIR / BEADS_DB: its output. Failing: an error with its words."
  (let ((default-directory (file-name-as-directory dir))
        (process-environment (seq-remove (lambda (v) (string-match-p "\\`BEADS_\\(?:DIR\\|DB\\)=" v))
                                         process-environment))
        (errors (make-temp-file "bd-errors-")))
    (unwind-protect
        (with-temp-buffer
          (let ((status (if input
                            (progn (insert input)
                                   (apply #'call-process-region (point-min) (point-max) "bd" t
                                          (list t errors) nil args))
                          (apply #'call-process "bd" nil (list t errors) nil args))))
            (unless (eql status 0)
              (error "bd %s failed: %s" (car args)
                     (string-trim (with-temp-buffer (insert-file-contents errors)
                                                    (if (string-blank-p (buffer-string))
                                                        (format "exit %s" status)
                                                      (buffer-string))))))
            (buffer-string)))
      (delete-file errors))))

(cl-defun +my/beads-file-bug (title description &key (from doom-user-dir) labels new)
  "File a bug, TITLE and DESCRIPTION (Markdown), with LABELS, in the issues
found from FROM up (this config's by default). A similar open bug of those
labels: DESCRIPTION added to its notes instead, unless NEW. Returns (:id ID
:new BOOL :dir DIR). Signals an error saying what's missing (no issues set
up, no bd) or bd's words if it fails."
  (let ((dir (locate-dominating-file from ".beads")))
    (unless dir
      (error "no Beads issues (.beads) in %s or above" (abbreviate-file-name from)))
    (unless (executable-find "bd")
      (error "%s" "bd isn't installed"))
    (let* ((open (json-parse-string
                  (apply #'+my/beads--bd dir nil "list" "--status" "open,in_progress,blocked,deferred"
                         "--type" "bug" "--json" "--limit" "0"
                         (when labels (list "--label" (string-join labels ","))))
                  :object-type 'plist :array-type 'list :null-object nil))
           (same (and (not new)
                      (seq-find (lambda (issue) (+my/beads-similar-titles-p title (plist-get issue :title)))
                                open))))
      (if same
          (progn
            (+my/beads--bd dir nil "update" (plist-get same :id) "--append-notes"
                           (format "Reported again, %s: %s\n\n%s" (format-time-string "%F") title description))
            (list :id (plist-get same :id) :new nil :dir dir))
        (let ((output (apply #'+my/beads--bd dir description "create" "--silent" "--type=bug" "--priority=2"
                             (concat "--title=" title) "--body-file" "-"
                             (when labels (list (concat "--labels=" (string-join labels ",")))))))
          ;; --silent: its id alone (its last line, after any warning).
          (list :id (car (last (split-string output "\n" t "[ \t]+"))) :new t :dir dir))))))
