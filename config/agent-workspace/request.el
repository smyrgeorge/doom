;;; $DOOMDIR/config/agent-workspace/request.el -*- lexical-binding: t; -*-
;; The shell's way in: cmd/agent-workspace. Loaded from
;; config/agent-workspace.el, after new.el. No Doom here.
;;
;; cmd/agent-workspace writes its request in a folder of its own (`request':
;; its operation, then the shell's folder; `payload': JSON) and has Emacs
;; answer it (emacsclient: `agent-workspace-request'), the reply JSON in
;; `reply'. For your scripts: an agent made from the shell.
;;
;;   new  {"role": "builder", "name": "ada", "prompt": "..."}  (name, prompt:
;;        optional) -> {"ok": true, "name", "role", "worktree", "branch",
;;        "state"}

(require 'cl-lib)
(require 'subr-x)
(require 'json)

(defun agent-workspace--request-new (directory payload)
  "Make an agent in DIRECTORY's project, as PAYLOAD (a plist) says: the
reply, a plist."
  (let* ((default-directory (file-name-as-directory directory))
         (project (or (agent-workspace-project)
                      (user-error "No crew here: %s" (agent-workspace-no-crew-reason))))
         (role (plist-get payload :role))
         (name (plist-get payload :name))
         (prompt (plist-get payload :prompt)))
    (unless (stringp role)
      (user-error "new: which role? --role ROLE"))
    (let ((agent (agent-workspace-create
                  :project project :role role
                  :name (if (and (stringp name) (not (string-empty-p name)))
                            name
                          (agent-workspace-pool-name project role))
                  :prompt (and (stringp prompt) (not (string-empty-p prompt)) prompt))))
      (list :ok t
            :name (agent-workspace-agent-name agent)
            :role (agent-workspace-agent-role agent)
            :worktree (directory-file-name (agent-workspace-agent-worktree agent))
            :branch (agent-workspace-agent-branch agent)
            :state (symbol-name (agent-workspace-agent-state agent))))))

(defun agent-workspace-request (dir)
  "Answer cmd/agent-workspace's request in DIR (see the top of this file):
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
                  ("new" (agent-workspace--request-new directory payload))
                  (_ (list :ok :false :error (format "unknown operation %S; operations: new" op)))))
            (json-parse-error (list :ok :false :error (format "not JSON: %s" (error-message-string err))))
            (error (list :ok :false :error (error-message-string err))))))
    (let ((coding-system-for-write 'utf-8-unix))
      (with-temp-file (expand-file-name "reply" dir)
        (insert (json-serialize reply) "\n")))
    t))
