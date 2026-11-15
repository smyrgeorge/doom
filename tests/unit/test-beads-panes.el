;;; tests/unit/test-beads-panes.el -*- lexical-binding: t; -*-
;; config/beads.el: the list and its issues in panes, the preview, tiling; keys
;; over Vim's; the theme's colours (shared: tests/helper-beads.el).

(load (expand-file-name "../helper-beads" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== PANES ======

(ert-deftest beads/the-list-and-issues-in-panes ()
  "Tiling's applications: SPC o i, a new pane (its own, shown already); an
issue, a new pane, the next one in it (not the list's preview's)."
  (+test-beads-with-project
    (let ((this-command 'test)
          (+my/tiling-strategy 'tall)
          (+my/focus-new-windows t)
          (first (+test-beads--create "First"))
          (second (+test-beads--create "Second"))
          (file (+test-buffer "notes.txt" "Notes\n")))
      (switch-to-buffer file)
      (+my/beads-project)
      (should (= (length (+my/tiling--panes)) 2))
      (should (eq (window-buffer (car (+my/tiling--panes))) file))
      (let ((list-window (selected-window)))
        (should (with-current-buffer (window-buffer list-window) (derived-mode-p 'beads-list-mode)))
        ;; Again, from the file: its pane.
        (select-window (car (+my/tiling--panes)))
        (+my/beads-project)
        (should (= (length (+my/tiling--panes)) 2))
        (should (eq (selected-window) list-window))
        ;; An issue: a new pane; the next one: that pane.
        (beads-detail-open (beads-client-show first))
        (should (= (length (+my/tiling--panes)) 3))
        (let ((issue-window (selected-window)))
          (should (string-match-p first (buffer-name (window-buffer issue-window))))
          ;; Not in the list's pane's history (drawn there, not shown).
          (should-not (seq-find (lambda (entry) (string-match-p "Beads Detail" (buffer-name (car entry))))
                                (window-prev-buffers list-window)))
          (select-window list-window)
          (beads-detail-open (beads-client-show second))
          (should (= (length (+my/tiling--panes)) 3))
          (should (eq (selected-window) issue-window))
          (should (string-match-p second (buffer-name (window-buffer issue-window)))))))))

;; doom-o5t.10
(ert-deftest beads/bd-the-preview-beside-its-list ()
  "P in a list in a 40-column pane, another pane beside it: the preview opens
next to the list, its room taken from the other pane (the list kept at 40);
each row asked of bd in the background (a row doesn't wait for it, one moved
over before its answer came is dropped); the list's own (its project's
folder); gone with the list. beads.el's: on the frame's right edge, 40% of
it, the list squeezed to 21; bd waited for on each row; left behind."
  (+test-beads-with-project
    (let ((first (+test-beads--create "First"))
          (second (+test-beads--create "Second" :priority 0))
          (slow (+test-beads--slow-bd 1)))
      (+my/beads-project)
      (let* ((list (+test-beads--list))
             (window (get-buffer-window list))
             (other (progn (delete-other-windows window)
                           (split-window window nil 'right)))
             (goto (lambda (id) (goto-char (point-min)) (search-forward id) (beginning-of-line))))
        (set-window-buffer other (get-buffer-create "*scratch*"))
        (+test-beads--width window 40)
        (select-window window)
        (with-current-buffer list
          (funcall goto first)
          (beads-preview-mode 1)
          (should-not (get-buffer-window "*Beads Preview*"))
          ;; As its timer does once the cursor stops: bd not waited for.
          (cl-letf (((symbol-function 'beads-backend-cli-program-path) (lambda (&rest _) slow)))
            (let ((start (float-time)))
              (+my/beads--preview-issue list (beads-list--get-issue-at-point))
              (should (< (- (float-time) start) 0.5)))
            (let ((preview +my/beads--preview))
              (should (buffer-local-value '+my/beads--fetching preview))
              ;; Another row before its answer came: that one dropped.
              (funcall goto second)
              (+my/beads--preview-issue list (beads-list--get-issue-at-point))
              (+test-beads--settle preview)))
          (let* ((preview +my/beads--preview)
                 (shown (get-buffer-window preview)))
            (should (equal (buffer-name preview)
                           (replace-regexp-in-string "\\`\\*Beads: " "*Beads Preview: " (buffer-name list))))
            (should (equal (buffer-local-value 'default-directory preview) repo))
            (should (equal (buffer-local-value 'beads-detail--current-issue-id preview) second))
            (should (string-match-p "Second" (+test-beads--text preview)))
            (should shown)
            (should (= (window-body-width window) 40))
            (should (eq (window-in-direction 'right window) shown))
            (should (eq (window-in-direction 'right shown) other))
            ;; An issue opened from the list: in a pane of its own, not the
            ;; preview's (tiling lays the panes out again: the preview one).
            (beads-list-goto-issue)
            (setq shown (get-buffer-window preview))
            (should shown)
            (should-not (eq (selected-window) shown))
            (should (string-match-p "Beads Detail" (buffer-name (window-buffer (selected-window)))))
            ;; The list killed: its preview gone.
            (kill-buffer list)
            (should-not (buffer-live-p preview))
            (should-not (window-live-p shown))))))))

(ert-deftest beads/issues-are-tiling-s-applications ()
  (dolist (mode '(beads-list-mode beads-detail-mode beads-detail-vui-mode))
    (should (seq-find (lambda (app) (eq (if (consp app) (car app) app) mode)) (+my/tiling--apps))))
  ;; A list's preview (config/beads/preview.el's), beads.el's own: where they
  ;; ask; an issue: a new pane.
  (dolist (case '(("*Beads Preview: doom*" . nil) ("*Beads Preview*" . nil)
                  ("*Beads Detail: doom-1*" . t)))
    (with-temp-buffer
      (rename-buffer (car case) t)
      (should (equal (buffer-name) (car case)))
      (should (eq (and (+my/tiling-beads-issue-new-pane-p) t) (cdr case))))))

(ert-deftest beads/a-preview-shown-where-it-asks ()
  "A list's preview shown through `display-buffer' (beads.el's own: a side
window on the right): there, not in a new pane as an issue is."
  (+test-with-reset
    (let ((this-command 'test)
          (+my/tiling-apps 'all))
      (dolist (name '("*Beads Preview: doom*" "*Beads Preview*"))
        (let ((preview (get-buffer-create name)))
          (unwind-protect
              (progn
                (with-current-buffer preview (beads-detail-mode))
                (let ((window (display-buffer preview '((display-buffer-in-side-window)
                                                        (side . right) (window-width . 0.4)))))
                  (should (eq (window-parameter window 'window-side) 'right))
                  (should (= (length (+my/tiling--panes)) 1))))
            (kill-buffer preview))))
      (let ((issue (get-buffer-create "*Beads Detail: doom-1*")))
        (unwind-protect
            (progn
              (with-current-buffer issue (beads-detail-mode))
              (let ((window (display-buffer issue '((display-buffer-in-side-window) (side . right)))))
                (should-not (window-parameter window 'window-side))
                (should (= (length (+my/tiling--panes)) 2))))
          (kill-buffer issue))))))

;; ====== EVIL ======

(ert-deftest beads/keys-over-vim-s ()
  "In the list, normal state: its letters, gr refreshing; Vim's gg; j and k
from row to row (a title on several lines one)."
  (with-temp-buffer
    (beads-list-mode)
    (evil-normal-state)
    (should (eq (key-binding "es") #'beads-list-edit-status))
    (should (eq (key-binding "et") #'beads-list-edit-title))
    (should (eq (key-binding "f") (lookup-key beads-list-mode-map "f")))
    (should (eq (key-binding "P") #'beads-preview-mode))
    (should (eq (key-binding "gr") #'beads-list-refresh))
    (should (eq (key-binding "gg") #'evil-goto-first-line))
    (should (eq (key-binding "j") #'+my/beads-next-row))
    (should (eq (key-binding "k") #'+my/beads-previous-row))
    (should (eq (key-binding (kbd "RET")) #'beads-list-goto-issue))
    ;; Not what it inherits: SPC (Doom's leader) and h stay Vim's.
    (should-not (eq (key-binding " ") #'scroll-up-command))
    (should (eq (key-binding "h") #'evil-backward-char))))

(ert-deftest beads/an-issue-closed-for-good ()
  "q in an issue's buffer kills it (beads.el's quit-window only hid it), in
Vim's normal state and Emacs's; the list's q is its own (filters cleared
first) (doom-gcg)."
  (require 'beads-detail)
  (dolist (mode '(beads-detail-mode beads-detail-vui-mode))
    (let ((buffer (generate-new-buffer "*beads issue*")))
      (save-window-excursion
        (switch-to-buffer buffer)
        (funcall mode)
        (evil-normal-state)
        (should (eq (key-binding "q") #'kill-current-buffer))
        (evil-emacs-state)
        (should (eq (key-binding "q") #'kill-current-buffer))
        (evil-normal-state)
        ;; Pressed, as in its window.
        (execute-kbd-macro "q"))
      (should-not (buffer-live-p buffer))))
  (with-temp-buffer
    (beads-list-mode)
    (evil-normal-state)
    (should (eq (key-binding "q") #'beads-list-quit))))

(ert-deftest beads/forms-typed-into ()
  "beads.el's own: its forms in Emacs's state."
  (require 'beads-form)
  (should (eq (evil-initial-state 'beads-form-mode) 'emacs))
  (should (eq (evil-initial-state 'beads-form-vui-mode) 'emacs)))

;; ====== THE THEME'S COLOURS ======

(ert-deftest beads/faces-the-theme-s ()
  "No colour names: each face inherits the theme's; P0 rows tinted with its red."
  (+my/beads-faces)
  (pcase-dolist (`(,face . ,theme-face) +my/beads--faces)
    (should (eq (face-attribute face :inherit) theme-face))
    (should (eq (face-attribute face :foreground) 'unspecified)))
  ;; Each of beads.el's faces with a colour name is in the list.
  (dolist (face (face-list))
    (when (string-prefix-p "beads-" (symbol-name face))
      (let ((foreground (face-attribute face :foreground)))
        (should (or (eq foreground 'unspecified) (assq face +my/beads--faces))))))
  (should (memq #'+my/beads-faces doom-load-theme-hook)))

(ert-deftest beads/p0-row-tinted ()
  (cl-letf* ((face-background (symbol-function 'face-background))
             (face-foreground (symbol-function 'face-foreground))
             ((symbol-function 'face-background)
              (lambda (face &rest args) (if (eq face 'default) "#000000" (apply face-background face args))))
             ((symbol-function 'face-foreground)
              (lambda (face &rest args) (if (eq face 'error) "#ff0000" (apply face-foreground face args)))))
    (+my/beads-faces)
    (should (equal (face-attribute 'beads-list-row-p0 :background) (doom-blend "#ff0000" "#000000" 0.15)))
    (should (eq (face-attribute 'beads-list-row-p0 :extend) t))))
