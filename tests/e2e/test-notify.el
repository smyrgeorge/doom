;;; tests/e2e/test-notify.el -*- lexical-binding: t; -*-
;; config/notify.el in a GUI Emacs: a real frame's focus (the tests' frame
;; doesn't take the keyboard: Emacs is away; E2E_WINDOW=front gives it the
;; keyboard: in front), and a notification going all the way to what the
;; desktop would be asked to show (recorded: tests/helper.el), as macOS's
;; AppleScript or Linux's D-Bus.

(+test-load "config/notify")
(require 'server)                       ; its variables special, bound below

(defun +test-notify--posted ()
  "What the desktop was asked to show (tests/helper.el records it)."
  +test-notifications)

(ert-deftest e2e-notify/a-gui-frame-says-whether-it-has-the-focus ()
  "A GUI frame's focus is known (t or nil), never `unknown': in front or
away is told, not guessed."
  (should (memq (frame-focus-state (selected-frame)) '(t nil)))
  (should (eq (and (+my/notify-emacs-in-front-p) t)
              (and (seq-some (lambda (frame) (eq (frame-focus-state frame) t)) (frame-list)) t))))

(ert-deftest e2e-notify/away-shown-in-front-not ()
  "A session finished its turn: posted to the desktop while Emacs is away,
titled by its agent; nothing while it's in front."
  (let ((+test-notifications nil)
        (+my/notify-enabled t)
        (+my/notify-off nil)
        (buffer (generate-new-buffer "*claude-code @ e2e*")))
    (with-current-buffer buffer
      (setq-local agent-shell--state (list (cons :agent-config (list (cons :mode-line-name "Claude"))))))
    (unwind-protect
        (cl-letf (((symbol-function '+my/os--dbus-notifications-p) (lambda () t))
                  ((symbol-function 'agent-shell-cwd) (lambda () "/home/me/dev/doom/")))
          (+my/notify-agent-shell--turn-done buffer '((:data (:stop-reason . "end_turn"))))
          (if (+my/notify-emacs-in-front-p)
              (should-not (+test-notify--posted))
            (let ((posted (car (+test-notify--posted))))
              (should posted)
              (if (+my/macos-p)
                  (should (equal posted '(applescript "display notification \"doom: finished\" with title \"Claude\"")))
                (should (eq (car posted) 'dbus))
                (should (equal (plist-get (cdr posted) :title) "Claude"))
                (should (equal (plist-get (cdr posted) :body) "doom: finished"))))))
      (kill-buffer buffer))))

(defun +test-notify--emacsclient ()
  "The emacsclient beside this Emacs (Emacs.app's bin/), else the PATH's."
  (let ((beside (expand-file-name "bin/emacsclient" invocation-directory)))
    (if (file-executable-p beside) beside (executable-find "emacsclient"))))

(ert-deftest e2e-notify/claude-notifies-through-emacsclient ()
  "An agent's way: emacsclient --eval '(+my/notify-agent-shell ...)' to this
Emacs's server: the message (named by the folder given; no session there:
titled Agent shell) posted to the desktop while Emacs is away, t printed
back; in front, nil."
  (let* ((client (or (+test-notify--emacsclient) (ert-skip "No emacsclient")))
         ;; In /tmp: a socket's path is short (the tests' folder's was too long).
         (server-socket-dir (make-temp-file "/tmp/e2e-notify-" t))
         (server-name "e2e-notify")
         (+test-notifications nil)
         (+my/notify-enabled t)
         (+my/notify-off nil)
         (output (generate-new-buffer " *emacsclient*")))
    (unwind-protect
        (cl-letf (((symbol-function '+my/os--dbus-notifications-p) (lambda () t)))
          (server-start)
          (let ((process (make-process
                          :name "emacsclient" :buffer output :connection-type 'pipe
                          ;; No "Process ... finished" in OUTPUT; ended once
                          ;; its output is all read (its reply, on a busy
                          ;; machine, read after it exited).
                          :sentinel #'+test-process-sentinel
                          :command (list client "-s" (expand-file-name server-name server-socket-dir)
                                         "--eval" "(+my/notify-agent-shell \"The tests pass\" \"/home/me/dev/rskit/\")"))))
            (should (+test-wait-for (lambda () (+test-process-ended-p process)) 10))
            (should (zerop (process-exit-status process))))
          (let ((printed (string-trim (with-current-buffer output (buffer-string)))))
            (if (+my/notify-emacs-in-front-p)
                (progn (should (equal printed "nil"))
                       (should-not +test-notifications))
              (should (equal printed "t"))
              (let ((posted (car +test-notifications)))
                (if (+my/macos-p)
                    (should (equal posted '(applescript "display notification \"rskit: The tests pass\" with title \"Agent shell\"")))
                  (should (equal (plist-get (cdr posted) :body) "rskit: The tests pass")))))))
      (server-force-delete)
      (kill-buffer output)
      (delete-directory server-socket-dir t))))
