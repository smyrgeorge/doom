;;; tests/unit/test-notify.el -*- lexical-binding: t; -*-
;; config/notify.el: desktop notifications while Emacs isn't in front. Kinds
;; defined and fired, only when on and Emacs isn't in front (each frame's
;; focus: in front, away, not known), a click bringing Emacs forward on the
;; buffer, the toggles (SPC t n, SPC t N), the test notification; and Claude
;; Code's (config/notify/claude.el): agent-shell's events, stood in for. What
;; the desktop would show is recorded (`+my/os-notify' here, config/os.el's
;; own posting in tests/helper.el).

(+test-load "config/notify")
;; Agent UI's questions: the notification reads them from their canvas.
(+test-load "config/agent-ui")

;; config/agent-shell.el's (what Claude Code is told about Emacs), not loaded
;; here: special, a test binds it.
(defvar +my/agent-shell-claude-context)

;; ====== HELPERS ======

(defvar +test-notify--shown nil
  "What `+my/os-notify' was asked to show, (TITLE BODY ON-CLICK), latest first.")

(defmacro +test-notify (focus &rest body)
  "BODY with every frame's focus FOCUS (t, nil, unknown), notifications on,
none off, what's shown recorded in `+test-notify--shown'."
  (declare (indent 1))
  `(let ((+test-notify--shown nil)
         (+my/notify-enabled t)
         (+my/notify-off nil)
         (+my/notify-kinds (copy-sequence +my/notify-kinds)))
     (cl-letf (((symbol-function 'frame-focus-state) (lambda (&rest _) ,focus))
               ((symbol-function 'frame-initial-p) #'ignore)
               ((symbol-function '+my/os-notify)
                (lambda (title body &optional on-click)
                  (push (list title body on-click) +test-notify--shown)
                  t)))
       ,@body)))

;; ====== SETTINGS, KEYS ======

(ert-deftest notify/settings ()
  (should (eq (default-value '+my/notify-enabled) t))
  (should-not (default-value '+my/notify-off))
  ;; Claude Code's, Agent UI's, so far.
  (should (equal (mapcar #'car +my/notify-kinds)
                 '(agent-ui-question agent-ui-bug claude-question claude-permission claude-turn-done claude))))

(ert-deftest notify/keys ()
  (should (eq (lookup-key doom-leader-map (kbd "t n")) #'+my/notify-toggle))
  (should (eq (lookup-key doom-leader-map (kbd "t N")) #'+my/notify-toggle-kind))
  (dolist (command '(+my/notify-toggle +my/notify-toggle-kind +my/notify-test))
    (should (commandp command))))

;; ====== KINDS ======

(ert-deftest notify/a-kind-defined ()
  (+test-notify nil
    (+my/notify-define 'test-kind "Title" "Something happened")
    (should (equal (alist-get 'test-kind +my/notify-kinds) '("Title" "Something happened")))
    ;; Again: replaced.
    (+my/notify-define 'test-kind "Other" "Else")
    (should (equal (alist-get 'test-kind +my/notify-kinds) '("Other" "Else")))
    (should (= (seq-count (lambda (e) (eq (car e) 'test-kind)) +my/notify-kinds) 1))))

(ert-deftest notify/on-when-all-and-its-kind-are ()
  (+test-notify nil
    (+my/notify-define 'test-kind "Title" "Something")
    (should (+my/notify-on-p 'test-kind))
    (let ((+my/notify-off '(test-kind)))
      (should-not (+my/notify-on-p 'test-kind)))
    (let ((+my/notify-enabled nil))
      (should-not (+my/notify-on-p 'test-kind)))
    ;; Not defined.
    (should-not (+my/notify-on-p 'no-such-kind))))

;; ====== EMACS IN FRONT ======

(ert-deftest notify/emacs-in-front ()
  "A frame with the focus: in front. None: away. Not known (a terminal that
doesn't say): in front (nothing shown). The daemon's first frame: not
counted."
  (+test-notify t (should (+my/notify-emacs-in-front-p)))
  (+test-notify nil (should-not (+my/notify-emacs-in-front-p)))
  (+test-notify 'unknown (should (+my/notify-emacs-in-front-p)))
  (+test-notify 'unknown
    (cl-letf (((symbol-function 'frame-initial-p) (lambda (&rest _) t)))
      (should-not (+my/notify-emacs-in-front-p)))))

;; ====== FIRING ======

(ert-deftest notify/shown-while-emacs-is-away ()
  "Emacs away: shown, under its kind's title; in front: not."
  (+test-notify nil
    (+my/notify-define 'test-kind "Title" "Something")
    (should (+my/notify 'test-kind "It happened"))
    (should (equal (mapcar #'butlast +test-notify--shown) '(("Title" "It happened"))))
    ;; No buffer: nothing to click to.
    (should-not (nth 2 (car +test-notify--shown))))
  (+test-notify t
    (+my/notify-define 'test-kind "Title" "Something")
    (should-not (+my/notify 'test-kind "It happened"))
    (should-not +test-notify--shown)))

(ert-deftest notify/not-shown-when-off ()
  (+test-notify nil
    (+my/notify-define 'test-kind "Title" "Something")
    (let ((+my/notify-enabled nil))
      (should-not (+my/notify 'test-kind "x")))
    (let ((+my/notify-off '(test-kind)))
      (should-not (+my/notify 'test-kind "x")))
    (should-not (+my/notify 'no-such-kind "x"))
    (should-not +test-notify--shown)))

(ert-deftest notify/a-click-shows-its-buffer ()
  "Clicked: Emacs forward, on the buffer (its window if it has one)."
  (+test-with-reset
    (+test-notify nil
      (+my/notify-define 'test-kind "Title" "Something")
      (let ((buffer (+test-buffer "about")))
        (+my/notify 'test-kind "It happened" :buffer buffer)
        (cl-letf (((symbol-function 'select-frame-set-input-focus) #'ignore))
          (funcall (nth 2 (car +test-notify--shown)))
          (should (eq (window-buffer (selected-window)) buffer))
          ;; Shown already elsewhere: that window.
          (let ((other (split-window-right)))
            (set-window-buffer other buffer)
            (switch-to-buffer "*scratch*")
            (funcall (nth 2 (car +test-notify--shown)))
            (should (eq (selected-window) other)))
          ;; Gone: Emacs forward all the same.
          (kill-buffer buffer)
          (funcall (nth 2 (car +test-notify--shown))))))))

(ert-deftest notify/the-test-one-in-front-too ()
  "M-x +my/notify-test: shown even with Emacs in front."
  (+test-notify t
    (+test-clear-messages)
    (+my/notify-test)
    (should (equal (car (car +test-notify--shown)) "Emacs"))
    (should (= (+test-messages "^Sent a notification") 1))))

;; ====== ON AND OFF ======

(ert-deftest notify/toggle-all ()
  (+test-notify nil
    (+test-clear-messages)
    (+my/notify-toggle)
    (should-not +my/notify-enabled)
    (+my/notify-toggle)
    (should +my/notify-enabled)
    (should (= (+test-messages "^Notifications off$") 1))
    (should (= (+test-messages "^Notifications on$") 1))))

(ert-deftest notify/toggle-a-kind ()
  "SPC t N: each kind by what it's about, on or off; picked, turned over."
  (+test-notify nil
    (let ((+my/notify-kinds nil))
      (+my/notify-define 'first "Title" "The first")
      (+my/notify-define 'second "Title" "The second")
      (let (offered)
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt collection &rest _)
                     (setq offered (mapcar #'car collection))
                     (car (seq-find (lambda (c) (eq (cdr c) 'second)) collection)))))
          (call-interactively #'+my/notify-toggle-kind)
          (should (equal offered '("The first (on, first)" "The second (on, second)")))
          (should (equal +my/notify-off '(second)))
          (call-interactively #'+my/notify-toggle-kind)
          (should (equal (cadr offered) "The second (off, second)"))
          (should-not +my/notify-off))))
    (let ((+my/notify-kinds nil))
      (should-error (call-interactively #'+my/notify-toggle-kind) :type 'user-error))))

;; ====== CLAUDE CODE ======

(defmacro +test-notify--session (name &rest body)
  "BODY in a stand-in Claude Code session in project NAME, its
subscriptions recorded in `subscribed' ((EVENT . FUNCTION)...)."
  (declare (indent 1))
  `(let ((subscribed nil)
         (session (generate-new-buffer "*claude-code @ test*")))
     (unwind-protect
         (cl-letf (((symbol-function 'agent-shell-subscribe-to)
                    (lambda (&rest args)
                      (push (cons (plist-get args :event) (plist-get args :on-event)) subscribed)))
                   ((symbol-function 'agent-shell-cwd)
                    (lambda () (concat "/home/me/dev/" ,name "/"))))
           (with-current-buffer session
             (+my/notify-claude--watch-h))
           ,@body)
       (kill-buffer session))))

(ert-deftest notify/claude-kinds-and-hook ()
  (should (equal (alist-get 'claude-turn-done +my/notify-kinds)
                 '("Claude Code" "A session finished its turn")))
  (should (equal (alist-get 'claude-permission +my/notify-kinds)
                 '("Claude Code" "A session asks for your permission")))
  (should (memq #'+my/notify-claude--watch-h (default-value 'agent-shell-mode-hook))))

(ert-deftest notify/agent-ui-bug-filed ()
  "A bug filed in Agent UI's own issues (config/notify/agent-ui.el): said while
Emacs is away, a new one or added to a similar open one."
  (should (equal (alist-get 'agent-ui-bug +my/notify-kinds)
                 '("Agent UI" "A bug filed in Agent UI's own issues")))
  (should (memq #'+my/notify-agent-ui--bug-filed (default-value 'agent-ui-bug-filed-functions)))
  (+test-notify nil
    (run-hook-with-args 'agent-ui-bug-filed-functions "doom-abc" "Agent UI: a tile overlaps" t "/lib/")
    (should (equal (butlast (car +test-notify--shown)) '("Agent UI" "Filed doom-abc: Agent UI: a tile overlaps")))
    (+my/notify-agent-ui--bug-filed "doom-abc" "Agent UI: again" nil "/lib/")
    (should (equal (cadr (car +test-notify--shown)) "Added to doom-abc: Agent UI: again")))
  ;; Emacs in front: nothing.
  (+test-notify t
    (+my/notify-agent-ui--bug-filed "doom-abc" "x" t "/lib/")
    (should-not +test-notify--shown)))

(ert-deftest notify/claude-finished-its-turn ()
  "A session's turn complete: named by its project, why it stopped; a click
shows the session."
  (+test-notify nil
    (+test-notify--session "doom"
      (let ((done (alist-get 'turn-complete subscribed)))
        (should done)
        (pcase-dolist (`(,reason . ,text)
                       '(("end_turn" . "doom: finished") (nil . "doom: finished")
                         ("max_tokens" . "doom: stopped: the answer was too long")
                         ("refusal" . "doom: stopped: it refused")
                         ("cancelled" . "doom: cancelled")
                         ("odd" . "doom: stopped (odd)")))
          (setq +test-notify--shown nil)
          (funcall done `((:event . turn-complete) (:data (:stop-reason . ,reason))))
          (should (equal (mapcar #'butlast +test-notify--shown) `(("Claude Code" ,text)))))
        (cl-letf (((symbol-function 'select-frame-set-input-focus) #'ignore))
          (funcall (nth 2 (car +test-notify--shown)))
          (should (eq (window-buffer (selected-window)) session)))))))

