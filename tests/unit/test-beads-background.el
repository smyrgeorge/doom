;;; tests/unit/test-beads-background.el -*- lexical-binding: t; -*-
;; config/beads.el: the place kept across a refresh, refreshes in the background
;; (never waiting for bd, never twice at once, failing quietly) (shared:
;; tests/helper-beads.el).
;; run.sh: slow (~75 s: the real bd, slowed down).

(load (expand-file-name "../helper-beads" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== THE PLACE KEPT ======

(defun +test-beads--ids-at (window)
  "The issues at WINDOW's top and at its cursor: (TOP . CURSOR)."
  (with-current-buffer (window-buffer window)
    (let ((start (window-start window))
          (point (window-point window)))
      (save-excursion
        (cons (progn (goto-char start) (tabulated-list-get-id))
              (progn (goto-char point) (tabulated-list-get-id)))))))

(defun +test-beads--scroll (window top cursor)
  "WINDOW scrolled to its list's TOP-th row, its cursor on the CURSOR-th."
  (with-current-buffer (window-buffer window)
    (save-excursion
      (goto-char (point-min))
      (forward-line (1- top))
      (set-window-start window (point)))
    (set-window-point window (save-excursion (goto-char (point-min)) (forward-line (1- cursor)) (point)))))

(ert-deftest beads/bd-a-refresh-keeps-the-place ()
  "A list scrolled down, its cursor on an issue; a P0 added (listed first: the
rows under it a line lower): refreshed by gr, by the timer from another
pane, shown in two windows: each keeps the same issue at its top and at its
cursor."
  (+test-beads-with-project
    (+test-beads--bulk 40 0)
    (+my/beads-project)
    (let* ((list (+test-beads--list))
           (window (get-buffer-window list)))
      (+test-beads--scroll window 20 25)
      (let ((place (+test-beads--ids-at window)))
        (should (car place))
        (should-not (equal (car place) (cdr place)))
        ;; gr, in the list's window.
        (+test-beads--create "Urgent" :priority 0)
        (with-selected-window window (beads-list-refresh t))
        (should (string-match-p "Urgent" (+test-beads--line "Urgent")))
        (should (equal (+test-beads--ids-at window) place))
        ;; The timer's, in the background, from another pane scrolled elsewhere.
        (let ((other (split-window window nil 'left)))
          (set-window-buffer other (get-buffer-create "*scratch*"))
          (with-current-buffer "*scratch*" (insert (make-string 400 ?\n)))
          (set-window-start other 200)
          (select-window other)
          (+test-beads--create "Urgent too" :priority 0)
          (with-current-buffer list (beads-autoupdate--refresh))
          (+test-beads--settle list)
          (with-current-buffer list (should (+test-beads--line "Urgent too")))
          (should (eq (selected-window) other))
          (should (equal (+test-beads--ids-at window) place))
          ;; Two windows on the list, each its own place.
          (set-window-buffer other list)
          (+test-beads--scroll other 5 8)
          (let ((other-place (+test-beads--ids-at other)))
            (+test-beads--create "Urgent three" :priority 0)
            (with-selected-window window (beads-list-refresh t))
            (should (equal (+test-beads--ids-at window) place))
            (should (equal (+test-beads--ids-at other) other-place))))))))

;; ====== IN THE BACKGROUND ======

(ert-deftest beads/the-timer-s-refresh-doesn-t-wait-for-bd ()
  "beads-autoupdate's refresh, bd taking 2 s: returns at once; the list
redrawn once bd answered, with what bd added meanwhile (its bar too)."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list))
          (slow (+test-beads--slow-bd 2)))
      (should (get-buffer-window list 'visible))
      (+test-beads--run "bd" "create" "Added by Claude" "--quiet")
      (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) slow)))
        (with-current-buffer list
          (let ((start (float-time)))
            (beads-autoupdate--refresh)
            (should (< (- (float-time) start) 1)))
          (should +my/beads--fetching)
          (should-not (string-match-p "Added by Claude" (+test-beads--text list)))
          (should (string-match-p "1 total" (+test-beads--bar))))
        (+test-beads--settle list))
      (should (string-match-p "Added by Claude" (+test-beads--text list)))
      (with-current-buffer list
        (should (string-match-p "2 total" (+test-beads--bar)))))))

(ert-deftest beads/a-refresh-on-its-way-not-started-again ()
  "Asked again while on its way: the same one; gr meanwhile: waited for, and
the one on its way cancelled (its older answer never drawn)."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list))
          (slow (+test-beads--slow-bd 2))
          drawn)
      (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) slow)))
        (with-current-buffer list
          (+my/beads-refresh-async list)
          (let ((fetching +my/beads--fetching))
            (should (= (length (cdr fetching)) 2)) ; bd list, bd stats
            (+my/beads-refresh-async list)
            (should (eq +my/beads--fetching fetching))
            ;; gr: bd asked and waited for (the real one), the other cancelled.
            (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) (executable-find "bd"))))
              (+test-beads--run "bd" "create" "Second" "--quiet")
              (beads-list-refresh t))
            (should-not +my/beads--fetching)
            (dolist (process (cdr fetching))
              (should (process-get process 'cancelled))
              (should-not (process-live-p process)))
            (should (string-match-p "Second" (+test-beads--text list))))))
      (cl-letf (((symbol-function '+my/beads--redraw) (lambda (&rest args) (push args drawn))))
        (accept-process-output nil 0.3))
      (should-not drawn))))

