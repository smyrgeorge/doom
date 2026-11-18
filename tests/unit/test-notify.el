;;; tests/unit/test-notify.el -*- lexical-binding: t; -*-
;; config/notify.el: desktop notifications while Emacs isn't in front. Kinds
;; defined and fired, only when on and Emacs isn't in front (each frame's
;; focus: in front, away, not known), a click bringing Emacs forward on the
;; buffer, the toggles (SPC t n, SPC t N), the test notification; and Claude
;; Code's (config/notify/claude.el): agent-shell's events, stood in for. What
;; the desktop would show is recorded (`+my/os-notify' here,
;; config/emacs/os.el's own posting in tests/helper.el).

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
  ;; Claude Code's, Agent UI's, an agent crew's, so far.
  (should (equal (mapcar #'car +my/notify-kinds)
                 '(agent-napping agent-message agent-stuck agent-done agent-hand
                   agent-ui-question agent-ui-bug claude-question claude-permission claude-turn-done claude))))

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

(ert-deftest notify/toggle-a-kind-none-picked ()
  "SPC t N, nothing picked (empty input, M-RET in vertico): said, none
turned off; nor a kind not defined."
  (+test-notify nil
    (+my/notify-define 'first "Title" "The first")
    (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "")))
      (should-error (call-interactively #'+my/notify-toggle-kind) :type 'user-error))
    (should-error (+my/notify-toggle-kind 'no-such-kind) :type 'user-error)
    (should-error (+my/notify-toggle-kind nil) :type 'user-error)
    (should-not +my/notify-off)))

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
                 '("Claude Code" "A session finished its turn, or stopped on an error")))
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

(ert-deftest notify/claude-stopped-on-an-error ()
  "A session's turn failing (agent-shell's error, no turn-complete: the API
overloaded, the login expired, a rate limit): said with its message, the
first line; a click shows the session. Emacs in front, or the kind off:
nothing."
  (+test-notify nil
    (+test-notify--session "doom"
      (let ((failed (alist-get 'error subscribed)))
        (should failed)
        (funcall failed '((:event . error) (:data (:code . 529) (:message . "Overloaded"))))
        (funcall failed '((:event . error) (:data (:code . -32603) (:message . " Rate limit reached\nTry later "))))
        (funcall failed '((:event . error) (:data (:code . -32603) (:message))))
        (should (equal (mapcar #'butlast +test-notify--shown)
                       '(("Claude Code" "doom: stopped on an error")
                         ("Claude Code" "doom: stopped: Rate limit reached")
                         ("Claude Code" "doom: stopped: Overloaded"))))
        (cl-letf (((symbol-function 'select-frame-set-input-focus) #'ignore))
          (funcall (nth 2 (car +test-notify--shown)))
          (should (eq (window-buffer (selected-window)) session))))))
  (+test-notify t
    (+test-notify--session "doom"
      (funcall (alist-get 'error subscribed) '((:data (:message . "Overloaded"))))
      (should-not +test-notify--shown)))
  (+test-notify nil
    (let ((+my/notify-off '(claude-turn-done)))
      (+test-notify--session "doom"
        (funcall (alist-get 'error subscribed) '((:data (:message . "Overloaded"))))
        (should-not +test-notify--shown)))))

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
              ;; Named as Claude Code's own are: its project.
              (should (equal (butlast (car +test-notify--shown)) '("Agent UI" "doom asks: Which fix?")))
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
a click; no directory, or the root (no folder's name): the message alone."
  (+test-notify nil
    (+my/notify-claude "Deployed" "/home/me/dev/pas-workspace/")
    (+my/notify-claude "Hello")
    (+my/notify-claude "x" "/")
    (should (equal (mapcar #'butlast +test-notify--shown)
                   '(("Claude Code" "x") ("Claude Code" "Hello") ("Claude Code" "pas-workspace: Deployed"))))
    (should-not (seq-some (lambda (shown) (nth 2 shown)) +test-notify--shown))))

(ert-deftest notify/claude-two-sessions-in-one-folder ()
  "Two sessions in one folder: each named by its folder and buffer
\(\"doom · Claude\", \"doom · Claude<2>\"), not both \"doom\"; a message
from the one named, else the one whose turn is running (the caller), not
the last used; a click shows it."
  (+test-with-reset
    (+test-notify nil
      (let ((dir (+test-tmp-file "dev/doom/"))
            (busy nil))
        (make-directory dir t)
        (+test-notify--sessions (list dir dir)
          (with-current-buffer (nth 0 sessions) (rename-buffer "Claude"))
          (with-current-buffer (nth 1 sessions) (rename-buffer "Claude<2>"))
          (cl-letf (((symbol-function 'shell-maker-busy) (lambda () (eq (current-buffer) busy)))
                    ((symbol-function 'select-frame-set-input-focus) #'ignore))
            (should (equal (mapcar #'+my/notify-claude--name sessions) '("doom · Claude" "doom · Claude<2>")))
            ;; The first used last; the second's turn running: its message.
            (switch-to-buffer (nth 0 sessions))
            (setq busy (nth 1 sessions))
            (should (+my/notify-claude "b's tests pass" dir))
            (should (equal (cadr (car +test-notify--shown)) "doom · Claude<2>: b's tests pass"))
            (switch-to-buffer "*scratch*")
            (funcall (nth 2 (car +test-notify--shown)))
            (should (eq (window-buffer (selected-window)) (nth 1 sessions)))
            ;; Named by the caller, as a buffer or its name.
            (should (+my/notify-claude "a's done" dir (nth 0 sessions)))
            (should (equal (cadr (car +test-notify--shown)) "doom · Claude: a's done"))
            (should (+my/notify-claude "b's done" dir "Claude<2>"))
            (should (equal (cadr (car +test-notify--shown)) "doom · Claude<2>: b's done"))
            ;; One left: its folder again.
            (kill-buffer (nth 1 sessions))
            (should (equal (+my/notify-claude--name (nth 0 sessions)) "doom"))))))))

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

;; ====== AN AGENT CREW'S (config/notify/crew.el) ======

(+test-load "config/agent-workspace")

(defmacro +test-notify-crew (&rest body)
  "BODY as `+test-notify' away from Emacs, with an agent `ada' (a builder of
a crew in /tmp/project/, its session `session', a buffer), the quiet times
forgotten; a click's selection recorded in `selected'."
  (declare (indent 0))
  `(+test-notify nil
     (let* ((+my/notify-crew--last (make-hash-table :test #'equal))
            (session (generate-new-buffer "ada · builder"))
            (ada (agent-workspace--make-agent :name "ada" :role "builder" :colour "blue" :state 'working
                                              :project "/tmp/project/" :buffer session))
            (selected nil))
       (with-current-buffer session (setq agent-workspace--agent ada))
       (unwind-protect
           (cl-letf (((symbol-function 'agent-workspace-open) #'ignore)
                     ((symbol-function 'agent-workspace-select) (lambda (agent go) (push (list agent go) selected))))
             ,@body)
         (kill-buffer session)))))

(ert-deftest notify/crew-kinds ()
  (dolist (kind '(agent-hand agent-done agent-stuck agent-message agent-napping))
    (should (assq kind +my/notify-kinds)))
  (should (memq #'+my/notify-crew--state-h agent-workspace-state-change-functions))
  (should (memq #'+my/notify-crew--nap-h agent-workspace-nap-functions))
  (should (memq #'+my/notify-crew--watch agent-workspace-session-functions))
  (should (memq #'+my/notify-crew--own-p +my/notify-claude-own-functions)))

(ert-deftest notify/crew-a-hand-raised ()
  "A hand raised: named by the agent, saying what it wants; a click opens its
crew's app on it, the cursor in its pane."
  (+test-notify-crew
    (agent-workspace--raise-hand ada '(:kind permission :title "npm install" :tool-kind "execute"))
    (should (equal (mapcar #'butlast +test-notify--shown)
                   '(("Agent crew" "ada (builder) wants to run npm install"))))
    (funcall (nth 2 (car +test-notify--shown)))
    (should (equal selected (list (list ada t))))))

(ert-deftest notify/crew-once-per-change-of-state ()
  "Once per change of state, and not again for the same agent and kind
within `+my/notify-crew-quiet' seconds."
  (+test-notify-crew
    (agent-workspace--raise-hand ada '(:kind question :title "restore or rebuild?"))
    (agent-workspace--raise-hand ada '(:kind question :title "and then?"))
    (should (= (length +test-notify--shown) 1))
    (agent-workspace--set-state ada 'working)
    (agent-workspace--raise-hand ada '(:kind question :title "again?"))
    (should (= (length +test-notify--shown) 1))
    (let ((+my/notify-crew-quiet 0))
      (agent-workspace--set-state ada 'working)
      (agent-workspace--raise-hand ada '(:kind question :title "now?"))
      (should (equal (cadr (car +test-notify--shown)) "ada (builder) asks: now?")))))

(ert-deftest notify/crew-stuck-and-done ()
  "Stuck, why; a turn finished, its issue; one you interrupted, nothing."
  (+test-notify-crew
    (setf (agent-workspace-agent-error ada) "its session: the API is overloaded\nmore")
    (agent-workspace--set-state ada 'stuck)
    (should (equal (cadr (car +test-notify--shown)) "ada (builder) is stuck: its session: the API is overloaded"))
    (setf (agent-workspace-agent-issue ada) "doom-a1b")
    (+my/notify-crew--turn-done ada '((:event . turn-complete) (:data (:stop-reason . "end_turn"))))
    (should (equal (cadr (car +test-notify--shown)) "ada (builder) finished doom-a1b"))
    (clrhash +my/notify-crew--last)
    (setq +test-notify--shown nil)
    (+my/notify-crew--turn-done ada '((:event . turn-complete) (:data (:stop-reason . "cancelled"))))
    (should-not +test-notify--shown)))

(ert-deftest notify/crew-napping ()
  "A looping agent with nothing left naps: said once, in its role's verb
\(its loop calls the hook once, until it takes an issue again)."
  (+test-notify-crew
    (setf (agent-workspace-agent-state ada) 'nap)
    (run-hook-with-args 'agent-workspace-nap-functions ada)
    (should (equal (mapcar #'butlast +test-notify--shown)
                   '(("Agent crew" "ada (builder) is napping: nothing to build"))))
    (funcall (nth 2 (car +test-notify--shown)))
    (should (equal selected (list (list ada t))))
    (let ((+my/notify-off '(agent-napping)))
      (clrhash +my/notify-crew--last)
      (run-hook-with-args 'agent-workspace-nap-functions ada)
      (should (= (length +test-notify--shown) 1)))))

(ert-deftest notify/crew-claude-s-kinds-leave-them ()
  "A crew's agent's session: Claude Code's kinds leave it (no notification
twice); its own message named by the agent."
  (+test-notify-crew
    (should (+my/notify-claude--own-p session))
    (with-temp-buffer
      (should-not (+my/notify-claude--own-p (current-buffer))))
    (should (+my/notify-claude "The tests pass" "/tmp/project/.agent-shell/worktrees/ada/" session))
    (should (equal (mapcar #'butlast +test-notify--shown) '(("Agent crew" "ada (builder): The tests pass"))))))

(ert-deftest notify/crew-off-or-in-front ()
  "A kind off, or Emacs in front: nothing."
  (+test-notify-crew
    (let ((+my/notify-off '(agent-hand)))
      (agent-workspace--raise-hand ada '(:kind question :title "?")))
    (should-not +test-notify--shown))
  (+test-notify t
    (let ((ada (agent-workspace--make-agent :name "ada" :role "builder" :state 'working :project "/tmp/p/")))
      (agent-workspace--raise-hand ada '(:kind question :title "?"))
      (should-not +test-notify--shown))))
