;;; tests/e2e/test-agent-shell.el -*- lexical-binding: t; -*-
;; config/agent-shell.el in a GUI Emacs: an image in a reply of Claude Code's,
;; streamed as agent-shell streams it (indented by its line-prefix), as wide
;; as the window beside that indent at most, at any width and after a resize.
;; A stand-in session (agent-shell's mode, no agent).

(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's)
(+test-load "config/window" "config/agent-shell")
(require 'agent-shell)

;; ====== HELPERS ======

(defun +test-agent-shell--session ()
  "A stand-in Claude Code session: agent-shell's mode's buffer, kept aligned
to its window as agent-shell keeps it."
  (let ((buffer (generate-new-buffer "*claude-code @ test*")))
    (with-current-buffer buffer
      (setq-local major-mode 'agent-shell-mode)
      (agent-shell--enable-realign))
    buffer))

(defun +test-agent-shell--stream (chunk &optional create-new)
  "CHUNK streamed into the current buffer as agent-shell streams a reply: its
fragment appended to (a new one with CREATE-NEW), its body rendered."
  (let ((inhibit-read-only t))
    (when-let* ((range (agent-shell-ui-update-fragment
                        (agent-shell-ui-make-fragment-model
                         :namespace-id "1" :block-id "1-agent_message_chunk" :body chunk)
                        :append t :create-new create-new :navigation 'never :no-undo t))
                (start (map-nested-elt range '(:body :start)))
                (end (map-nested-elt range '(:body :end))))
      (save-restriction
        (narrow-to-region start end)
        (agent-shell--render-markdown :complete t)))))

(defun +test-agent-shell--show-at (buffer columns)
  "BUFFER in a new window COLUMNS wide, selected; another window beside it."
  (delete-other-windows)
  (switch-to-buffer (get-buffer-create "*other*"))
  (let ((window (split-window nil (- columns) 'right)))
    (set-window-buffer window buffer)
    (select-window window)
    window))

(defun +test-agent-shell--image (buffer)
  "BUFFER's image: (START . END), or nil."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-min))
      (when-let* ((match (text-property-search-forward
                          'display nil (lambda (_ value) (eq (car-safe value) 'image)))))
        (cons (prop-match-beginning match) (prop-match-end match))))))

(defun +test-agent-shell--fits (buffer)
  "Non-nil if BUFFER's image, drawn after the reply's indent, ends inside its
window's body: where it starts (found on the screen, a point of its row) plus
its width at most the body's width. Said either way."
  (+test-sleep 0.3)
  (pcase-let* ((window (get-buffer-window buffer))
               (`(,start . ,_) (+test-agent-shell--image buffer))
               (image (with-current-buffer buffer (get-text-property start 'display)))
               (width (car (image-size image t (window-frame window))))
               (body (window-body-width window t))
               (y (1+ (cdr (posn-x-y (posn-at-point start window)))))
               (posn (posn-at-x-y (/ body 2) y window))
               (left (and (posn-image posn) (- (/ body 2) (car (posn-object-x-y posn))))))
    (message "%d columns: image %d px wide from x=%S, body %d px"
             (window-total-width window) width left body)
    (and (> width 0) left (> left 0) (<= (+ left width) body))))

;; ====== IMAGES IN REPLIES ======

(ert-deftest e2e-agent-shell/an-image-beside-the-reply-s-indent ()
  "A wide image in a reply: drawn after the reply's indent, it ends inside the
window, at 100, 60, 40 and 25 columns, and resized from 25 to 80 and 30."
  (let ((file (expand-file-name "wide.svg" (make-temp-file (+test-tmp-file "images-") t)))
        (buffer (+test-agent-shell--session)))
    (with-temp-file file
      (insert "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"3000\" height=\"200\">"
              "<rect width=\"3000\" height=\"200\" fill=\"#51afef\"/></svg>"))
    (unwind-protect
        (progn
          (+test-agent-shell--show-at buffer 100)
          (with-current-buffer buffer
            (+test-agent-shell--stream (format "Here:\n\n![wide](%s)\n\nDone.\n" file) t))
          (should (+test-agent-shell--image buffer))
          (with-current-buffer buffer
            (should (equal (get-text-property (car (+test-agent-shell--image buffer)) 'line-prefix) "  ")))
          (should (+test-agent-shell--fits buffer))
          (dolist (columns '(60 40 25))
            (+test-agent-shell--show-at buffer columns)
            (should (+test-agent-shell--fits buffer)))
          (let ((window (get-buffer-window buffer)))
            (dolist (columns '(80 30))
              (window-resize window (- columns (window-total-width window)) t)
              (should (+test-agent-shell--fits buffer)))))
      (let ((kill-buffer-query-functions nil))
        (kill-buffer buffer)))))
