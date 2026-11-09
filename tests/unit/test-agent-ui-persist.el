;;; tests/unit/test-agent-ui-persist.el -*- lexical-binding: t; -*-
;; config/agent-ui/persist.el: a session's canvas kept with it. Saved as it
;; changes (a moment later, together), by its session id, in its directory;
;; closing it changes nothing saved, clearing it saves it empty; back when the
;; session starts with that id, its sources not started again. Sessions are
;; buffers the tests make, their ids stubbed; no agent runs.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defvar +test-aup-ids nil "Session buffers' ids: (BUFFER . ID).")
(defvar +test-aup-dir nil "The test session's directory.")

(defmacro +test-aup (&rest body)
  "BODY with a session `session' (its id \"sess-1\", working in `dir'), no
window shown, saves at once; what it makes, killed after."
  (declare (indent 0))
  `(let* ((+test-aup-dir (file-name-as-directory (make-temp-file (+test-tmp-file "persist-") t)))
          (dir +test-aup-dir)
          (agent-ui-display-function #'ignore)
          (agent-ui-persist-delay 0.01)
          (session (generate-new-buffer "Claude Agent @ persist"))
          (+test-aup-ids (list (cons session "sess-1")))
          (before (buffer-list)))
     (with-current-buffer session (setq default-directory dir))
     (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () (list session)))
               ((symbol-function 'agent-shell-cwd) (lambda () default-directory))
               ((symbol-function 'agent-shell-session-id)
                (lambda (&key shell-buffer) (cdr (assq shell-buffer +test-aup-ids)))))
       (unwind-protect (let ((name (agent-ui--session-name session))) (ignore name) ,@body)
         (dolist (b (buffer-list))
           (unless (memq b before) (kill-buffer b)))
         (kill-buffer session)))))

(defun +test-aup-file () (expand-file-name ".agent-shell/agent-ui/sess-1.json" +test-aup-dir))

(defun +test-aup-saved ()
  "What's saved, parsed (nil if nothing)."
  (with-timeout (2 nil)
    (while (not (file-exists-p (+test-aup-file)))
      (accept-process-output nil 0.01)))
  (when (file-exists-p (+test-aup-file))
    (agent-ui-parse-json (with-temp-buffer (insert-file-contents (+test-aup-file)) (buffer-string)))))

(defun +test-aup-settle ()
  "Wait past the save's delay."
  (let ((end (+ (float-time) 0.1)))
    (while (< (float-time) end) (accept-process-output nil 0.01))))

;; ====== SAVING ======

(ert-deftest agent-ui-persist/saved-as-it-changes ()
  (+test-aup
    (should (equal (agent-ui-persist-file session) (+test-aup-file)))
    (agent-ui-show '(:id "b" :type "progress" :max 4 :title "Build") :canvas name)
    (agent-ui-update "b" '(:value 3) :canvas name)
    (should (equal (+test-aup-saved) '((:id "b" :type "progress" :max 4 :title "Build" :value 3))))
    (agent-ui-show '(:id "t" :type "text" :text "ü ✓") :canvas name)
    (agent-ui-remove "b" :canvas name)
    (+test-aup-settle)
    (should (equal (+test-aup-saved) '((:id "t" :type "text" :text "ü ✓"))))))

(ert-deftest agent-ui-persist/closing-keeps-it ()
  (+test-aup
    (agent-ui-show '(:id "t" :type "text" :text "kept") :canvas name)
    (+test-aup-saved)
    ;; A change waiting when it closes: saved then; nothing emptied.
    (agent-ui-update "t" '(:text "last") :canvas name)
    (kill-buffer (agent-ui-canvas-buffer-name name))
    (should (equal (+test-aup-saved) '((:id "t" :type "text" :text "last"))))
    ;; Cleared: empty, saved.
    (agent-ui-show '(:id "x" :type "text" :text "x") :canvas name)
    (agent-ui-clear :canvas name)
    (+test-aup-settle)
    (should (equal (+test-aup-saved) nil))
    (should (file-exists-p (+test-aup-file)))))

(ert-deftest agent-ui-persist/not-without-a-session-id ()
  (+test-aup
    (setq +test-aup-ids nil)
    (agent-ui-show '(:id "t" :type "text" :text "x") :canvas name)
    (+test-aup-settle)
    (should-not (file-exists-p (+test-aup-file)))
    ;; A canvas of no session: neither.
    (let ((agent-ui-default-canvas (make-temp-name "nobody-")))
      (agent-ui-show '(:id "t" :type "text" :text "x"))
      (+test-aup-settle)
      (should-not (file-exists-p (expand-file-name ".agent-shell/agent-ui/" dir))))))

;; ====== RESTORING ======

(ert-deftest agent-ui-persist/back-when-resumed ()
  (+test-aup
    (make-directory (file-name-directory (+test-aup-file)) t)
    (with-temp-file (+test-aup-file)
      (insert "[{\"id\":\"b\",\"type\":\"progress\",\"max\":4,\"value\":4,\"status\":\"done\"},"
              "{\"id\":\"s\",\"type\":\"text\",\"text\":\"tail\",\"source\":{\"command\":\"echo again\",\"tail\":1}},"
              "{\"id\":\"g\",\"type\":\"gone-type\"}]"))
    (should (= (agent-ui-persist-restore session) 2))
    ;; As they were; the one of a type gone, left out; no source started.
    (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas name)) '("b" "s")))
    (should (equal (plist-get (agent-ui-get "b" :canvas name) :status) "done"))
    (should-not (plist-get (agent-ui-get "s" :canvas name) :source))
    (should-not (agent-ui-source-status "s" :canvas name))
    ;; Tied to its session, as any.
    (should (eq (buffer-local-value 'agent-ui--session-buffer (get-buffer (agent-ui-canvas-buffer-name name)))
                session))
    ;; A canvas with elements already: left as it is.
    (should-not (agent-ui-persist-restore session))))

(ert-deftest agent-ui-persist/nothing-kept-nothing-back ()
  (+test-aup
    (should-not (agent-ui-persist-restore session))
    (should-not (get-buffer (agent-ui-canvas-buffer-name name)))
    ;; Unreadable: nothing, no error.
    (make-directory (file-name-directory (+test-aup-file)) t)
    (with-temp-file (+test-aup-file) (insert "{not json"))
    (should (equal (agent-ui-persist-restore session) 0))))

(ert-deftest agent-ui-persist/when-a-session-starts ()
  (+test-aup
    (should (memq #'agent-ui--persist-watch agent-shell-mode-hook))
    (let (subscribed)
      (cl-letf (((symbol-function 'agent-shell-subscribe-to)
                 (lambda (&rest args) (setq subscribed args))))
        (with-current-buffer session (agent-ui--persist-watch)))
      (should (eq (plist-get subscribed :shell-buffer) session))
      (should (eq (plist-get subscribed :event) 'init-session))
      ;; Its session known: its canvas back.
      (make-directory (file-name-directory (+test-aup-file)) t)
      (with-temp-file (+test-aup-file) (insert "[{\"id\":\"t\",\"type\":\"text\",\"text\":\"back\"}]"))
      (funcall (plist-get subscribed :on-event) '((:event . init-session)))
      (should (equal (plist-get (agent-ui-get "t" :canvas name) :text) "back")))))
