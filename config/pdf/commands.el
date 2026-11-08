;;; $DOOMDIR/config/pdf/commands.el -*- lexical-binding: t; -*-
;; Scrolling, pages, search, zoom, toggles, print. Loaded from config/pdf.el.

;; COMMANDS (see config/pdf.el)

(defvar-local +my/pdf--searching nil
  "Non-nil while a search shows its matches (Esc ends it).")

(defvar +my/pdf--search-history nil)

(defun +my/pdf--scroll (dx dy)
  (+my/pdf--js (format "scroll(%d, %d)" dx dy)))

(defun +my/pdf-scroll-down (&optional count)
  "j: scroll the PDF down."
  (interactive "p")
  (+my/pdf--scroll 0 (* (or count 1) +my/pdf-scroll-step)))

(defun +my/pdf-scroll-up (&optional count)
  "k: scroll the PDF up."
  (interactive "p")
  (+my/pdf--scroll 0 (- (* (or count 1) +my/pdf-scroll-step))))

(defun +my/pdf-scroll-right (&optional count)
  "l: scroll the PDF right (zoomed in)."
  (interactive "p")
  (+my/pdf--scroll (* (or count 1) +my/pdf-scroll-step) 0))

(defun +my/pdf-scroll-left (&optional count)
  "h: scroll the PDF left (zoomed in)."
  (interactive "p")
  (+my/pdf--scroll (- (* (or count 1) +my/pdf-scroll-step)) 0))

(defun +my/pdf-half-screen-down ()
  "C-d: scroll the PDF down half a screen."
  (interactive)
  (+my/pdf--js "screen(0.5)"))

(defun +my/pdf-half-screen-up ()
  "C-u: scroll the PDF up half a screen."
  (interactive)
  (+my/pdf--js "screen(-0.5)"))

(defun +my/pdf-screen-down ()
  "C-f: scroll the PDF down a screen (a bit less, to keep your place)."
  (interactive)
  (+my/pdf--js "screen(0.9)"))

(defun +my/pdf-screen-up ()
  "C-b: scroll the PDF up a screen (a bit less, to keep your place)."
  (interactive)
  (+my/pdf--js "screen(-0.9)"))

(defun +my/pdf-top (&optional page)
  "gg: the PDF's start; with a count, that page."
  (interactive "P")
  (+my/pdf--js (if page
                           (format "goto(%d)" (prefix-numeric-value page))
                         "top()")))

(defun +my/pdf-bottom (&optional page)
  "G: the PDF's end; with a count, that page."
  (interactive "P")
  (+my/pdf--js (if page
                           (format "goto(%d)" (prefix-numeric-value page))
                         "bottom()")))

(defun +my/pdf-next-page (&optional count)
  "J: the next page."
  (interactive "p")
  (+my/pdf--js (format "page(%d)" (or count 1))))

(defun +my/pdf-previous-page (&optional count)
  "K: the previous page."
  (interactive "p")
  (+my/pdf--js (format "page(%d)" (- (or count 1)))))

(defun +my/pdf-back ()
  "C-o / Cmd+[ (Linux: Alt+←): back to where the last jump left from (see
config/pdf.el)."
  (interactive)
  (+my/pdf--js "back()"))

(defun +my/pdf-forward ()
  "C-i / Cmd+] (Linux: Alt+→): forward again, after going back (see
config/pdf.el)."
  (interactive)
  (+my/pdf--js "forward()"))

