;;; $DOOMDIR/config/webkit/input.el -*- lexical-binding: t; -*-
;; The pointer, clicks, scrolling and copying. Loaded from config/webkit.el.

;; POINTER
;; Emacs draws its own mouse pointer over a view, the text I-beam everywhere,
;; so a page's CSS cursors never show (WebKit's hand over a link). A page that
;; says which one it wants (in its title, see WATCHING in js.el) gets it from
;; its watch function with `+my/webkit-pointer': into the `pointer' text
;; property under the views, which Emacs's pointer follows after the redisplay
;; that brings.

(defvar-local +my/webkit--pointer nil
  "The pointer shape the buffer's text has (see POINTER).")

(defun +my/webkit-pointer (window shape)
  "The mouse pointer SHAPE (`hand', `text', `arrow') over WINDOW's view, if
the mouse is over it (see above)."
  (when (and (eq window +my/webkit--under)
             (not (eq shape +my/webkit--pointer)))
    (setq +my/webkit--pointer shape)
    (with-silent-modifications
      (put-text-property (point-min) (point-max) 'pointer shape))))

;; CLICKS
(defun +my/webkit-mouse-select (event)
  "A click on a page: select its window (the click itself is WebKit's)."
  (interactive "e")
  (let ((window (posn-window (event-start event))))
    (when (window-live-p window)
      (select-window window))))

(defun +my/webkit-bind-clicks (map)
  "In MAP, clicks are WebKit's (selecting text, links): Emacs only selects the
window, instead of starting a selection of its own (Evil's visual state, where
the page's keys don't apply)."
  (let ((keys '(([down-mouse-1] . +my/webkit-mouse-select)
                ([mouse-1] . ignore)
                ([drag-mouse-1] . ignore)
                ([double-down-mouse-1] . ignore)
                ([double-mouse-1] . ignore)
                ([triple-down-mouse-1] . ignore)
                ([triple-mouse-1] . ignore))))
    (pcase-dolist (`(,key . ,command) keys)
      (define-key map key command))
    (with-eval-after-load 'evil
      (pcase-dolist (`(,key . ,command) keys)
        (evil-define-key* '(normal motion visual) map key command)))))

;; COMMANDS
;; For pages with no keys of their own (a mode binds them): j / k, C-d / C-u,
;; C-f / C-b, gg / G scroll the selected window's view; y / Cmd+C copy its
;; selected text (`+my/webkit-selection-script').
(defun +my/webkit-scroll-down (&optional count)
  "j: scroll the page down."
  (interactive "p")
  (+my/webkit-execute (format "window.scrollBy(0, %d)" (* (or count 1) +my/webkit-scroll-step))))

(defun +my/webkit-scroll-up (&optional count)
  "k: scroll the page up."
  (interactive "p")
  (+my/webkit-execute (format "window.scrollBy(0, %d)" (- (* (or count 1) +my/webkit-scroll-step)))))

(defun +my/webkit-half-screen-down ()
  "C-d: half a screen down."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, innerHeight / 2)"))

(defun +my/webkit-half-screen-up ()
  "C-u: half a screen up."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, -innerHeight / 2)"))

(defun +my/webkit-screen-down ()
  "C-f: a screen down."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, innerHeight * 0.9)"))

(defun +my/webkit-screen-up ()
  "C-b: a screen up."
  (interactive)
  (+my/webkit-execute "window.scrollBy(0, -innerHeight * 0.9)"))

(defun +my/webkit-top ()
  "gg: the page's top."
  (interactive)
  (+my/webkit-execute "window.scrollTo(0, 0)"))

(defun +my/webkit-bottom ()
  "G: the page's bottom."
  (interactive)
  (+my/webkit-execute "window.scrollTo(0, document.documentElement.scrollHeight)"))

(defun +my/webkit-copied (text)
  "Put TEXT, a page's selection, in the kill ring (and the clipboard)."
  (if (and (stringp text) (not (string-blank-p text)))
      (progn (kill-new text)
             (message "Copied %d characters" (length text)))
    (message "No text selected")))

(defun +my/webkit-copy ()
  "y / Cmd+C: copy the text selected in the page (an answer awaited, see
JAVASCRIPT)."
  (interactive)
  (+my/webkit-ask +my/webkit-selection-script #'+my/webkit-copied))
