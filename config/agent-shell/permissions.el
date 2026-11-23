;;; $DOOMDIR/config/agent-shell/permissions.el -*- lexical-binding: t; -*-
;; A session's permission request answered from elsewhere (an agent
;; workspace's raised hand, a workflow run's pane): agent-shell's own buttons
;; (Allow, Always allow, Reject...), read from its buffer and pressed as they
;; are. Loaded from config/agent-shell.el.

(require 'text-property-search)

(defun +my/agent-shell-permission-buttons (buffer)
  "The permission buttons waiting in agent-shell's session BUFFER, its
latest row: ((LABEL POSITION . ACTION)...), ACTION its own command, run with
point at POSITION."
  (with-current-buffer buffer
    (save-excursion
      (goto-char (point-max))
      (when-let* ((last (text-property-search-backward 'button 'permission t)))
        (let ((start (save-excursion (goto-char (prop-match-beginning last)) (line-beginning-position)))
              (end (save-excursion (goto-char (prop-match-beginning last)) (line-end-position)))
              buttons match)
          (goto-char start)
          (while (and (setq match (text-property-search-forward 'button 'permission t))
                      (< (prop-match-beginning match) end))
            (let* ((from (prop-match-beginning match))
                   (label (string-trim (buffer-substring-no-properties from (prop-match-end match)) "[[ ]+" "[] ]+"))
                   (map (get-text-property from 'keymap))
                   (action (and (keymapp map) (lookup-key map (kbd "RET")))))
              (when (functionp action)
                (push (cons label (cons from action)) buttons))))
          (nreverse buttons))))))

(defun +my/agent-shell-press-permission (buffer label)
  "Press the permission button LABEL waiting in agent-shell's session
BUFFER, as RET on it does. Nil if there's none of that label."
  (when-let* ((button (assoc label (+my/agent-shell-permission-buttons buffer))))
    (with-current-buffer buffer
      (save-excursion
        (goto-char (cadr button))
        (funcall-interactively (cddr button))))
    t))
