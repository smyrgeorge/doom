;;; tests/unit/test-terminal.el -*- lexical-binding: t; -*-
;; config/terminal.el: terminal (tty) frames: the terminal's background painted
;; with the theme's (OSC 11), once it's set up, its own asked first (OSC 11 ?)
;; and given back (OSC 11 with it; else OSC 111) on exit or when an
;; emacsclient -t frame closes, as a terminal Emacs on a pty shows; no menu
;; bar; no tty-tip-mode.

;; As Doom has it, before this config.
(add-hook 'tty-setup-hook #'tty-tip-mode)

(+test-load "config/terminal")

;; The batch Emacs's frame is a terminal one, its terminal the test's output:
;; no escape codes there when it exits.
(add-hook 'kill-emacs-hook (lambda () (fset '+my/tty-reset-bg-h #'ignore)) -90)

;; ====== HELPERS ======

(defvar +test-terminal--sent nil "(STRING TERMINAL) sent, latest first.")

(defmacro +test-terminal (&rest body)
  "BODY with what is sent to terminals recorded in `+test-terminal--sent',
the background queries too (as (QUERY TERMINAL), xterm's queries there)."
  (declare (indent 0))
  `(let ((+test-terminal--sent nil))
     (cl-letf (((symbol-function 'send-string-to-terminal)
                (lambda (string &optional terminal)
                  (push (list string terminal) +test-terminal--sent)))
               ((symbol-function 'xterm--query) #'ignore)
               ((symbol-function '+my/tty--query)
                (lambda (frame query _handler)
                  (push (list query (frame-terminal frame)) +test-terminal--sent))))
       ,@body)))

(defmacro +test-terminal--frames (frames &rest body)
  "BODY with FRAMES ((FRAME TYPE BACKGROUND [TERMINAL])...) the frames: TYPE
what `framep' says (t: a terminal's, ns: GUI), BACKGROUND its default face's,
TERMINAL its terminal (default: FRAME-terminal), set up (`terminal-initted'),
its parameters in `params' ((TERMINAL . PARAMETER) . VALUE)."
  (declare (indent 1))
  `(let ((frames ,frames)
         (params nil)
         (framep (symbol-function 'framep))
         (face-background (symbol-function 'face-background))
         (frame-terminal (symbol-function 'frame-terminal))
         (terminal-parameter (symbol-function 'terminal-parameter))
         (set-terminal-parameter (symbol-function 'set-terminal-parameter)))
     (ignore params)
     (cl-letf (((symbol-function 'frame-list) (lambda () (mapcar #'car frames)))
               ((symbol-function 'terminal-parameter)
                (lambda (terminal parameter)
                  (if (and terminal (symbolp terminal))
                      (let ((cell (assoc (cons terminal parameter) params)))
                        (if cell (cdr cell) (eq parameter 'terminal-initted)))
                    (funcall terminal-parameter terminal parameter))))
               ((symbol-function 'set-terminal-parameter)
                (lambda (terminal parameter value)
                  (if (and terminal (symbolp terminal))
                      (setf (alist-get (cons terminal parameter) params nil nil #'equal) value)
                    (funcall set-terminal-parameter terminal parameter value))))
               ((symbol-function 'framep)
                (lambda (frame) (if (assq frame frames) (nth 1 (assq frame frames))
                                  (funcall framep frame))))
               ((symbol-function 'face-background)
                (lambda (face &optional frame &rest args)
                  (if (and (eq face 'default) (assq frame frames))
                      (nth 2 (assq frame frames))
                    (apply face-background face frame args))))
               ((symbol-function 'frame-terminal)
                (lambda (&optional frame)
                  (if (and frame (symbolp frame))
                      (or (nth 3 (assq frame frames)) (intern (format "%s-terminal" frame)))
                    (funcall frame-terminal frame)))))
       ,@body)))

;; ====== HOOKS ======

(ert-deftest terminal/hooks ()
  (should (memq '+my/tty-sync-bg-h doom-load-theme-hook))
  (should (memq '+my/tty-sync-bg-h tty-setup-hook))
  (should (memq '+my/tty-sync-bg-h after-make-frame-functions))
  (should (memq '+my/tty-reset-bg-h kill-emacs-hook))
  (should (memq '+my/tty-reset-frame-bg-h delete-frame-functions))
  ;; Before the server's (it closes the client's terminal), whenever it starts.
  (require 'server)
  (let ((delete-frame-functions (default-value 'delete-frame-functions)))
    (add-hook 'delete-frame-functions #'server-handle-delete-frame)
    (should (< (seq-position delete-frame-functions '+my/tty-reset-frame-bg-h)
               (seq-position delete-frame-functions 'server-handle-delete-frame))))
  (should (memq '+my/tty-no-menu-bar-h after-make-frame-functions))
  (should (memq '+my/tty-no-menu-bar-h tty-setup-hook)))

(ert-deftest terminal/no-tty-tip-mode ()
  "Doom's `tty-tip-mode' on terminal frames is off: it's global, GUI frames
drew their tips the terminal's way."
  (should-not (memq 'tty-tip-mode tty-setup-hook))
  ;; Loading again: still off, the hooks there once.
  (add-hook 'tty-setup-hook #'tty-tip-mode)
  (+test-load "config/terminal")
  (should-not (memq 'tty-tip-mode tty-setup-hook))
  (should (= (cl-count '+my/tty-sync-bg-h tty-setup-hook) 1)))

;; ====== THE TERMINAL'S BACKGROUND ======

(ert-deftest terminal/background-painted ()
  "OSC 11 with the theme's background, to the terminal of each terminal
frame; its own background asked first, once."
  (+test-terminal
    (+test-terminal--frames '((tty1 t "#282c34") (tty2 t "#1e1e1e"))
      (+my/tty-sync-bg-h)
      (should (equal (reverse +test-terminal--sent)
                     '(("\e]11;?\e\\" tty1-terminal)
                       ("\e]11;#282c34\a" tty1-terminal)
                       ("\e]11;?\e\\" tty2-terminal)
                       ("\e]11;#1e1e1e\a" tty2-terminal))))
      ;; A theme loaded later: painted again, not asked again.
      (setq +test-terminal--sent nil)
      (+my/tty-sync-bg-h)
      (should (equal (reverse +test-terminal--sent)
                     '(("\e]11;#282c34\a" tty1-terminal)
                       ("\e]11;#1e1e1e\a" tty2-terminal)))))))

(ert-deftest terminal/background-not-before-the-terminal-is-set-up ()
  "`emacs -nw' loads Doom's theme before its terminal is set up (the query
needs term/xterm.el): not painted then; tty-setup-hook paints it."
  (+test-terminal
    (+test-terminal--frames '((tty t "#282c34"))
      (setf (alist-get '(tty-terminal . terminal-initted) params nil nil #'equal) nil)
      (+my/tty-sync-bg-h)
      (should-not +test-terminal--sent)
      (setf (alist-get '(tty-terminal . terminal-initted) params nil nil #'equal) 'terminal-init-xterm)
      (+my/tty-sync-bg-h)
      (should (= (length +test-terminal--sent) 2)))))

(ert-deftest terminal/background-not-asked-without-xterm ()
  "A terminal not xterm-like (no xterm queries): painted, not asked."
  (+test-terminal
    (+test-terminal--frames '((tty t "#282c34"))
      (cl-letf (((symbol-function 'xterm--query) nil))
        (fmakunbound 'xterm--query)
        (+my/tty-sync-bg-h))
      (should (equal +test-terminal--sent '(("\e]11;#282c34\a" tty-terminal)))))))

(ert-deftest terminal/background-reply-read ()
  "The reply (after its \\e]11;): rgb:R/G/B up to ST or BEL, kept."
  (dolist (reply '("rgb:1111/2222/3333\e\\" "rgb:aa/bb/cc\a"))
    (+test-terminal--frames '((tty t "#282c34"))
      (let ((unread-command-events (append reply nil)))
        (+my/tty--bg-reply 'tty-terminal))
      (should (equal (terminal-parameter 'tty-terminal '+my/tty-bg)
                     (substring reply 0 (string-match "[\e\a]" reply))))))
  ;; Not a colour: nothing kept.
  (+test-terminal--frames '((tty t "#282c34"))
    (let ((unread-command-events (append "nonsense\e\\" nil)))
      (+my/tty--bg-reply 'tty-terminal))
    (should-not (terminal-parameter 'tty-terminal '+my/tty-bg))))

(ert-deftest terminal/background-of-the-real-frame ()
  "Batch Emacs's own frame is a terminal one (set up here, asked already)."
  (should (eq (framep (selected-frame)) t))
  (let ((before (face-background 'default (selected-frame)))
        (terminal (frame-terminal (selected-frame))))
    (unwind-protect
        (+test-terminal
          (set-terminal-parameter terminal 'terminal-initted t)
          (set-terminal-parameter terminal '+my/tty-bg-asked t)
          (set-face-background 'default "#112233" (selected-frame))
          (+my/tty-sync-bg-h)
          (should (equal +test-terminal--sent
                         (list (list "\e]11;#112233\a" terminal)))))
      (set-terminal-parameter terminal 'terminal-initted nil)
      (set-terminal-parameter terminal '+my/tty-bg-asked nil)
      (set-face-background 'default before (selected-frame)))))

(ert-deftest terminal/background-not-for-gui-frames ()
  (+test-terminal
    (+test-terminal--frames '((gui ns "#282c34") (x x "#282c34") (tty t "#000000"))
      (+my/tty-sync-bg-h)
      (should (equal (reverse +test-terminal--sent)
                     '(("\e]11;?\e\\" tty-terminal) ("\e]11;#000000\a" tty-terminal)))))))

(ert-deftest terminal/background-only-a-colour-code ()
  "Not a #RRGGBB colour (no theme yet, a named colour): left alone."
  (+test-terminal
    (+test-terminal--frames '((a t "unspecified-bg") (b t "black") (c t nil))
      (+my/tty-sync-bg-h)
      (should-not +test-terminal--sent))))

(ert-deftest terminal/background-hook-arguments ()
  "Called with a frame (after-make-frame-functions) or none (themes)."
  (+test-terminal
    (+test-terminal--frames '((tty t "#282c34"))
      (+my/tty-sync-bg-h 'tty)
      (+my/tty-sync-bg-h)
      (+my/tty-sync-bg-h 'tty 'more)
      (should (= (length +test-terminal--sent) 4)))))   ; asked once

(ert-deftest terminal/background-given-back-on-exit ()
  "Its own, as the terminal said (OSC 11); where it didn't, OSC 111 (which
iTerm2 ignores)."
  (+test-terminal
    (+test-terminal--frames '((tty1 t "#282c34") (gui ns "#282c34") (tty2 t "#282c34"))
      (set-terminal-parameter 'tty1-terminal '+my/tty-bg "rgb:1111/2222/3333")
      (+my/tty-reset-bg-h)
      (should (equal (reverse +test-terminal--sent)
                     '(("\e]11;rgb:1111/2222/3333\a" tty1-terminal) ("\e]111\a" tty2-terminal)))))))

(defun +test-terminal--nw (reply)
  "Run a terminal Emacs (this config's terminal.el, Doom's theme) on a pty,
being its terminal: answer its background query with REPLY (nil: no answer,
as tmux), quit it (C-x C-c) once it painted the theme's. What it wrote."
  (let* ((home (make-temp-file (+test-tmp-file "nw-home-") t))
         (setup (format "(progn (run-at-time 30 nil #'kill-emacs 3) (require 'doom-themes) (+test-load \"config/terminal\") (load-theme 'doom-one t) (run-hooks 'doom-load-theme-hook))"))
         (process-environment (append (list "TERM=xterm-256color" "COLORTERM=truecolor"
                                            (concat "TEST_TMP=" (file-name-as-directory home)))
                                      process-environment))
         (output "")
         (answered nil)
         (quitting nil)
         (process (make-process
                   :name "terminal-emacs" :connection-type 'pty :coding 'binary :noquery t
                   :command (list (expand-file-name invocation-name invocation-directory)
                                  "-nw" "-Q" (concat "--init-directory=" home)
                                  "-l" (expand-file-name "helper.el" +test-dir) "--eval" setup)
                   :filter (lambda (_ string) (setq output (concat output string))))))
    (set-process-window-size process 30 100)
    (with-timeout (40 (delete-process process) (error "The terminal Emacs didn't quit: %S" output))
      (while (process-live-p process)
        (accept-process-output process 0.1)
        (when (and reply (not answered) (string-search "\e]11;?" output))
          (setq answered t)
          (process-send-string process reply))
        (when (and (not quitting) (string-search "\e]11;#" output))
          (setq quitting t)
          (process-send-string process "\C-x\C-c"))))
    output))

(ert-deftest terminal/given-back-as-it-was ()
  "A terminal Emacs on a pty that answers the query (iTerm2 does): asked
before the theme's painted, given that very colour back on exit, not OSC 111
(which iTerm2 ignores: the theme's stayed)."
  (let* ((output (+test-terminal--nw "\e]11;rgb:1111/2222/3333\e\\"))
         (asked (string-search "\e]11;?" output))
         (painted (string-search "\e]11;#282c34\a" output))
         (given-back (string-search "\e]11;rgb:1111/2222/3333\a" output)))
    (should asked)
    (should painted)
    (should (< asked painted))
    (should given-back)
    (should (> given-back painted))
    (should-not (string-search "\e]111" output))))

(ert-deftest terminal/given-back-when-a-servers-frame-closes ()
  "cmd/diff with Emacs running as a server: emacsclient -t's frame, on a
terminal that answers; the frame deleted as cmd/diff does it: that terminal
given its own colour back."
  (let* ((home (make-temp-file (+test-tmp-file "server-home-") t))
         ;; A name, not a path: a socket's path has at most ~104 characters.
         (socket (format "doom-test-tty-%d-%d" (emacs-pid) (random 100000)))
         (setup "(progn (run-at-time 60 nil #'kill-emacs 3) (require 'doom-themes) (+test-load \"config/terminal\") (load-theme 'doom-one t) (run-hooks 'doom-load-theme-hook))")
         (emacs (expand-file-name invocation-name invocation-directory))
         ;; COLORTERM the server's own: Emacs reads it from its environment
         ;; for a client's terminal too (24-bit colour, the theme's #RRGGBB;
         ;; without, it was the shell's that ran the tests).
         (process-environment (append (list "TERM=xterm-256color" "COLORTERM=truecolor"
                                            (concat "TEST_TMP=" (file-name-as-directory home)))
                                      process-environment)))
    (call-process emacs nil nil nil (concat "--daemon=" socket) "-Q" (concat "--init-directory=" home)
                  "-l" (expand-file-name "helper.el" +test-dir) "--eval" setup)
    (unwind-protect
        (let* ((output "")
               (answered nil)
               (closing nil)
               ;; 24-bit colour, as cmd/diff gets it (the theme's #RRGGBB).
               (process-environment (cons "COLORTERM=truecolor" process-environment))
               (client (make-process
                        :name "emacsclient-t" :connection-type 'pty :coding 'binary :noquery t
                        :command (list "emacsclient" "-s" socket "-t")
                        :filter (lambda (_ string) (setq output (concat output string))))))
          (set-process-window-size client 30 100)
          (with-timeout (40 (delete-process client) (error "The client didn't end: %S" output))
            (while (process-live-p client)
              (accept-process-output client 0.1)
              (when (and (not answered) (string-search "\e]11;?" output))
                (setq answered t)
                (process-send-string client "\e]11;rgb:1111/2222/3333\e\\"))
              (when (and answered (not closing) (string-search "\e]11;#" output))
                (setq closing t)
                (sleep-for 0.5)         ; the reply read (the client's output too)
                ;; As cmd/diff's end: its frame deleted. Not waited for here:
                ;; this Emacs is the client's terminal, and while it waited it
                ;; read nothing, the pty filled, the server's writes to it
                ;; blocked, and the request never came back.
                (make-process
                 :name "emacsclient-e" :noquery t :buffer nil
                 :command (list "emacsclient" "-s" socket "-e"
                                "(dolist (f (frame-list)) (when (and (eq (framep f) t) (terminal-parameter f 'terminal-initted) (not (eq (frame-terminal f) (frame-terminal terminal-frame)))) (delete-frame f t)))")))))
          (when (process-live-p client) (delete-process client))
          (should answered)
          (should (string-search "\e]11;rgb:1111/2222/3333\a" output))
          (should-not (string-search "\e]111" output)))
      ;; The client gone first (see above), then the server.
      (dolist (process (process-list))
        (when (string-prefix-p "emacsclient" (process-name process))
          (delete-process process)))
      (call-process "emacsclient" nil nil nil "-s" socket "-e" "(kill-emacs)"))))

(ert-deftest terminal/given-back-with-a-reset-if-it-never-said ()
  "No answer (tmux detached, a terminal without the query): OSC 111."
  (let ((output (+test-terminal--nw nil)))
    (should (string-search "\e]11;#282c34\a" output))
    (should (string-search "\e]111\a" output))))

(ert-deftest terminal/background-given-back-when-a-frame-closes ()
  "emacsclient -t: its frame closing gives its terminal its colour back."
  (+test-terminal
    (+test-terminal--frames '((tty t "#282c34") (gui ns "#282c34"))
      (cl-letf (((symbol-function 'frame-live-p) (lambda (frame) (memq frame '(tty gui)))))
        (+my/tty-reset-frame-bg-h 'tty)
        (should (equal +test-terminal--sent '(("\e]111\a" tty-terminal))))
        ;; GUI frames: nothing.
        (setq +test-terminal--sent nil)
        (+my/tty-reset-frame-bg-h 'gui)
        (should-not +test-terminal--sent)
        ;; The terminal gone already (its window closed): the frame is dead.
        (+my/tty-reset-frame-bg-h 'dead)
        (should-not +test-terminal--sent)))))

(ert-deftest terminal/background-kept-while-another-frame-shows-it ()
  "C-x 5 0 of one of two frames in a terminal: the other still shows the
theme's background; the last one gives it back."
  (+test-terminal
    (+test-terminal--frames '((one t "#282c34" shared) (two t "#282c34" shared)
                              (elsewhere t "#282c34"))
      (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t)))
        (+my/tty-reset-frame-bg-h 'one)
        (should-not +test-terminal--sent)))
    (+test-terminal--frames '((two t "#282c34" shared) (elsewhere t "#282c34"))
      (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t)))
        (+my/tty-reset-frame-bg-h 'two)
        (should (equal +test-terminal--sent '(("\e]111\a" shared))))))))

(ert-deftest terminal/background-closing-frame-errors-ignored ()
  (+test-terminal--frames '((tty t "#282c34"))
    (cl-letf (((symbol-function 'frame-live-p) (lambda (_) t))
              ((symbol-function 'send-string-to-terminal)
               (lambda (&rest _) (error "Terminal gone"))))
      (should-not (+my/tty-reset-frame-bg-h 'tty)))))

;; ====== NO MENU BAR ======

(ert-deftest terminal/no-menu-bar-in-terminal-frames ()
  (let ((before (frame-parameter nil 'menu-bar-lines)))
    (unwind-protect
        (progn
          (set-frame-parameter nil 'menu-bar-lines 1)
          (+my/tty-no-menu-bar-h (selected-frame))
          (should (eql (frame-parameter nil 'menu-bar-lines) 0))
          ;; No frame: the selected one (emacs -nw's first).
          (set-frame-parameter nil 'menu-bar-lines 1)
          (+my/tty-no-menu-bar-h)
          (should (eql (frame-parameter nil 'menu-bar-lines) 0))
          ;; A new frame.
          (set-frame-parameter nil 'menu-bar-lines 1)
          (let ((after-make-frame-functions '(+my/tty-no-menu-bar-h)))
            (run-hook-with-args 'after-make-frame-functions (selected-frame)))
          (should (eql (frame-parameter nil 'menu-bar-lines) 0)))
      (set-frame-parameter nil 'menu-bar-lines before))))

(ert-deftest terminal/menu-bar-off-already-left-alone ()
  (let ((set nil))
    (cl-letf (((symbol-function 'frame-parameter) (lambda (_ p) (and (eq p 'menu-bar-lines) 0)))
              ((symbol-function 'set-frame-parameter) (lambda (&rest args) (setq set args))))
      (+my/tty-no-menu-bar-h (selected-frame)))
    (should-not set)))

(ert-deftest terminal/menu-bar-kept-in-gui-frames ()
  "macOS GUI frames: it lives in the system's menu bar."
  (let ((set nil))
    (+test-terminal--frames '((gui ns "#282c34"))
      (cl-letf (((symbol-function 'frame-parameter) (lambda (_ p) (and (eq p 'menu-bar-lines) 1)))
                ((symbol-function 'set-frame-parameter) (lambda (&rest args) (setq set args))))
        (+my/tty-no-menu-bar-h 'gui)))
    (should-not set)))

;; ====== LOADED ======

(ert-deftest terminal/config-el-loads-it ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.el" +test-root))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file))
      (should (member '(load! "config/terminal") forms)))))
