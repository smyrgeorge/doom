;;; $DOOMDIR/config/agent-workflow/list.el -*- lexical-binding: t; -*-
;; Every run of a project, a list: M-x agent-workflow-list. Loaded from
;; config/agent-workflow.el, after pane-boxes.el. No Doom here (its keys are in
;; config/agent-workflow.el).
;;
;; A line per run, those not over first, then the latest: its issue, which
;; run of it, its workflow, its state, how long it ran, what it spent, what
;; it waits for or which jobs work. Those this Emacs runs (started from here
;; or the shell), and those over, read from their folders. RET opens a run's
;; pane (made if it has none: pane.el); g reads them again; it follows the
;; runs as they change.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'tabulated-list)

(defvar-keymap agent-workflow-list-mode-map
  :doc "Keys of the runs' list."
  :parent tabulated-list-mode-map
  "RET" #'agent-workflow-list-open)

(defvar-local agent-workflow--list-project nil "In the runs' list: its project.")

(defvar agent-workflow--read-runs (make-hash-table :test #'equal)
  "Runs over read from their folders, by folder: read once, the pane kept.")

(define-derived-mode agent-workflow-list-mode tabulated-list-mode "Workflow runs"
  "A project's runs of its workflows: RET opens one's pane.

\\{agent-workflow-list-mode-map}"
  (setq tabulated-list-format [("Issue" 14 t) ("#" 3 t :right-align t) ("Workflow" 10 t) ("State" 10 t)
                               ("Time" 8 nil :right-align t) ("Spent" 8 nil :right-align t) ("What" 0 nil)]
        tabulated-list-padding 1
        tabulated-list-sort-key nil)
  (tabulated-list-init-header)
  (add-hook 'tabulated-list-revert-hook #'agent-workflow--list-entries nil t))

(defun agent-workflow-project-runs (project)
  "PROJECT's runs: this Emacs's, and those over read from their folders,
those not over first, then the latest."
  (let* ((live (agent-workflow-runs-of project))
         (dirs (mapcar (lambda (run) (file-name-as-directory (agent-workflow-run-dir run))) live))
         (root (agent-workflow--runs-directory project))
         (read (when (file-directory-p root)
                 (delq nil
                       (mapcar (lambda (dir)
                                 (let ((dir (file-name-as-directory dir)))
                                   (unless (member dir dirs)
                                     (or (gethash dir agent-workflow--read-runs)
                                         (when-let* ((run (ignore-errors (agent-workflow--read-run dir))))
                                           (puthash dir run agent-workflow--read-runs))))))
                               (file-expand-wildcards (expand-file-name "*/*/" root)))))))
    (sort (append live read)
          (lambda (a b)
            (let ((over-a (memq (agent-workflow-run-state a) agent-workflow--ended))
                  (over-b (memq (agent-workflow-run-state b) agent-workflow--ended)))
              (if (eq (and over-a t) (and over-b t))
                  (time-less-p (agent-workflow--run-touched b) (agent-workflow--run-touched a))
                (not over-a)))))))

(defun agent-workflow--run-touched (run)
  "When RUN last changed: its journal's time."
  (or (file-attribute-modification-time
       (file-attributes (expand-file-name "journal.jsonl" (agent-workflow-run-dir run))))
      0))

(defun agent-workflow--list-what (run)
  "What RUN waits for, or which of its jobs work."
  (pcase (agent-workflow-run-state run)
    ((or 'waiting 'queued) (or (agent-workflow-run-why run) ""))
    ('running (let ((working (mapcar #'car (agent-workflow--status-of run 'running))))
                (if working (concat (string-join working ", ") " working") "")))
    ('done "every job done")
    (_ "")))

(defun agent-workflow--list-entries ()
  "The runs' list's lines."
  (setq tabulated-list-entries
        (mapcar (lambda (run)
                  (let ((spent (agent-workflow-run-spent-now run))
                        (state (agent-workflow-run-state run)))
                    (list run
                          (vector (if (agent-workflow-run-ticket-p run)
                                      (agent-workflow-run-issue run)
                                    (propertize "–" 'face 'shadow))
                                  (number-to-string (agent-workflow-run-n run))
                                  (or (plist-get (agent-workflow-run-workflow run) :name) "")
                                  (propertize (symbol-name state)
                                              'face (pcase state
                                                      ('waiting 'warning) ('done 'success)
                                                      ('cancelled 'shadow) ('failed 'error) (_ 'default)))
                                  (agent-workflow--duration-words (plist-get spent :time))
                                  (if (> (plist-get spent :cost) 0) (format "$%.2f" (plist-get spent :cost)) "")
                                  (agent-workflow--list-what run)))))
                (agent-workflow-project-runs agent-workflow--list-project))))

(defun agent-workflow-list (&optional project)
  "Every run of PROJECT (default: the current one's), a list: RET opens a
run's pane."
  (interactive)
  (let* ((project (or project (agent-workflow-project) (user-error "Not in a git repository")))
         (buffer (get-buffer-create (format "*agent-workflow runs: %s*"
                                            (file-name-nondirectory (directory-file-name project))))))
    (agent-workflow--ensure-restored project)
    (with-current-buffer buffer
      (unless (derived-mode-p 'agent-workflow-list-mode)
        (agent-workflow-list-mode))
      (setq agent-workflow--list-project project
            default-directory project)
      (revert-buffer))
    (pop-to-buffer buffer)))

(defun agent-workflow-list-open ()
  "Open the pane of the run on this line, selected."
  (interactive)
  (let ((run (or (tabulated-list-get-id) (user-error "No run on this line"))))
    (agent-workflow-pane run 'select)))

(defvar agent-workflow--list-timer nil "The runs' lists read again, soon.")

(defun agent-workflow--list-changed (_run)
  "A run changed: the runs' lists shown read again, soon. In
`agent-workflow-run-functions'."
  (unless (timerp agent-workflow--list-timer)
    (setq agent-workflow--list-timer
          (run-with-timer 0.5 nil
                          (lambda ()
                            (setq agent-workflow--list-timer nil)
                            (dolist (buffer (buffer-list))
                              (when (and (eq (buffer-local-value 'major-mode buffer) 'agent-workflow-list-mode)
                                         (get-buffer-window buffer t))
                                (with-current-buffer buffer
                                  (with-demoted-errors "agent workflow runs: %S"
                                    (revert-buffer))))))))))

(add-hook 'agent-workflow-run-functions #'agent-workflow--list-changed)
