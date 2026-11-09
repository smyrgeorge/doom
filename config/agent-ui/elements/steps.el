;;; $DOOMDIR/config/agent-ui/elements/steps.el -*- lexical-binding: t; -*-
;; Agent UI's checklist: steps whose state changes as work goes on. Appending
;; a step whose name is there changes it in its place. Loaded from
;; config/agent-ui/elements.el.
;;
;;   ✓ Run the tests      412 passed
;;   ⠹ Build the release
;;   ○ Publish

(require 'cl-lib)
(require 'subr-x)

(defconst agent-ui-steps--statuses '(pending running done failed skipped))

(defun agent-ui-steps--name (step)
  "STEP's name: STEP itself (a string), or its :name."
  (if (stringp step) step (and (agent-ui--plist-p step) (plist-get step :name))))

(defun agent-ui-steps--normalize (step index)
  "STEP (\"name\", or (:name :status :detail)) as (:name :status :detail),
its status a symbol; an error naming step INDEX if it's wrong."
  (cl-flet ((bad (what) (agent-ui--fail "steps: step %d %s" (1+ index) what)))
    (cond
     ((stringp step) (list :name step :status 'pending :detail nil))
     ((agent-ui--plist-p step)
      (cl-loop for (k _) on step by #'cddr
               unless (memq k '(:name :status :detail))
               do (bad (format "has %s: a step has name, status, detail"
                               (agent-ui--show-value (substring (symbol-name k) 1)))))
      (let ((name (plist-get step :name))
            (status (or (plist-get step :status) "pending"))
            (detail (plist-get step :detail)))
        (unless (stringp name) (bad "has no name"))
        (let ((sym (if (stringp status) (intern-soft status) status)))
          (unless (memq sym agent-ui-steps--statuses)
            (bad (format "has status %s; one of: pending, running, done, failed, skipped"
                         (agent-ui--show-value status))))
          (when (and detail (not (stringp detail)))
            (setq detail (agent-ui-cell detail)))
          (list :name name :status sym :detail detail))))
     (t (bad (format "is %s: a name, or {\"name\": ..., \"status\": ...}"
                     (agent-ui--show-value step)))))))

(defun agent-ui-steps--icon (status ctx)
  (pcase status
    ('done (propertize "✓" 'face 'agent-ui-success))
    ('failed (propertize "✗" 'face 'agent-ui-error))
    ('running (propertize (agent-ui-spinner ctx) 'face 'agent-ui-accent))
    ('skipped (propertize "–" 'face 'agent-ui-muted))
    (_ (propertize "○" 'face 'agent-ui-muted))))

(defun agent-ui-steps--text (props ctx)
  (let* ((steps (plist-get props :steps))
         (shown (seq-take steps agent-ui-max-rows))
         (width (plist-get ctx :width))
         (names (min (apply #'max 0 (mapcar (lambda (s) (string-width (plist-get s :name))) shown))
                     (max 10 (/ width 2)))))
    (if (null steps)
        (propertize "no steps yet" 'face 'agent-ui-muted)
      (concat
       (mapconcat
        (lambda (step)
          (let* ((status (plist-get step :status))
                 (detail (plist-get step :detail))
                 (name (plist-get step :name))
                 (name (if (memq status '(pending skipped))
                           (propertize name 'face 'agent-ui-muted)
                         name)))
            (if (and detail (not (string-empty-p detail)))
                (concat (agent-ui-steps--icon status ctx) " " (agent-ui-pad name names) "  "
                        (propertize (agent-ui-truncate detail (max 0 (- width names 4)))
                                    'face (if (eq status 'failed) 'agent-ui-error 'agent-ui-muted)))
              (concat (agent-ui-steps--icon status ctx) " "
                      (agent-ui-truncate name (- width 2))))))
        shown "\n")
       (when (> (length steps) (length shown))
         (concat "\n" (propertize (format "… %d steps more" (- (length steps) (length shown)))
                                  'face 'agent-ui-muted)))))))

(defun agent-ui-steps--append (element patch)
  "ELEMENT with PATCH's steps: one whose name is there replaces it (its
status and detail changed), the others after."
  (cl-loop for (k _) on patch by #'cddr
           unless (memq k '(:id :steps))
           do (agent-ui--fail "steps: only steps can be appended to"))
  (let ((steps (copy-sequence (plist-get element :steps))))
    (dolist (step (plist-get patch :steps))
      (let* ((name (agent-ui-steps--name step))
             (at (and name (cl-position name steps :key #'agent-ui-steps--name :test #'equal))))
        (if at
            (setf (nth at steps)
                  (if (stringp step)
                      (nth at steps)
                    (let ((old (nth at steps)))
                      (if (stringp old)
                          step
                        (cl-loop for (k v) on step by #'cddr
                                 do (setq old (plist-put (copy-sequence old) k v)))
                        old))))
          (setq steps (append steps (list step))))))
    (plist-put (copy-sequence element) :steps steps)))

(agent-ui-define steps
  "A checklist whose steps change state as work goes on. A step is a name
\(pending), or {\"name\", \"status\", \"detail\"}: status one of pending,
running (a spinner), done, failed, skipped; detail a note after it.
Appending a step whose name is there changes it in its place: append
{\"steps\": [{\"name\": \"Build\", \"status\": \"done\"}]}."
  :props ((steps list "The steps, in order"))
  :example (:title "Release"
            :steps ((:name "Run the tests" :status "done" :detail "412 passed")
                    (:name "Build the release" :status "running")
                    "Publish"))
  :animated (lambda (props)
              (seq-some (lambda (s) (eq (plist-get s :status) 'running)) (plist-get props :steps)))
  :check (lambda (props)
           (plist-put props :steps
                      (cl-loop for step in (plist-get props :steps)
                               for i from 0
                               collect (agent-ui-steps--normalize step i))))
  :append #'agent-ui-steps--append
  :text #'agent-ui-steps--text)
