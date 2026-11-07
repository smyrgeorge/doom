;;; $DOOMDIR/config/excalidraw/input.el -*- lexical-binding: t; -*-
;; Keys given to the page; copy and paste. Loaded from config/excalidraw.el.

;; KEYS (see config/excalidraw.el)
;; A key typed in Emacs, as the KeyboardEvent a browser gives a page on a US
;; keyboard: the character typed (`key') and the physical key (`code', which
;; Excalidraw reads for some: Shift+1 is "!" on Digit1), and the modifiers
;; (Cmd is `metaKey', Option `altKey').
(defconst +my/excalidraw--shifted
  '((?! . ?1) (?@ . ?2) (?# . ?3) (?$ . ?4) (?% . ?5) (?^ . ?6) (?& . ?7) (?* . ?8)
    (?\( . ?9) (?\) . ?0) (?_ . ?-) (?+ . ?=) (?{ . ?\[) (?} . ?\]) (?| . ?\\)
    (?: . ?\;) (?\" . ?') (?< . ?,) (?> . ?.) (?? . ?/) (?~ . ?`))
  "A character typed with Shift, and the one its key types without.")

(defconst +my/excalidraw--codes
  '((?- . "Minus") (?= . "Equal") (?\[ . "BracketLeft") (?\] . "BracketRight")
    (?\\ . "Backslash") (?\; . "Semicolon") (?' . "Quote") (?, . "Comma")
    (?. . "Period") (?/ . "Slash") (?` . "Backquote"))
  "The code of the key typing a character, but letters and digits.")

(defconst +my/excalidraw--named
  '((return . "Enter") (tab . "Tab") (backtab . "Tab") (escape . "Escape")
    (backspace . "Backspace") (delete . "Delete") (deletechar . "Delete")
    (left . "ArrowLeft") (right . "ArrowRight") (up . "ArrowUp") (down . "ArrowDown"))
  "Function keys, and their name (`key' and `code' both).")

(defun +my/excalidraw--key-init (event)
  "Key EVENT as a KeyboardEvent's properties (JSON), or nil if it's none."
  (let* ((char (and (integerp event) (logand event #x3fffff))) ; no modifier bits
         ;; RET, TAB, ESC, DEL as characters: C-m, C-i... to Emacs.
         (named (pcase char (13 'return) (9 'tab) (27 'escape) (127 'backspace)))
         (modifiers (event-modifiers (if named (logior (- event char) ?a) event)))
         (basic (or named (event-basic-type event)))
         (shift (or (memq 'shift modifiers) (eq basic 'backtab)))
         (key nil)
         (code ""))
    (cond ((symbolp basic)
           (when-let* ((name (alist-get basic +my/excalidraw--named)))
             (setq key name code name)))
          ((not (characterp basic)))
          ((<= ?a basic ?z)
           (setq key (string (if shift (upcase basic) basic))
                 code (format "Key%c" (upcase basic))))
          ((<= ?0 basic ?9)
           (setq key (string basic) code (format "Digit%c" basic)))
          ((assq basic +my/excalidraw--shifted)
           (let ((unshifted (cdr (assq basic +my/excalidraw--shifted))))
             (setq key (string basic)
                   shift t
                   code (if (<= ?0 unshifted ?9)
                            (format "Digit%c" unshifted)
                          (cdr (assq unshifted +my/excalidraw--codes))))))
          (t (setq key (string basic)
                   code (or (cdr (assq basic +my/excalidraw--codes)) ""))))
    (when key
      (+my/excalidraw--json
       (list :key key :code code
             :shiftKey (if shift t :false)
             :metaKey (if (memq 'super modifiers) t :false)
             :altKey (if (memq 'meta modifiers) t :false)
             :ctrlKey (if (memq 'control modifiers) t :false))))))

(defun +my/excalidraw-key ()
  "A key of Excalidraw's: to the drawing in the selected window (see above)."
  (interactive)
  (when-let* ((init (+my/excalidraw--key-init last-command-event)))
    (+my/webkit-execute (format "window.exd && exd.key(%s)" init))))

;; COPY AND PASTE
;; Through Emacs's kill ring (and so the clipboard): WebKit's own clipboard
;; events don't come from Emacs's keys.
(defun +my/excalidraw-copy ()
  "Cmd+C: copy the selection (see above)."
  (interactive)
  (+my/webkit-ask "window.exd ? exd.copy() : ''" #'+my/excalidraw--copied))

(defun +my/excalidraw-cut ()
  "Cmd+X: cut the selection (see above)."
  (interactive)
  (+my/webkit-ask "window.exd ? exd.cut() : ''" #'+my/excalidraw--copied))

(defun +my/excalidraw--copied (text)
  "The selection a page copied, TEXT, in the kill ring."
  (if (and (stringp text) (not (string-empty-p text)))
      (progn (kill-new text)
             (message "Copied the selection"))
    (message "Nothing selected")))

(defun +my/excalidraw-paste ()
  "Cmd+V: paste the kill ring's latest (the clipboard's): shapes copied from
a drawing, or text."
  (interactive)
  (let ((text (ignore-errors (current-kill 0))))
    (if (not (and (stringp text) (not (string-empty-p text))))
        (message "Nothing to paste")
      (+my/webkit-execute (format "window.exd && exd.paste(%s)"
                                  (+my/excalidraw--json (substring-no-properties text)))))))
