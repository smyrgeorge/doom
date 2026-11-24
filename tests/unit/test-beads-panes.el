;;; tests/unit/test-beads-panes.el -*- lexical-binding: t; -*-
;; config/beads.el: the list and its issues in panes (not tiling's), the preview; keys
;; over Vim's; the theme's colours (shared: tests/helper-beads.el).

(load (expand-file-name "../helper-beads" (file-name-directory (or load-file-name buffer-file-name))) nil t)

;; ====== PANES ======

(ert-deftest beads/the-list-and-issues-in-panes ()
  "Not tiling's applications: SPC o i, the current window, always (another
pane showing the list already too); an issue, below the list, the next one
in its window (not the list's preview's)."
  (+test-beads-with-project
    (let ((this-command 'test)
          (+my/tiling-strategy 'tall)
          (+my/focus-new-windows t)
          (first (+test-beads--create "First"))
          (second (+test-beads--create "Second"))
          (file (+test-buffer "notes.txt" "Notes\n")))
      (switch-to-buffer file)
      (let ((here (selected-window)))
        (+my/beads-project)
        (should (eq (selected-window) here))
        (should (= (length (window-list nil 'nomini)) 1))
        (should (with-current-buffer (window-buffer here) (derived-mode-p 'beads-list-mode)))
        (let ((list (window-buffer here)))
          ;; Again, from another pane: that one, the list's left as it is.
          (let ((other (split-window here nil 'right)))
            (set-window-buffer other file)
            (select-window other)
            (+my/beads-project)
            (should (eq (selected-window) other))
            (should (eq (window-buffer other) list))
            (should (eq (window-buffer here) list))
            (delete-window other))
          (select-window here)
          ;; An issue: below the list; the next one: that window.
          (beads-detail-open (beads-client-show first))
          (let ((issue-window (selected-window)))
            (should-not (eq issue-window here))
            (should (eq (window-in-direction 'below here) issue-window))
            (should (eq (window-buffer here) list))
            (should (string-match-p first (buffer-name (window-buffer issue-window))))
            ;; Not in the list's window's history (drawn there, not shown).
            (should-not (seq-find (lambda (entry) (string-match-p "Beads Detail" (buffer-name (car entry))))
                                  (window-prev-buffers here)))
            (select-window here)
            (beads-detail-open (beads-client-show second))
            (should (= (length (window-list nil 'nomini)) 2))
            (should (eq (selected-window) issue-window))
            (should (string-match-p second (buffer-name (window-buffer issue-window))))))))))

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

(ert-deftest beads/issues-aren-t-tiling-s-applications ()
  "Not one of tiling's applications, all of them chosen: a list or an issue
isn't one."
  (let ((+my/tiling-apps 'all))
    (dolist (mode '(beads-list-mode beads-detail-mode beads-detail-vui-mode))
      (should-not (seq-find (lambda (app) (eq (if (consp app) (car app) app) mode)) (+my/tiling--apps)))
      (with-temp-buffer
        (funcall mode)
        (should-not (+my/tiling-app-p (current-buffer)))))))

(ert-deftest beads/a-preview-and-an-issue-shown-where-they-ask ()
  "A list's preview, and an issue, shown through `display-buffer' (beads.el's
preview: a side window on the right): there, not in a new pane."
  (+test-with-reset
    (let ((this-command 'test)
          (+my/tiling-apps 'all))
      (dolist (name '("*Beads Preview: doom*" "*Beads Preview*" "*Beads Detail: doom-1*"))
        (let ((buffer (get-buffer-create name)))
          (unwind-protect
              (progn
                (with-current-buffer buffer (beads-detail-mode))
                (let ((window (display-buffer buffer '((display-buffer-in-side-window)
                                                       (side . right) (window-width . 0.4)))))
                  (should (eq (window-parameter window 'window-side) 'right))
                  (should (= (length (+my/tiling--panes)) 1))))
            (kill-buffer buffer)))))))

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
