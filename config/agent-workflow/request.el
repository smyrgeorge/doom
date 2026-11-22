;;; $DOOMDIR/config/agent-workflow/request.el -*- lexical-binding: t; -*-
;; The shell's way in: cmd/agent-workflow. Loaded from
;; config/agent-workflow.el, after check.el. No Doom here.
;;
;; cmd/agent-workflow writes its request in a folder of its own (`request':
;; its operation, then the shell's folder, then its process's id; `payload':
;; JSON) and has Emacs answer it (emacsclient: `agent-workflow-request'), the
;; reply JSON in `reply'.
;;
;;   check {"file": "/abs/feature.yml"} (file: optional) -> {"ok": true
;;        when there's no error (else false, "error": "2 errors"),
;;        "project", "workflows": [names], "profiles": [names], "problems":
;;        [{"level", "file", "line", "message"}...]}: the project's
;;        workflows and profiles, or the one file, read anew (check.el)

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'json)

(defun agent-workflow--request-check (directory payload)
  "Check DIRECTORY's project's workflows and profiles, or PAYLOAD's file:
the reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (agent-workflow-project))
         (file (plist-get payload :file))
         (file (and (stringp file) (not (string-empty-p file)) (expand-file-name file)))
         (problems (progn
                     (when (and file (not (file-exists-p file)))
                       (user-error "check: no file %s" (abbreviate-file-name file)))
                     (agent-workflow-check-problems project file))))
    (append
     (let ((errors (seq-count (lambda (p) (eq (car p) 'error)) problems)))
       (if (> errors 0)
           (list :ok :false :error (format "%d error%s" errors (if (= errors 1) "" "s")))
         (list :ok t)))
     (list :project (if project (directory-file-name project) :null)
           :workflows (vconcat (unless file (mapcar #'car (agent-workflow-workflows project))))
           :profiles (vconcat (unless file (mapcar #'car (agent-workflow-profiles project))))
           :problems (vconcat
                      (mapcar (pcase-lambda (`(,level ,_ ,file ,line ,what))
                                (list :level (symbol-name level) :file file :line line :message what))
                              problems))))))

(defun agent-workflow-request (dir)
  "Answer cmd/agent-workflow's request in DIR (see the top of this file):
its reply written to DIR/reply. Return t."
  (let* ((lines (split-string (with-temp-buffer
                                (insert-file-contents (expand-file-name "request" dir))
                                (buffer-string))
                              "\n"))
         (op (nth 0 lines))
         (directory (nth 1 lines))
         (payload-file (expand-file-name "payload" dir))
         (reply
          (condition-case err
              (let ((payload (when (file-exists-p payload-file)
                               (with-temp-buffer
                                 (let ((coding-system-for-read 'utf-8))
                                   (insert-file-contents payload-file))
                                 (json-parse-buffer :object-type 'plist :null-object nil
                                                    :false-object nil)))))
                (pcase op
                  ("check" (agent-workflow--request-check directory payload))
                  (_ (list :ok :false :error (format "unknown operation %S; operations: check" op)))))
            (json-parse-error (list :ok :false :error (format "not JSON: %s" (error-message-string err))))
            (error (list :ok :false :error (error-message-string err))))))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file (expand-file-name "reply" dir)
        (insert (json-serialize reply) "\n")))
    t))