(ert-deftest beads/not-shown-not-refreshed-until-shown ()
  "A list in no window: no bd run, marked; shown again: refreshed."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list)))
      (should (memq #'+my/beads--shown-h (buffer-local-value 'window-buffer-change-functions list)))
      (dolist (window (get-buffer-window-list list nil t))
        (set-window-buffer window (get-buffer-create "*scratch*")))
      (should-not (get-buffer-window list 'visible))
      (+test-beads--run "bd" "create" "While hidden" "--quiet")
      (with-current-buffer list
        (cl-letf (((symbol-function 'make-process) (lambda (&rest _) (error "bd run"))))
          (beads-autoupdate--refresh))
        (should-not +my/beads--fetching)
        (should +my/beads--stale))
      ;; Shown (batch Emacs runs no window change functions: called as
      ;; redisplay calls them).
      (set-window-buffer (selected-window) list)
      (with-current-buffer list
        (+my/beads--shown-h (selected-window))
        (should +my/beads--fetching)
        (should-not +my/beads--stale))
      (+test-beads--settle list)
      (should (string-match-p "While hidden" (+test-beads--text list))))))

(ert-deftest beads/an-issue-refreshed-in-the-background ()
  "An issue's buffer (Claude's bd commands refresh it): bd show not waited
for, the issue redrawn with bd's answer."
  (+test-beads-with-project
    (let ((id (+test-beads--create "Old title")))
      (beads-detail-open (beads-client-show id))
      (let ((detail (get-buffer (format "*Beads Detail: %s*" id))))
        (should (get-buffer-window detail 'visible))
        (+test-beads--run "bd" "update" id "--title" "New title" "--quiet")
        (+my/beads-refresh-async detail t)
        (should (buffer-local-value '+my/beads--fetching detail))
        (should (string-match-p "Old title" (+test-beads--text detail)))
        (+test-beads--settle detail)
        (should (string-match-p "New title" (+test-beads--text detail)))))))

(ert-deftest beads/bd-failing-in-the-background ()
  "bd failing: said as beads.el says it, the list as it was, nothing on its way."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list))
          (failing (+test-beads--slow-bd 0 3))
          messages)
      (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) failing))
                ((symbol-function 'message)
                 (lambda (format &rest args) (push (apply #'format-message format args) messages))))
        (+my/beads-refresh-async list)
        (+test-beads--settle list))
      (should (seq-find (lambda (m) (string-match-p "Failed to fetch issues: .*bd broke" m)) messages))
      (should (string-match-p "First" (+test-beads--text list))))))

;; doom-o5t.13
(ert-deftest beads/no-bd-in-the-background ()
  "bd not found: a refresh in the background leaves nothing behind (its
processes, its buffers), signals nothing (beads-autoupdate's timer runs it),
keeps the list as it was, and says so once; bd back, it refreshes again."
  (+test-beads-with-project
    (+test-beads--create "First")
    (+my/beads-project)
    (let ((list (+test-beads--list))
          (processes (length (process-list)))
          (buffers (length (buffer-list)))
          messages)
      (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) "/nonexistent/bd"))
                ((symbol-function 'message)
                 (lambda (format &rest args) (when format (push (apply #'format-message format args) messages)))))
        (dotimes (_ 3)
          (with-current-buffer list
            (beads-autoupdate--refresh))))
      (should (= (length (process-list)) processes))
      (should (= (length (buffer-list)) buffers))
      (should-not (buffer-local-value '+my/beads--fetching list))
      (should (= (seq-count (lambda (m) (string-match-p "Failed to fetch issues: /nonexistent/bd not found" m)) messages) 1))
      (should (string-match-p "First" (+test-beads--text list)))
      (+test-beads--run "bd" "create" "Second" "--quiet")
      (+my/beads-refresh-async list)
      (+test-beads--settle list)
      (should (string-match-p "Second" (+test-beads--text list))))))

(ert-deftest beads/background-refresh-wired ()
  (should (advice-member-p #'+my/beads-autoupdate-a 'beads-autoupdate--refresh))
  (should (advice-member-p #'+my/beads-refresh-lists-a 'beads-detail--refresh-list-buffers))
  (should (advice-member-p #'+my/beads-cancel-a 'beads-list-refresh))
  (should (advice-member-p #'+my/beads-cancel-a 'beads-detail-refresh)))

(ert-deftest beads/bd-an-issue-knows-its-issue ()
  "An issue opened (vui's view, beads.el's default): it keeps which issue it
shows, so gr refreshes it."
  (+test-beads-with-project
    (let ((id (+test-beads--create "Old title")))
      (beads-detail-open (beads-client-show id))
      (with-current-buffer (format "*Beads Detail: %s*" id)
        (should (derived-mode-p 'beads-detail-vui-mode))
        (should (equal beads-detail--current-issue-id id))
        (should (equal (alist-get 'id beads-detail--current-issue) id))
        (+test-beads--run "bd" "update" id "--title" "New title" "--quiet")
        (beads-detail-refresh)
        (should (string-match-p "New title" (+test-beads--text (current-buffer))))))))
