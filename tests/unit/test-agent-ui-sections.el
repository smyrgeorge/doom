;;; tests/unit/test-agent-ui-sections.el -*- lexical-binding: t; -*-
;; config/agent-ui/canvas.el's sections: a canvas divided by dividers, each
;; section's elements its own (their ids too), shown, changed, listed,
;; cleared in it; a section's title and state changed, folded and unfolded
;; (a question shown in it unfolds it); removed. A session's canvas shown in
;; a section of another (`agent-ui-host'): what it shows goes there, its
;; requests, its questions and actions its own; given back. No agent runs:
;; sessions are buffers the tests make.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defvar +test-aus-sessions nil "The sessions `agent-ui--sessions' gives.")

(defmacro +test-aus (&rest body)
  "BODY with a canvas of its own, `canvas' (its name `name'), no pane
shown, `+test-aus-sessions' agent-shell's sessions; the buffers it makes,
and what it hosts, gone after."
  (declare (indent 0))
  `(let* ((agent-ui-display-function #'ignore)
          (agent-ui-default-width 40)
          (+test-aus-sessions nil)
          (agent-ui--hosts nil)
          (before (buffer-list))
          (name (make-temp-name "run-"))
          (canvas (agent-ui-canvas name)))
     (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () +test-aus-sessions)))
       (unwind-protect (progn ,@body)
         (dolist (b (buffer-list))
           (unless (memq b before) (kill-buffer b)))))))

(defun +test-aus-session (session)
  "A session's buffer, its name for Agent UI SESSION."
  (let ((buffer (generate-new-buffer session)))
    (with-current-buffer buffer (setq agent-ui-session session))
    (push buffer +test-aus-sessions)
    buffer))

(defun +test-aus-lines (canvas)
  "CANVAS's text as it shows it (folded sections hidden), drawn first: its
lines, the blank ones left out."
  (with-current-buffer canvas
    (agent-ui--flush)
    (let ((text "") (pos (point-min)))
      (while (< pos (point-max))
        (let ((next (next-char-property-change pos)))
          (unless (invisible-p pos)
            (setq text (concat text (buffer-substring-no-properties pos next))))
          (setq pos next)))
      (split-string text "\n" t))))

(defun +test-aus-ids (canvas &optional section)
  (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements :canvas canvas :section section)))