(ert-deftest notify/claude-asks-for-permission ()
  "A session asking for permission: what for, the tool call's title."
  (+test-notify nil
    (+test-notify--session "rskit"
      (let ((asks (alist-get 'permission-request subscribed)))
        (should asks)
        (funcall asks '((:event . permission-request)
                        (:data (:tool-call (:title . "Run npm test")))))
        (funcall asks '((:event . permission-request) (:data (:tool-call (:title . ""))))))
      (should (equal (mapcar #'butlast +test-notify--shown)
                     '(("Claude Code" "rskit needs your permission")
                       ("Claude Code" "rskit needs your permission: Run npm test")))))))

(ert-deftest notify/claude-asks-a-question ()
  "A session asking you a question in its conversation (agent-shell's
elicitation-request, a form; its turn waits for the answer, no turn-complete
coming): the question, its first line; a click shows the session (doom-4zw)."
  (should (equal (alist-get 'claude-question +my/notify-kinds)
                 '("Claude Code" "A session asks you a question")))
  (+test-notify nil
    (+test-notify--session "rskit"
      (let ((asks (alist-get 'elicitation-request subscribed)))
        (should asks)
        (funcall asks '((:event . elicitation-request)
                        (:data (:request-id . 7) (:message . "  Which approach?\nA or B.  "))))
        (funcall asks '((:event . elicitation-request) (:data (:request-id . 8) (:message))))
        (should (equal (mapcar #'butlast +test-notify--shown)
                       '(("Claude Code" "rskit asks you a question")
                         ("Claude Code" "rskit asks: Which approach?"))))
        (cl-letf (((symbol-function 'select-frame-set-input-focus) #'ignore))
          (funcall (nth 2 (car +test-notify--shown)))
          (should (eq (window-buffer (selected-window)) session))))))
  ;; Emacs in front, or the kind off (SPC t N): nothing.
  (+test-notify t
    (+test-notify--session "rskit"
      (funcall (alist-get 'elicitation-request subscribed) '((:data (:message . "Which?"))))
      (should-not +test-notify--shown)))
  (+test-notify nil
    (let ((+my/notify-off '(claude-question)))
      (+test-notify--session "rskit"
        (funcall (alist-get 'elicitation-request subscribed) '((:data (:message . "Which?"))))
        (should-not +test-notify--shown)))))

(ert-deftest notify/claude-in-front-or-off-nothing ()
  (+test-notify t
    (+test-notify--session "doom"
      (funcall (alist-get 'turn-complete subscribed) '((:data (:stop-reason . "end_turn"))))
      (should-not +test-notify--shown)))
  (+test-notify nil
    (let ((+my/notify-off '(claude-turn-done)))
      (+test-notify--session "doom"
        (funcall (alist-get 'turn-complete subscribed) '((:data (:stop-reason . "end_turn"))))
        (funcall (alist-get 'permission-request subscribed) '((:data (:tool-call (:title . "x")))))
        (should (equal (mapcar #'cadr +test-notify--shown) '("doom needs your permission: x")))))))

(ert-deftest notify/agent-ui-question-waiting ()
  "A session's turn ended with a new question waiting on its canvas
(config/notify/agent-ui.el): said, the question's own words, a click
showing the canvas; said instead of the turn's end, not with it."
  (should (equal (alist-get 'agent-ui-question +my/notify-kinds)
                 '("Agent UI" "A question waits for you on a canvas")))
  (should (memq #'+my/notify-agent-ui--question (default-value 'agent-ui-question-waiting-functions)))
  (should (memq #'+my/notify-agent-ui--question-said-p (default-value '+my/notify-claude-turn-said-functions)))
  (let* ((agent-ui-display-function #'ignore)
         ;; A canvas of its own, not the default one.
         (name (make-temp-name "notify-"))
         (canvas (progn (agent-ui-show '(:id "fix" :type "choice" :question "Which fix?" :options ("a" "b"))
                                       :canvas name)
                        (get-buffer (agent-ui-canvas-buffer-name name))))
         (new nil))
    (unwind-protect
        (cl-letf (((symbol-function 'agent-ui-questions-new) (lambda (_session _event) new)))
          (+test-notify nil
            (+test-notify--session "doom"
              (+my/notify-agent-ui--question session canvas "fix")
              (should (equal (butlast (car +test-notify--shown))
                             (list "Agent UI" (format "%s asks: Which fix?" (buffer-name session)))))
              (cl-letf (((symbol-function 'select-frame-set-input-focus) #'ignore))
                (funcall (nth 2 (car +test-notify--shown)))
                (should (eq (window-buffer (selected-window)) canvas)))
              ;; The turn's end: a new question, not said as finished.
              (setq +test-notify--shown nil new (list (cons canvas "fix")))
              (funcall (alist-get 'turn-complete subscribed) '((:data (:stop-reason . "end_turn"))))
              (should-not +test-notify--shown)
              ;; None new: finished, as ever.
              (setq new nil)
              (funcall (alist-get 'turn-complete subscribed) '((:data (:stop-reason . "end_turn"))))
              (should (equal (mapcar #'cadr +test-notify--shown) '("doom: finished")))
              ;; The question's kind off: the turn's end said.
              (let ((+my/notify-off '(agent-ui-question)))
                (setq +test-notify--shown nil new (list (cons canvas "fix")))
                (funcall (alist-get 'turn-complete subscribed) '((:data (:stop-reason . "end_turn"))))
                (should (equal (mapcar #'cadr +test-notify--shown) '("doom: finished"))))))
          ;; Emacs in front: nothing.
          (+test-notify t
            (+my/notify-agent-ui--question nil canvas "fix")
            (should-not +test-notify--shown)))
      (kill-buffer canvas))))

;; ====== A MESSAGE FROM CLAUDE CODE ======

(defvar-local +test-notify--cwd nil "A stand-in session's working directory.")

(defmacro +test-notify--sessions (dirs &rest body)
  "BODY with a stand-in Claude Code session working in each of DIRS,
`sessions' their buffers in that order."
  (declare (indent 1))
  `(let ((sessions (mapcar (lambda (dir)
                             (with-current-buffer (generate-new-buffer "*claude-code @ test*")
                               (setq-local major-mode 'agent-shell-mode
                                           +test-notify--cwd dir)
                               (current-buffer)))
                           ,dirs)))
     (unwind-protect
         (cl-letf (((symbol-function 'agent-shell-cwd) (lambda () +test-notify--cwd)))
           ,@body)
       (mapc #'kill-buffer sessions))))

(ert-deftest notify/claude-s-message-in-its-words ()
  "The caller's message, named by the session's project; a click shows that
session (the one working in the directory given)."
  (+test-with-reset
    (+test-notify nil
      (+test-notify--sessions (list (+test-tmp-file "dev/doom/") (+test-tmp-file "dev/rskit/"))
        (mapc (lambda (dir) (make-directory dir t)) (list (+test-tmp-file "dev/doom/") (+test-tmp-file "dev/rskit/")))
        (should (+my/notify-claude "The tests pass" (+test-tmp-file "dev/rskit")))
        (should (equal (mapcar #'butlast +test-notify--shown) '(("Claude Code" "rskit: The tests pass"))))
        (cl-letf (((symbol-function 'select-frame-set-input-focus) #'ignore))
          (funcall (nth 2 (car +test-notify--shown)))
          (should (eq (window-buffer (selected-window)) (nth 1 sessions))))))))

(ert-deftest notify/claude-s-message-without-a-session ()
  "A directory no session works in: named by its folder, nothing to show on
a click; no directory: the message alone."
  (+test-notify nil
    (+my/notify-claude "Deployed" "/home/me/dev/pas-workspace/")
    (+my/notify-claude "Hello")
    (should (equal (mapcar #'butlast +test-notify--shown)
                   '(("Claude Code" "Hello") ("Claude Code" "pas-workspace: Deployed"))))
    (should-not (nth 2 (car +test-notify--shown)))
    (should-not (nth 2 (cadr +test-notify--shown)))))

(ert-deftest notify/claude-s-message-as-every-notification ()
  "Emacs in front, or its kind off: not shown (nil, what emacsclient prints);
no message: an error."
  (+test-notify t
    (should-not (+my/notify-claude "x")))
  (+test-notify nil
    (let ((+my/notify-off '(claude)))
      (should-not (+my/notify-claude "x")))
    (should-not +test-notify--shown)
    (should-error (+my/notify-claude "  ") :type 'user-error)
    (should-error (+my/notify-claude nil) :type 'user-error)))

(ert-deftest notify/claude-is-told-how-to-notify ()
  "What Claude Code is told about Emacs gets how to notify, once (loaded
again: not twice)."
  (let ((+my/agent-shell-claude-context "About Emacs."))
    (+test-load "config/notify/claude")
    (+test-load "config/notify/claude")
    (should (string-prefix-p "About Emacs.\n\nNotifications: " +my/agent-shell-claude-context))
    (should (= (with-temp-buffer
                 (insert +my/agent-shell-claude-context)
                 (count-matches "Notifications: " (point-min) (point-max)))
               1))
    (should (string-search "emacsclient --eval '(+my/notify-claude " +my/agent-shell-claude-context))
    ;; Not those it gets already: a turn's end, a permission, a question.
    (should (string-search "when you finish a turn, when you ask for permission and when you ask a question in the conversation: don't send those again"
                           +my/agent-shell-claude-context))))
