;;; $DOOMDIR/config/agent-ui/elements/html.el -*- lexical-binding: t; -*-
;; Agent UI's web page: an HTML file (or a URL) as a card, its title and the
;; start of its text. Loaded from config/agent-ui/elements.el.
;;
;; RET or a click opens it (`agent-ui-open-page-function': a WebKit pane in
;; a graphic Emacs with xwidgets, see config/html.el; else the browser). Its
;; text read from the file (scripts, styles and tags left out), not from the
;; web: a URL's card is its address.

(require 'cl-lib)
(require 'subr-x)

(defcustom agent-ui-open-page-function #'agent-ui-html-browse
  "Opens a page an element shows, given a file's name or a URL."
  :type 'function :group 'agent-ui)

(defcustom agent-ui-html-max-bytes 500000
  "The most of an HTML file read for its card."
  :type 'natnum :group 'agent-ui)

(defun agent-ui-html-browse (page)
  "Open PAGE (a file's name or a URL) in the browser."
  (if (string-match-p "\\`[a-z]+://" page)
      (browse-url page)
    (browse-url-of-file page)))

(defconst agent-ui-html--entities
  '(("nbsp" . " ") ("lt" . "<") ("gt" . ">") ("quot" . "\"") ("apos" . "'") ("amp" . "&")
    ("mdash" . "—") ("ndash" . "–") ("hellip" . "…") ("copy" . "©") ("reg" . "®") ("trade" . "™")
    ("laquo" . "«") ("raquo" . "»") ("lsquo" . "‘") ("rsquo" . "’") ("ldquo" . "“") ("rdquo" . "”")
    ("bull" . "•") ("middot" . "·") ("times" . "×") ("divide" . "÷") ("deg" . "°") ("plusmn" . "±")
    ("euro" . "€") ("pound" . "£") ("yen" . "¥") ("cent" . "¢") ("sect" . "§") ("para" . "¶")
    ("larr" . "←") ("rarr" . "→") ("uarr" . "↑") ("darr" . "↓") ("le" . "≤") ("ge" . "≥") ("ne" . "≠")
    ("check" . "✓") ("shy" . "") ("zwj" . "") ("zwnj" . "") ("thinsp" . " ") ("ensp" . " ") ("emsp" . " "))
  "HTML's common named entities, as text.")

(defun agent-ui-html--entities (text)
  "TEXT with its entities read once (&amp;lt; is &lt;: it was read twice):
&#N;, &#xN; and the common named ones; others as they are."
  (let ((case-fold-search nil))
    (replace-regexp-in-string
     "&\\(?:#\\([0-9]\\{1,7\\}\\)\\|#[xX]\\([0-9a-fA-F]\\{1,6\\}\\)\\|\\([a-zA-Z][a-zA-Z0-9]*\\)\\);"
     (lambda (m)
       (let ((n (cond ((match-string 1 m) (string-to-number (match-string 1 m)))
                      ((match-string 2 m) (string-to-number (match-string 2 m) 16)))))
         (cond (n (if (and (> n 0) (<= n #x10FFFF)) (string n) m))
               ((cdr (assoc (match-string 3 m) agent-ui-html--entities)))
               (t m))))
     text t t)))

(defun agent-ui-html--text-of (html)
  "HTML's title and its text: (TITLE . TEXT), scripts, styles and tags left
out, its entities read, its spaces one."
  (let ((case-fold-search t)
        (title nil))
    (when (string-match "<title[^>]*>\\(\\(?:.\\|\n\\)*?\\)</title>" html)
      (setq title (match-string 1 html)))
    (dolist (re '("<script\\b\\(?:.\\|\n\\)*?</script>" "<style\\b\\(?:.\\|\n\\)*?</style>"
                  "<head\\b\\(?:.\\|\n\\)*?</head>" "<!--\\(?:.\\|\n\\)*?-->"))
      (setq html (replace-regexp-in-string re " " html)))
    ;; Blocks as lines; tags gone.
    (setq html (replace-regexp-in-string "<\\(?:br\\|/p\\|/h[1-6]\\|/li\\|/tr\\|/div\\)\\b[^>]*>" "\n" html))
    (setq html (replace-regexp-in-string "<[^>]*>" " " html))
    ;; Its entities read once; its title on one line (its newlines kept, it
    ;; was two).
    (cl-flet ((spaces (s) (string-trim (replace-regexp-in-string "[ \t\r]+" " " s))))
      (cons (and title (spaces (replace-regexp-in-string "[\n\r]+" " " (agent-ui-html--entities title))))
            (string-join (seq-remove #'string-empty-p
                                     (mapcar #'spaces (split-string (agent-ui-html--entities html) "\n")))
                         "\n")))))

(defun agent-ui-html--text (props ctx)
  (let* ((file (plist-get props :file))
         (page (or file (plist-get props :url)))
         (width (plist-get ctx :width))
         ;; Why it can't be read (a folder too: reading it failed).
         (why (and file (cond ((not (file-readable-p file)) "not found")
                              ((not (file-regular-p file)) "not a file"))))
         (read (and file (not why)
                    (agent-ui-html--text-of
                     (with-temp-buffer
                       (let ((coding-system-for-read 'utf-8))
                         (insert-file-contents file nil 0 agent-ui-html-max-bytes))
                       (buffer-string)))))
         (title (or (car read) (if file (file-name-nondirectory file) page)))
         (open (lambda () (funcall agent-ui-open-page-function page))))
    (concat
     (propertize "◫ " 'face 'agent-ui-accent)
     (agent-ui-button (propertize (agent-ui-truncate title (- width 2)) 'face 'bold) open "RET: open the page")
     "\n"
     (propertize (agent-ui-truncate (abbreviate-file-name page) (if why (- width 4 (string-width why)) width))
                 'face 'agent-ui-muted)
     (cond
      (why (propertize (format "  (%s)" why) 'face 'agent-ui-muted))
      ((and read (not (string-empty-p (cdr read))))
       (concat "\n" (string-join (seq-take (split-string (agent-ui-wrap (cdr read) width) "\n")
                                           (plist-get props :lines))
                                 "\n")))
      (t "")))))

(agent-ui-define html
  "A web page as a card: its title and the start of its text, from an HTML
FILE (relative to your directory) or a URL (its address only). RET opens it:
in WebKit inside Emacs where it can, else the browser. For a report or a
page you made, to look at closer."
  :props ((file file "An HTML file")
          (url string "A web page's address")
          (lines integer "How many lines of its text the card shows" :default 4))
  :example (:file "coverage/index.html" :lines 3)
  :check (lambda (props)
           (unless (xor (plist-get props :file) (plist-get props :url))
             (agent-ui--fail "html: give a file or a url"))
           (unless (<= 0 (plist-get props :lines) 50)
             (agent-ui--fail "html: lines is 0 to 50"))
           props)
  :text #'agent-ui-html--text)
