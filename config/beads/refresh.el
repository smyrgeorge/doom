;;; $DOOMDIR/config/beads/refresh.el -*- lexical-binding: t; -*-
;; Issue lists refreshed in the background. Loaded from config/beads.el.

;; IN THE BACKGROUND
;; bd takes ~0.5 s to answer (bd list 0.35 s, bd stats 0.16 s: its database
;; started each time), and beads.el waits for it: Emacs froze that long every
;; 30 s for each open list (beads-autoupdate's timer), shown or not, after
;; each of Claude's bd commands, and for each list after an issue's edit.
;; Those refreshes now ask bd in the background, and redraw the list (or the
;; issue) once its answers came, with beads.el's own code (given them instead
;; of asking bd again). A buffer not shown in a window isn't refreshed: it is
;; when it's shown again. A refresh on its way isn't started again; one the
;; user asks for (gr, an edit in the list) is done as before, waited for, and
;; cancels the one on its way (its answer would be older).
(defvar-local +my/beads--fetching nil
  "This buffer's refresh on its way: (TOKEN . PROCESSES).")

(defvar-local +my/beads--stale nil
  "Non-nil when this buffer wasn't refreshed while not shown.")

(defvar +my/beads--fetched nil
  "While a buffer is redrawn from bd's answers fetched in the background: an
alist ((OPERATION . ANSWER) ...), what beads.el's client then returns.")

(defun +my/beads--cli-root ()
  "Where beads.el runs bd: its database's project, else this folder."
  (or (when-let* ((db (beads-client--find-database)))
        (file-name-directory (directory-file-name (file-name-directory db))))
      default-directory))

(defun +my/beads--answer (process errors)
  "PROCESS's answer, finished: its JSON read as beads.el reads it (a list for
an array), or (:error MESSAGE) with ERRORS, its standard error."
  (with-current-buffer (process-buffer process)
    (let ((code (process-exit-status process)))
      (if (not (and (eq (process-status process) 'exit) (zerop code)))
          (list :error (format "CLI failed with exit code %d: %s" code
                               (string-trim (concat (buffer-string) errors))))
        (goto-char (point-min))
        (condition-case nil
            (let ((output (json-read)))
              (if (vectorp output) (append output nil) output))
          (error (list :error (format "CLI returned invalid JSON: %s" (buffer-string)))))))))

(defun +my/beads--bd-async (operation args callback)
  "bd run for OPERATION with ARGS (an alist), as beads.el's command line runs
it, not waited for: CALLBACK called with its answer (see `+my/beads--answer')
when it ends, unless it was deleted. The process."
  (let* ((backend (beads-backend-for-project))
         (program (beads-backend-cli-program-path backend))
         (flags (append (when-let* ((fn (beads-backend-cli-extra-flags backend)))
                          (funcall fn operation))
                        (funcall (beads-backend-op-to-cli-args backend) operation args)
                        '("--json")))
         (default-directory (+my/beads--cli-root))
         (out (generate-new-buffer " *beads-fetch*" t))
         (err (generate-new-buffer " *beads-fetch-errors*" t))
         (stderr (make-pipe-process :name "beads-fetch-errors" :buffer err :noquery t)))
    (make-process
     :name "beads-fetch" :buffer out :stderr stderr :noquery t
     :connection-type 'pipe
     :command (cons program flags)
     :sentinel (lambda (process _event)
                 (unless (process-live-p process)
                   (unwind-protect
                       (unless (process-get process 'cancelled)
                         (funcall callback (+my/beads--answer
                                            process (with-current-buffer err (buffer-string)))))
                     (delete-process stderr)
                     (kill-buffer out)
                     (kill-buffer err)))))))

(defun +my/beads--cancel (&optional buffer)
  "BUFFER's (else this one's) refresh on its way, cancelled."
  (with-current-buffer (or buffer (current-buffer))
    (when-let* ((fetching +my/beads--fetching))
      (setq +my/beads--fetching nil)
      (dolist (process (cdr fetching))
        (process-put process 'cancelled t)
        (when (process-live-p process)
          (delete-process process))))))

(defun +my/beads--fetch (buffer operations done)
  "bd asked for each of OPERATIONS ((OPERATION . ARGS) ...) in the background,
from BUFFER: DONE called in BUFFER with their answers ((OPERATION . ANSWER)
...) once all came. One failed: said as beads.el says it, the rest dropped."
  (with-current-buffer buffer
    (let ((token (list 'fetch))
          (answers nil))
      (setq +my/beads--fetching
            (cons token
                  (mapcar
                   (lambda (operation)
                     (+my/beads--bd-async
                      (car operation) (cdr operation)
                      (lambda (answer)
                        (when (buffer-live-p buffer)
                          (with-current-buffer buffer
                            ;; Still this buffer's refresh (not cancelled).
                            (when (eq (car +my/beads--fetching) token)
                              (if (eq (car-safe answer) :error)
                                  (progn (+my/beads--cancel)
                                         (message "Failed to fetch issues: %s" (cadr answer)))
                                (push (cons (car operation) answer) answers)
                                (when (= (length answers) (length operations))
                                  (setq +my/beads--fetching nil)
                                  (funcall done answers)))))))))
                   operations))))))

(defun +my/beads--redraw (buffer answers fn &rest args)
  "FN called with ARGS in BUFFER, beads.el's client answering with ANSWERS
(see `+my/beads--fetched'); in its window, if it has one (beads.el keeps
the place of the selected one), and quietly."
  (when (buffer-live-p buffer)
    (let ((+my/beads--fetched answers)
          (inhibit-message (or inhibit-message (not (eq (window-buffer) buffer)))))
      (if-let* ((window (get-buffer-window buffer 'visible)))
          (with-selected-window window
            (apply fn args))
        (with-current-buffer buffer
          (apply fn args))))))

(defun +my/beads-refresh-async (&optional buffer silent)
  "Refresh BUFFER (else this one), an issue list or an issue, in the
background (see above); SILENT, no message."
  (let ((buffer (or buffer (current-buffer))))
    (when (buffer-live-p buffer)
      (with-current-buffer buffer
        (cond ((not (derived-mode-p '(beads-list-mode beads-detail-mode beads-detail-vui-mode))))
              ((not (get-buffer-window buffer 'visible))
               (setq +my/beads--stale t))
              (+my/beads--fetching)    ; on its way
              ((derived-mode-p 'beads-list-mode)
               (setq +my/beads--stale nil)
               (+my/beads--fetch
                buffer
                `(("list") ,@(and beads-list-show-header-stats '(("stats"))))
                (lambda (answers)
                  (+my/beads--redraw buffer answers #'beads-list-refresh silent))))
              (beads-detail--current-issue-id
               (setq +my/beads--stale nil)
               (+my/beads--fetch
                buffer
                `(("show" (id . ,beads-detail--current-issue-id)))
                (lambda (answers)
                  (let ((inhibit-message t))
                    (+my/beads--redraw buffer answers #'beads-detail-refresh))))))))))

;; beads.el's client, answering with what was fetched.
(defun +my/beads--fetched-list-a (fn &rest args)
  "`beads-client-list': what was fetched (see above), else bd's answer."
  (if-let* ((answer (and (null args) (assoc "list" +my/beads--fetched))))
      (cdr answer)
    (apply fn args)))

(defun +my/beads--fetched-stats-a (fn &rest args)
  "`beads-client-stats': what was fetched, its counts at the top (config/beads/bd.el)."
  (if-let* ((answer (assoc "stats" +my/beads--fetched)))
      (+my/beads--stats-summary-a (cdr answer))
    (apply fn args)))

(defun +my/beads--fetched-show-a (fn id &rest args)
  "`beads-client-show' of ID: what was fetched, the issue (not bd 1.x's list of
it, config/beads/bd.el), else bd's answer."
  (if-let* ((answer (cdr (assoc "show" +my/beads--fetched)))
            (issue (+my/beads--one-issue-a answer))
            ((equal (alist-get 'id issue) id)))
      issue
    (apply fn id args)))

(defun +my/beads-cancel-a (&rest _)
  "A refresh waited for (gr, an edit): the one on its way cancelled."
  (unless +my/beads--fetched
    (+my/beads--cancel)))

;; beads.el's timer and its lists after an issue's edit: in the background.
(defun +my/beads-autoupdate-a ()
  "`beads-autoupdate--refresh': in the background (see above)."
  (when (derived-mode-p 'beads-list-mode)
    (+my/beads-refresh-async (current-buffer) (not beads-autoupdate-message))))

(defun +my/beads-refresh-lists-a ()
  "`beads-detail--refresh-list-buffers': each list in the background."
  (dolist (buffer (buffer-list))
    (when (eq (buffer-local-value 'major-mode buffer) 'beads-list-mode)
      (+my/beads-refresh-async buffer t))))

;; Shown again: refreshed, if it missed one.
(defun +my/beads--shown-h (window)
  "WINDOW shows this buffer now: refreshed if it wasn't while hidden."
  (with-current-buffer (window-buffer window)
    (when +my/beads--stale
      (+my/beads-refresh-async (current-buffer) t))))

(defun +my/beads--follow-h ()
  "In an issue list or an issue: refreshed when shown again (if it missed
one), its refresh on its way cancelled when it's killed."
  (add-hook 'window-buffer-change-functions #'+my/beads--shown-h nil t)
  (add-hook 'kill-buffer-hook #'+my/beads--cancel nil t))

(add-hook 'beads-list-mode-hook #'+my/beads--follow-h)
(add-hook 'beads-detail-mode-hook #'+my/beads--follow-h)
(add-hook 'beads-detail-vui-mode-hook #'+my/beads--follow-h)

(after! beads-client
  (advice-add 'beads-client-list :around #'+my/beads--fetched-list-a)
  (advice-add 'beads-client-stats :around #'+my/beads--fetched-stats-a)
  (advice-add 'beads-client-show :around #'+my/beads--fetched-show-a))
(after! beads-list
  (advice-add 'beads-list-refresh :before #'+my/beads-cancel-a))
(after! beads-detail
  (advice-add 'beads-detail-refresh :before #'+my/beads-cancel-a)
  (advice-add 'beads-detail--refresh-list-buffers :override #'+my/beads-refresh-lists-a))
(after! beads-autoupdate
  (advice-add 'beads-autoupdate--refresh :override #'+my/beads-autoupdate-a))