(defun +test-aus-message (fn &rest args)
  (agent-ui-error-message (should-error (apply fn args) :type 'agent-ui-error)))

;; ====== A CANVAS DIVIDED ======

(ert-deftest agent-ui-sections/a-canvas-divided ()
  "Its own elements first, then each section under its divider (its fold's
arrow, its title, its state's mark, its note, a rule to the width), its
elements in their order; a section's ids its own; a new section shows the
canvas."
  (+test-aus
    (let* ((shown nil)
           (agent-ui-display-function (lambda (b) (push b shown))))
      (should (equal (agent-ui-section canvas "review" :title "Review" :state 'running :note "3m") "review"))
      (should (equal shown (list canvas)))
      (agent-ui-section canvas "build" :title "Build" :state "done")
      (agent-ui-show '(:id "plan" :type "text" :text "Own plan") :canvas canvas)
      (agent-ui-show '(:id "plan" :type "text" :text "Review plan") :canvas canvas :section "review")
      (agent-ui-show '(:id "notes" :type "text" :text "Review notes") :canvas canvas :section "review")
      (agent-ui-show '(:id "plan" :type "text" :text "Build plan") :canvas canvas :section "build")
      (should (equal (+test-aus-lines canvas)
                     (list "Own plan"
                           (concat "▾ Review ● 3m " (make-string 26 ?─))
                           "Review plan" "Review notes"
                           (concat "▾ Build ✓ " (make-string 30 ?─))
                           "Build plan")))
      ;; Each section's elements, its own; the canvas's, outside them.
      (should (equal (+test-aus-ids canvas) '("plan")))
      (should (equal (+test-aus-ids canvas "review") '("plan" "notes")))
      (should (equal (+test-aus-ids canvas "build") '("plan")))
      (should (equal (plist-get (agent-ui-get "plan" :canvas canvas :section "build") :text) "Build plan"))
      ;; Kept by their keys.
      (with-current-buffer canvas
        (should (equal agent-ui--order '("plan" "review/plan" "review/notes" "build/plan"))))
      (should (equal (mapcar (lambda (s) (plist-get s :name)) (agent-ui-sections canvas)) '("review" "build")))
      (should (equal (car (agent-ui-sections canvas))
                     '(:name "review" :title "Review" :state running :note "3m" :folded nil :hosts nil :elements 2))))))

(ert-deftest agent-ui-sections/one-after-another ()
  "A section after another (its elements), else at the end; the canvas's
own elements before them all, however late they come."
  (+test-aus
    (agent-ui-section canvas "a")
    (agent-ui-section canvas "c")
    (agent-ui-show '(:id "x" :type "text" :text "in a") :canvas canvas :section "a")
    (agent-ui-section canvas "b" :after "a")
    (agent-ui-show '(:id "x" :type "text" :text "in b") :canvas canvas :section "b")
    (agent-ui-show '(:id "x" :type "text" :text "in c") :canvas canvas :section "c")
    (agent-ui-show '(:id "own" :type "text" :text "own") :canvas canvas)
    (agent-ui-show '(:id "y" :type "text" :text "in a too") :canvas canvas :section "a")
    (should (equal (mapcar (lambda (line) (car (split-string line " ─")))
                           (+test-aus-lines canvas))
                   '("own" "▾ a" "in a" "in a too" "▾ b" "in b" "▾ c" "in c")))
    (should (equal (mapcar (lambda (s) (plist-get s :name)) (agent-ui-sections canvas)) '("a" "b" "c")))
    (should (string-match-p "no section \"nope\" to put d after"
                            (+test-aus-message #'agent-ui-section canvas "d" :after "nope")))))

(ert-deftest agent-ui-sections/elements-in-a-section ()
  "Updated, appended to, removed, replaced in their section; ids taken in a
section, not in another; a section that isn't there, a bad name, said."
  (+test-aus
    (agent-ui-section canvas "s")
    (agent-ui-section canvas "t")
    (agent-ui-show '(:id "p" :type "progress" :max 4) :canvas canvas :section "s")
    (agent-ui-show '(:id "p" :type "progress" :max 9) :canvas canvas :section "t")
    (agent-ui-update "p" '(:value 2) :canvas canvas :section "s")
    (should (= (plist-get (agent-ui-get "p" :canvas canvas :section "s") :value) 2))
    (should-not (plist-get (agent-ui-get "p" :canvas canvas :section "t") :value))
    (agent-ui-show '(:id "l" :type "log" :lines ("a")) :canvas canvas :section "s")
    (agent-ui-append "l" '(:lines ("b")) :canvas canvas :section "s")
    (should (equal (plist-get (agent-ui-get "l" :canvas canvas :section "s") :lines) '("a" "b")))
    ;; By its key, from the canvas.
    (should (equal (plist-get (agent-ui-get "s/l" :canvas canvas) :lines) '("a" "b")))
    ;; A panel's child's id: taken in its section only.
    (agent-ui-show '(:id "box" :type "panel" :children ((:id "kid" :type "text" :text "k"))) :canvas canvas :section "s")
    (agent-ui-show '(:id "kid" :type "text" :text "free in t") :canvas canvas :section "t")
    (should (string-match-p "the id \"kid\" is taken in section s of canvas"
                            (+test-aus-message #'agent-ui-show '(:id "x" :type "panel" :children ((:id "kid" :type "text" :text "k")))
                                               :canvas canvas :section "s")))
    (agent-ui-update "kid" '(:text "changed") :canvas canvas :section "s")
    (should (equal (plist-get (agent-ui-get "kid" :canvas canvas :section "s") :text) "changed"))
    (should (equal (plist-get (agent-ui-get "kid" :canvas canvas :section "t") :text) "free in t"))
    (agent-ui-remove "p" :canvas canvas :section "s")
    (should (equal (+test-aus-ids canvas "s") '("l" "box" "kid")))
    (should (equal (+test-aus-ids canvas "t") '("p" "kid")))
    (should (string-match-p "no element \"p\" in section s of canvas .*; its elements: l, box"
                            (+test-aus-message #'agent-ui-update "p" '(:value 1) :canvas canvas :section "s")))
    (should (string-match-p "has no section \"u\"; its sections: s, t"
                            (+test-aus-message #'agent-ui-show '(:type "text" :text "x") :canvas canvas :section "u")))
    (should (string-match-p "a section's name is letters"
                            (+test-aus-message #'agent-ui-section canvas "a/b")))
    (should (string-match-p "a section's state is one of running, needs-you"
                            (+test-aus-message #'agent-ui-section canvas "s" :state 'sleeping)))
    ;; Its hooks are given keys.
    (let* ((keys nil)
           (agent-ui-shown-functions (list (lambda (key _element) (push key keys))))
           (agent-ui-removed-functions (list (lambda (key) (push (list 'gone key) keys)))))
      (agent-ui-show '(:id "q" :type "panel" :children ((:id "qq" :type "text" :text "k")))
                     :canvas canvas :section "t")
      (agent-ui-remove "q" :canvas canvas :section "t")
      (should (equal (reverse keys) '("t/q" "t/qq" (gone "t/q") (gone "t/qq")))))))

;; ====== A SECTION'S STATE, ITS FOLD ======

(ert-deftest agent-ui-sections/title-and-state-changed ()
  "Given again: only what's given changes, its divider redrawn; running, its
mark glows (the canvas's animation runs), until it's done."
  (+test-aus
    (agent-ui-section canvas "s" :title "Tests" :state 'waiting)
    (should (string-prefix-p "▾ Tests ○ ─" (car (+test-aus-lines canvas))))
    (agent-ui-section canvas "s" :state 'running :note "12s")
    (should (string-prefix-p "▾ Tests ● 12s ─" (car (+test-aus-lines canvas))))
    (should (buffer-local-value 'agent-ui--animation-timer canvas))
    (agent-ui-section canvas "s" :state 'needs-you :note nil)
    (should (string-prefix-p "▾ Tests ◆ ─" (car (+test-aus-lines canvas))))
    (with-current-buffer canvas (agent-ui--animate))
    (should-not (buffer-local-value 'agent-ui--animation-timer canvas))
    (agent-ui-section canvas "s" :title "Unit tests" :state 'failed)
    (should (string-prefix-p "▾ Unit tests ✗ ─" (car (+test-aus-lines canvas))))
    (agent-ui-section canvas "s" :state nil)
    (should (string-prefix-p "▾ Unit tests ─" (car (+test-aus-lines canvas))))
    ;; Its words over its mark.
    (agent-ui-section canvas "s" :state 'done)
    (with-current-buffer canvas
      (agent-ui--flush)
      (goto-char (point-min))
      (search-forward "✓")
      (should (equal (get-text-property (match-beginning 0) 'help-echo) "done")))
    ;; A long title: cut, the rule still there.
    (agent-ui-section canvas "s" :title (make-string 60 ?x))
    (let ((line (car (+test-aus-lines canvas))))
      (should (= (string-width line) 40))
      (should (string-suffix-p "… ─" line)))))

(ert-deftest agent-ui-sections/folded-and-unfolded ()
  "TAB on its divider folds a section to it (saying how many it hides), the
cursor in it put on its divider; what comes in meanwhile hidden too; TAB
again unfolds it. Folded from Lisp too."
  (+test-aus
    (agent-ui-section canvas "a" :title "A")
    (agent-ui-section canvas "b" :title "B")
    (agent-ui-show '(:id "one" :type "text" :text "first") :canvas canvas :section "a")
    (agent-ui-show '(:id "two" :type "text" :text "second") :canvas canvas :section "a")
    (agent-ui-show '(:id "x" :type "text" :text "in b") :canvas canvas :section "b")
    ;; TAB on it.
    (with-current-buffer canvas
      (agent-ui--flush)
      (goto-char (point-min))
      (should (equal (key-binding (kbd "TAB")) #'agent-ui-section-toggle))
      (agent-ui-section-toggle))
    (should (equal (mapcar (lambda (line) (car (split-string line " ─")))
                           (+test-aus-lines canvas))
                   '("▸ A · 2 hidden" "▾ B" "in b")))
    (with-current-buffer canvas
      (goto-char (point-min))
      (agent-ui-section-toggle))
    ;; The cursor in it, folded: on its divider.
    (with-current-buffer canvas
      (agent-ui--flush)
      (goto-char (point-min))
      (search-forward "second"))
    (agent-ui-section canvas "a" :folded t)
    (with-current-buffer canvas
      (should (= (point) (point-min))))
    (should (plist-get (car (agent-ui-sections canvas)) :folded))
    (agent-ui-show '(:id "three" :type "text" :text "third") :canvas canvas :section "a")
    (should (equal (car (+test-aus-lines canvas)) (concat "▸ A · 3 hidden " (make-string 25 ?─))))
    (should (equal (cdr (+test-aus-lines canvas)) (list (concat "▾ B " (make-string 36 ?─)) "in b")))
    (with-current-buffer canvas
      (goto-char (point-min))
      (agent-ui-section-toggle))
    (should (equal (mapcar (lambda (line) (car (split-string line " ─")))
                           (+test-aus-lines canvas))
                   '("▾ A" "first" "second" "third" "▾ B" "in b")))
    ;; Not on a divider.
    (with-current-buffer canvas
      (goto-char (point-min))
      (search-forward "first")
      (should-error (agent-ui-section-toggle) :type 'user-error))
    ;; From Lisp; the last section's fold to the canvas's end.
    (agent-ui-section canvas "b" :folded t)
    (should (equal (+test-aus-lines canvas)
                   (list (concat "▾ A " (make-string 36 ?─)) "first" "second" "third"
                         (concat "▸ B · 1 hidden " (make-string 25 ?─)))))
    (agent-ui-show '(:id "y" :type "text" :text "more in b") :canvas canvas :section "b")
    (should (equal (car (last (+test-aus-lines canvas))) (concat "▸ B · 2 hidden " (make-string 25 ?─))))))

(ert-deftest agent-ui-sections/a-question-unfolds-its-section ()
  "A question shown in a folded section unfolds it, in view; another
element doesn't."
  (should (memq #'agent-ui--reveal-question-h (default-value 'agent-ui-shown-functions)))
  (+test-aus
    (let ((agent-ui-focus-questions nil))
      (agent-ui-section canvas "s" :folded t)
      (agent-ui-show '(:id "t" :type "text" :text "quiet") :canvas canvas :section "s")
      (should (plist-get (car (agent-ui-sections canvas)) :folded))
      (agent-ui-show '(:id "q" :type "confirm" :question "Merge it?") :canvas canvas :section "s")
      (should-not (plist-get (car (agent-ui-sections canvas)) :folded))
      (should (seq-some (lambda (line) (string-search "Merge it?" line)) (+test-aus-lines canvas))))))

;; ====== REMOVED, CLEARED ======

(ert-deftest agent-ui-sections/removed-and-cleared ()
  "A section removed: its elements and divider gone, the rest as it was; one
cleared: its elements only. The canvas cleared: its sections too, its panes
closed. A canvas with sections isn't empty."
  (+test-aus
    (let ((gone nil))
      (agent-ui-section canvas "a")
      (agent-ui-section canvas "b")
      (agent-ui-show '(:id "own" :type "text" :text "own") :canvas canvas)
      (agent-ui-show '(:id "x" :type "text" :text "in a") :canvas canvas :section "a")
      (agent-ui-show '(:id "x" :type "text" :text "in b") :canvas canvas :section "b")
      (let ((agent-ui-removed-functions (list (lambda (key) (push key gone)))))
        (should (equal (agent-ui-remove-section canvas "a") "a")))
      (should (equal gone '("a/x")))
      (should (equal (mapcar (lambda (line) (car (split-string line " ─"))) (+test-aus-lines canvas))
                     '("own" "▾ b" "in b")))
      (should (string-match-p "has no section \"a\"" (+test-aus-message #'agent-ui-remove-section canvas "a")))
      (agent-ui-clear :canvas canvas :section "b")
      (should (equal (mapcar (lambda (line) (car (split-string line " ─"))) (+test-aus-lines canvas))
                     '("own" "▾ b")))
      ;; Its own elements gone: the section keeps it.
      (agent-ui-remove "own" :canvas canvas)
      (should (buffer-live-p canvas))
      (with-current-buffer canvas (should-not (agent-ui--empty-p)))
      (agent-ui-show '(:id "own" :type "text" :text "back") :canvas canvas)
      (agent-ui-clear :canvas canvas)
      (should-not (agent-ui-sections canvas))
      (should-not (agent-ui-elements :canvas canvas))
      (should (equal (with-current-buffer canvas (buffer-string)) "")))))

;; ====== A CANVAS SHOWN IN ANOTHER'S SECTION ======

(ert-deftest agent-ui-sections/a-canvas-shown-in-a-section ()
  "Hosted: what's shown in it (its other canvases too) goes into the
section, no buffer of its own; its list, get and clear see the section
only. Its canvases there before: moved into it, closed. Removed: its own
canvas again, with its next element."
  (+test-aus
    (let* ((hosted nil)
           (agent-ui-host-functions (list (lambda (&rest args) (push args hosted)))))
      (agent-ui-section canvas "job" :title "build")
      (agent-ui-show '(:id "plan" :type "text" :text "the run's own") :canvas canvas)
      ;; Its canvases before: moved in, closed.
      (agent-ui-show '(:id "early" :type "text" :text "before") :canvas "agent-a")
      (agent-ui-show '(:id "t" :type "text" :text "tests before") :canvas "agent-a / tests")
      (should (equal (agent-ui-host "agent-a" canvas "job") "agent-a"))
      (should (equal hosted (list (list "agent-a" canvas "job"))))
      (should-not (get-buffer (agent-ui-canvas-buffer-name "agent-a")))
      (should-not (get-buffer (agent-ui-canvas-buffer-name "agent-a / tests")))
      (should (equal (+test-aus-ids canvas "job") '("early" "t")))
      (should (equal (plist-get (car (agent-ui-sections canvas)) :hosts) "agent-a"))
      ;; What it shows now: there, by its names.
      (agent-ui-show '(:id "plan" :type "text" :text "the agent's plan") :canvas "agent-a")
      (agent-ui-show '(:id "out" :type "text" :text "its tests") :canvas "agent-a / tests")
      (should-not (get-buffer (agent-ui-canvas-buffer-name "agent-a")))
      (should (equal (+test-aus-ids canvas "job") '("early" "t" "plan" "out")))
      (should (equal (+test-aus-ids canvas) '("plan")))
      (should (equal (+test-aus-ids "agent-a") '("early" "t" "plan" "out")))
      (should (equal (plist-get (agent-ui-get "plan" :canvas "agent-a") :text) "the agent's plan"))
      (should (equal (plist-get (agent-ui-get "plan" :canvas canvas) :text) "the run's own"))
      (agent-ui-update "plan" '(:text "plan, changed") :canvas "agent-a")
      (should (member "plan, changed" (+test-aus-lines canvas)))
      ;; No sections of its own.
      (should (string-match-p "is shown in section job of canvas"
                              (+test-aus-message #'agent-ui-section "agent-a" "x")))
      ;; Cleared: the section's elements only.
      (agent-ui-clear :canvas "agent-a")
      (should-not (+test-aus-ids canvas "job"))
      (should (equal (+test-aus-ids canvas) '("plan")))
      (should (agent-ui-sections canvas))
      ;; The section removed: its own canvas again.
      (agent-ui-show '(:id "x" :type "text" :text "x") :canvas "agent-a")
      (agent-ui-remove-section canvas "job")
      (should-not agent-ui--hosts)
      (agent-ui-show '(:id "y" :type "text" :text "own again") :canvas "agent-a")
      (should (get-buffer (agent-ui-canvas-buffer-name "agent-a")))
      (should (equal (+test-aus-ids "agent-a") '("y")))
      ;; Unhosted: its elements there gone, the section staying.
      (agent-ui-section canvas "job2")
      (agent-ui-host "agent-b" canvas "job2")
      (agent-ui-show '(:id "z" :type "text" :text "b's") :canvas "agent-b")
      (should (equal (agent-ui-unhost "agent-b") "agent-b"))
      (should-not (+test-aus-ids canvas "job2"))
      (should (agent-ui-sections canvas))
      (should-not (plist-get (car (agent-ui-sections canvas)) :hosts))
      ;; Unhosted, KEEP: its elements there kept, the section's own; its
      ;; next element on a canvas of its own.
      (agent-ui-host "agent-k" canvas "job2")
      (agent-ui-show '(:id "k" :type "text" :text "k's") :canvas "agent-k")
      (should (equal (agent-ui-unhost "agent-k" t) "agent-k"))
      (should (equal (+test-aus-ids canvas "job2") '("k")))
      (should-not (plist-get (car (agent-ui-sections canvas)) :hosts))
      (agent-ui-show '(:id "k2" :type "text" :text "on its own") :canvas "agent-k")
      (should (equal (+test-aus-ids "agent-k") '("k2")))
      (should (equal (+test-aus-ids canvas "job2") '("k")))
      (kill-buffer (agent-ui-canvas-buffer-name "agent-k"))
      (agent-ui-remove "k" :canvas canvas :section "job2")
      ;; Not in itself, nor in a section that isn't there.
      (should (string-match-p "can't be shown in its own section"
                              (+test-aus-message #'agent-ui-host name canvas "job2")))
      (should (string-match-p "has no section \"nope\""
                              (+test-aus-message #'agent-ui-host "agent-c" canvas "nope")))
      ;; The host killed: on its own again.
      (agent-ui-host "agent-c" canvas "job2")
      (kill-buffer canvas)
      (should-not agent-ui--hosts)
      (agent-ui-show '(:id "w" :type "text" :text "c's own") :canvas "agent-c")
      (should (get-buffer (agent-ui-canvas-buffer-name "agent-c"))))))

(ert-deftest agent-ui-sections/a-hosted-sessions-requests ()
  "cmd/agent-ui's requests for a session shown in a section: in it, said by
its own name (its links, get's canvas); an id with / (a key) refused."
  (+test-aus
    (agent-ui-section canvas "job")
    (agent-ui-show '(:id "own" :type "text" :text "the run's") :canvas canvas)
    (agent-ui-host "sess" canvas "job")
    (let ((reply (agent-ui-do "show" nil '(:id "plan" :type "text" :text "p") "sess")))
      (should (equal (plist-get reply :id) "plan"))
      (should (equal (plist-get reply :link) "agent-ui://canvas/sess#plan")))
    (should (equal (mapcar (lambda (e) (plist-get e :id)) (plist-get (agent-ui-do "list" nil nil "sess") :elements))
                   '("plan")))
    (let ((got (agent-ui-do "get" nil nil "sess")))
      (should (equal (plist-get got :canvas) "sess"))
      (should (equal (mapcar (lambda (e) (plist-get e :id)) (plist-get got :elements)) '("plan"))))
    (agent-ui-do "update" "plan" '(:text "q") "sess")
    (should (equal (plist-get (agent-ui-get "plan" :canvas "sess") :text) "q"))
    ;; Its batch's operations on its other canvas: the same section.
    (agent-ui-do "batch" nil '((:op "show" :id "n" :type "text" :text "n" :canvas "notes")) "sess")
    (let ((agent-ui--request-canvas "sess"))
      (agent-ui-do "batch" nil '((:op "show" :id "m" :type "text" :text "m" :canvas "notes")) "sess"))
    (should (equal (+test-aus-ids canvas "job") '("plan" "n" "m")))
    ;; Another section's element, by its key: not reached.
    (should (string-match-p "an id is letters"
                            (plist-get (aref (plist-get (agent-ui-do "batch" nil '((:op "remove" :id "job/plan")) "sess")
                                                        :results)
                                             0)
                                       :error)))
    (should (string-match-p "an id is letters" (+test-aus-message #'agent-ui-do "get" "job/plan" nil "sess")))
    ;; The link opens the canvas it's shown in, on it.
    (let ((agent-ui-display-function (lambda (b) (set-window-buffer (selected-window) b))))
      (should (eq (agent-ui-open-link "agent-ui://canvas/sess#plan") canvas))
      (with-current-buffer canvas
        (should (equal (get-text-property (point) 'agent-ui-id) "job/plan"))))))

(ert-deftest agent-ui-sections/a-hosted-sessions-actions-and-questions ()
  "In a section hosting a session's canvas: its buttons act in that session;
its questions wait for it (its mode line's mark), answered they go, with
what was shown with them (on its ask canvas: all of it). The session killed:
its elements there gone, the section staying."
  (+test-aus
    (let* ((session (+test-aus-session "Claude Agent @ job"))
           (other (+test-aus-session "Claude Agent @ else"))
           (inserted nil)
           (agent-ui-focus-questions nil)
           (agent-ui-close-answered t))
      (ignore other)
      (agent-ui-section canvas "job")
      (agent-ui-host "Claude Agent @ job" canvas "job")
      (agent-ui-show '(:id "t" :type "text" :text "2 failed" :actions ((:label "Retry" :prompt "Run them again")))
                     :canvas "Claude Agent @ job")
      (cl-letf (((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args inserted)))
                ((symbol-function 'agent-ui--session-busy-p) #'ignore))
        (with-current-buffer canvas
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "⏵ Retry")
          (goto-char (match-beginning 0))
          (agent-ui-button-press)))
      (should (equal (plist-get (car inserted) :shell-buffer) session))
      ;; Its questions, its.
      (agent-ui-show '(:id "mock" :type "text" :text "A mockup") :canvas "Claude Agent @ job / ask")
      (agent-ui-show '(:id "go" :type "confirm" :question "Merge?") :canvas "Claude Agent @ job / ask")
      (should (equal (agent-ui--waiting session) (list (cons canvas "job/go"))))
      (should-not (agent-ui--waiting other))
      (agent-ui--question-check session)
      (should (buffer-local-value 'agent-ui--question-waiting session))
      (let ((agent-ui-action-function #'ignore))
        (with-current-buffer canvas
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "⏵ Proceed")
          (goto-char (match-beginning 0))
          (agent-ui-button-press)))
      (let ((end (+ (float-time) 0.2)))
        (while (< (float-time) end) (accept-process-output nil 0.02)))
      ;; Answered: the question and its ask canvas's mockup gone, the rest
      ;; staying; the mark off.
      (should (equal (+test-aus-ids canvas "job") '("t")))
      (should-not (buffer-local-value 'agent-ui--question-waiting session))
      ;; The session killed: its elements gone, the section staying.
      (kill-buffer session)
      (should-not (+test-aus-ids canvas "job"))
      (should (agent-ui-sections canvas))
      (should-not agent-ui--hosts))))

;; ====== A CANVAS OF ITS OWN ======

(ert-deftest agent-ui-sections/a-canvas-answering-itself ()
  "A canvas with an answer function (`agent-ui-answer-function'): its
questions' answers go to it, with their element's key, not to a session;
but those of a section hosting a session's canvas, to that session."
  (+test-aus
    (let* ((session (+test-aus-session "Claude Agent @ own"))
           (answered nil)
           (inserted nil)
           (agent-ui-focus-questions nil))
      (with-current-buffer canvas
        (setq-local agent-ui-answer-function (lambda (prompt submit key) (push (list prompt submit key) answered))))
      (agent-ui-section canvas "needs")
      (agent-ui-section canvas "agent")
      (agent-ui-host "Claude Agent @ own" canvas "agent")
      (agent-ui-show '(:id "ask" :type "confirm" :question "Merge?") :canvas canvas :section "needs")
      (agent-ui-show '(:id "ask" :type "confirm" :question "The agent's?") :canvas "Claude Agent @ own")
      (cl-letf (((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args inserted)))
                ((symbol-function 'agent-ui--session-busy-p) #'ignore))
        (with-current-buffer canvas
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "⏵ Proceed")
          (goto-char (match-beginning 0))
          (agent-ui-button-press)
          ;; The first answered: the other's button the only one left.
          (agent-ui--flush)
          (goto-char (point-min))
          (search-forward "⏵ Proceed")
          (goto-char (match-beginning 0))
          (agent-ui-button-press)))
      ;; Its id in the answer's words, not its key.
      (should (equal answered '(("Answer to confirm ask (Merge?): proceed" t "needs/ask"))))
      (should (equal (agent-ui--unkeyed "Answer to steps job.a/plan (x): job.a/plan, ajob.a/no" "job.a")
                     "Answer to steps plan (x): plan, ajob.a/no"))
      (should (equal (plist-get (car inserted) :shell-buffer) session))
      (should (equal (plist-get (car inserted) :text) "Answer to confirm ask (The agent's?): proceed")))))

(ert-deftest agent-ui-sections/ret-on-a-divider ()
  "RET on a divider: its section's :open, if it has one; else it folds, as
TAB; its help says so."
  (+test-aus
    (let ((opened 0))
      (agent-ui-section canvas "a" :open (lambda () (cl-incf opened)))
      (agent-ui-section canvas "b")
      (with-current-buffer canvas
        (agent-ui--flush)
        (goto-char (point-min))
        (should (equal (key-binding (kbd "RET")) #'agent-ui-section-open))
        (should (string-match-p "RET: open what it shows" (get-text-property (point) 'help-echo)))
        (agent-ui-section-open)
        (should (= opened 1))
        (should-not (plist-get (car (agent-ui-sections canvas)) :folded))
        (search-forward "▾ b")
        (agent-ui-section-open)
        (should (plist-get (cadr (agent-ui-sections canvas)) :folded))))))

(ert-deftest agent-ui-sections/closing-with-one-element ()
  "A canvas closing with one of its elements (`agent-ui-closes-with'): its
countdown says closing, sections there or not; over, the canvas cleared,
killed."
  (+test-aus
    (agent-ui-section canvas "run")
    (agent-ui-show '(:id "jobs" :type "steps" :close t :steps ((:name "a" :status "done"))) :canvas canvas :section "run")
    (agent-ui-show '(:id "done" :type "steps" :close t :steps ((:name "b" :status "done"))) :canvas canvas)
    (with-current-buffer canvas
      (setq-local agent-ui-closes-with "run/jobs")
      (agent-ui--finished-check)
      (should (equal (agent-ui--closing-footer "run/jobs" 60)
                     (concat "✓ All done, closing in 10s   ⏵ Keep")))
      (should (string-prefix-p "✓ All done, removed in" (substring-no-properties (agent-ui--closing-footer "done" 60)))))
    (agent-ui--close-finished canvas '("run/jobs"))
    (should-not (buffer-live-p canvas))))