(defun +my/pdf--find (query &optional backward)
  "Search the PDF for QUERY (its spaces and line breaks as single spaces);
BACKWARD towards its start. An empty QUERY ends the search."
  (require 'json)
  (let ((query (string-trim (replace-regexp-in-string "[ \t\n\r]+" " " query))))
    (setq +my/pdf--searching (not (string-empty-p query)))
    (+my/pdf--js (format "find(%s, %s)" (json-encode query)
                                 (if backward "true" "false")))))

(defun +my/pdf-search (&optional backward)
  "/: search the PDF (case-sensitive with a capital), from where it shows;
BACKWARD (?) towards its start. Esc ends the search."
  (interactive)
  (+my/pdf--find (read-string (if backward "Search backward: " "Search: ")
                                      nil '+my/pdf--search-history)
                         backward))

(defun +my/pdf-search-backward ()
  "?: search the PDF towards its start (see `+my/pdf-search')."
  (interactive)
  (+my/pdf-search t))

(defun +my/pdf-search-next ()
  "n: the search's next match."
  (interactive)
  (+my/pdf--js "again(false)"))

(defun +my/pdf-search-previous ()
  "N: the search's previous match."
  (interactive)
  (+my/pdf--js "again(true)"))

(defun +my/pdf--escape-h ()
  "Esc in a PDF ends its search (highlights and count)."
  (when (and (derived-mode-p '+my/pdf-mode) +my/pdf--searching)
    (setq +my/pdf--searching nil)
    (+my/pdf--js "endFind()" t)
    t))

(add-hook 'doom-escape-hook #'+my/pdf--escape-h)

(defun +my/pdf--toggle (setting name was)
  "Turn the page's SETTING (\"dark\", \"toolbar\", \"sidebar\") on or off,
as the selected window's is, in all of the PDF's views (see VIEWS), and say so,
NAME being what it is; return whether it's on, WAS (as it was for the next PDF)
if it can't."
  (if (or (not (+my/webkit-xwidget)) +my/pdf--native)
      (progn (message "No PDF.js here: M-x +my/pdf-js-install, then open the PDF again")
             was)
    (let ((on (not (plist-get (+my/pdf--state) (intern (concat ":" setting))))))
      (+my/pdf--js (format "set({%s: %s})" setting (if on "true" "false")) t)
      (message "%s %s" name (if on "on" "off"))
      on)))

(defun +my/pdf-toggle-dark ()
  "SPC m d: dark pages on or off (see config/pdf.el)."
  (interactive)
  (setq +my/pdf-dark-pages (+my/pdf--toggle "dark" "Dark pages"
                                                             +my/pdf-dark-pages)))

(defun +my/pdf-toggle-toolbar ()
  "SPC m t: the toolbar on or off (see config/pdf.el)."
  (interactive)
  (setq +my/pdf-toolbar (+my/pdf--toggle "toolbar" "Toolbar"
                                                         +my/pdf-toolbar)))

(defun +my/pdf-toggle-sidebar ()
  "O: the sidebar (outline, pages) on or off (see config/pdf.el)."
  (interactive)
  (setq +my/pdf-outline-sidebar (+my/pdf--toggle "sidebar" "Sidebar"
                                                                 +my/pdf-outline-sidebar)))

;; PREVIEW AND PRINT
(defun +my/pdf-open-in-preview ()
  "SPC m p: the PDF in another app: macOS's Preview (to sign, annotate...),
Linux's default app for PDFs (config/os.el)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (+my/os-open (expand-file-name buffer-file-name)))

(defun +my/pdf-print ()
  "Cmd+P (Linux: Ctrl+P): print the PDF: in Preview's print dialog on macOS
(it asks once to let Emacs control Preview), on the default printer on
Linux, after asking (config/os.el)."
  (interactive)
  (unless buffer-file-name
    (user-error "Not a file"))
  (+my/os-print (expand-file-name buffer-file-name)))

(defun +my/pdf-zoom-in ()
  "Cmd+=: zoom the PDF in."
  (interactive)
  (+my/pdf--js (format "zoom(%s)" +my/pdf-zoom-step)))

(defun +my/pdf-zoom-out ()
  "Cmd+-: zoom the PDF out."
  (interactive)
  (+my/pdf--js (format "zoom(%s)" (/ 1.0 +my/pdf-zoom-step))))

(defun +my/pdf-actual-size ()
  "Cmd+0: the PDF at 100%."
  (interactive)
  (+my/pdf--js "fit('page-actual')"))

(defun +my/pdf-fit-width ()
  "W: the PDF as wide as the window (as it opens)."
  (interactive)
  (+my/pdf--js "fit('page-width')"))

(defun +my/pdf-fit-page ()
  "P: a whole page in the window."
  (interactive)
  (+my/pdf--js "fit('page-fit')"))
