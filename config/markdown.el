;;; $DOOMDIR/config/markdown.el -*- lexical-binding: t; -*-
;; Markdown live preview inside Emacs. Loaded from config.el.

;; ====== VARIABLES ======

;; MARKDOWN
;; Live preview inside Emacs (GUI, xwidget WebKit): re-renders as you type and
;; scrolls to the cursor line. pandoc's `sourcepos' tags each element with its
;; source line (data-pos="L:C-L:C"), which the scroll script uses.
;; Its pane is a WebKit page (config/webkit.el): split, each pane shows the
;; preview, following the cursor; it opens without a white flash; links to
;; files open them in Emacs, in the file's pane, other links in the browser, links to a
;; heading (#install) scroll there. In it, j / k, C-d / C-u, C-f / C-b, gg / G
;; scroll, y or Cmd+C copies the selected text, q closes it (as SPC m p).
;; Terminal: falls back to markdown-mode's eww preview (updates on save).
;; PREVIEW NOTICE
;; A Markdown file opens with a notice at the top (config/banner.el) offering
;; the live preview: it goes once the preview opens (SPC m p, or its button) or
;; with its ✕, and doesn't come back for that buffer. Only where the live
;; preview works (GUI, xwidgets, pandoc), and for files.
(defvar +my/markdown-preview-notice t
  "Offer the live preview in a notice when a Markdown file opens.")

(defvar-local +md-preview--buffer nil
  "In a Markdown buffer: its preview's buffer (see `+md-preview-page-mode').")

(defvar-local +md-preview--source nil
  "In a preview's buffer: its Markdown buffer.")

(defvar-local +md-preview--timer nil)

(defvar-local +md-preview--line nil)

(defvar-local +md-preview--file nil)

(defconst +md-preview--highlight-js
  "document.querySelectorAll('pre > code').forEach(function(c){
     var l=(c.parentElement.className||'').split(' ')[0];
     if(l && c.className.indexOf('language-')<0) c.classList.add('language-'+l);
     if(window.hljs && !c.dataset.highlighted) hljs.highlightElement(c);
   });")

;; Links to a heading of the page (#install): scrolled there, not followed (the
;; page's <base> is the file's folder: WebKit would go to the folder).
(defconst +md-preview--anchors-js
  "document.addEventListener('click',function(e){
     var a=e.target.closest && e.target.closest('a[href^=\"#\"]'); if(!a) return;
     e.preventDefault();
     var id=decodeURIComponent(a.getAttribute('href').slice(1));
     var t=document.getElementById(id)||document.getElementsByName(id)[0];
     if(t) t.scrollIntoView();
   });")

(defconst +md-preview--scroll-js
  "(function(line){
     var best=null, bestLine=-1;
     document.querySelectorAll('[data-pos]:not([data-wrapper])').forEach(function(el){
       var m=/^(\\d+):/.exec(el.getAttribute('data-pos')); if(!m) return;
       var l=+m[1]; if(l<=line && l>=bestLine){best=el; bestLine=l;}
     });
     if(best) window.scrollTo(0, best.getBoundingClientRect().top + window.scrollY - window.innerHeight/3);
   })(%d);")

;; Hide marksman's false "Ambiguous link" warnings (see MARKSMAN DIAGNOSTICS).
(after! lsp-mode
  (setq lsp-diagnostic-filter #'+md--drop-false-link-warnings))

;; ====== KEY BINDINGS ======

;; Both maps: with +tree-sitter, .md files open in markdown-ts-mode.
(map! :after markdown-mode
      :map markdown-mode-map
      :localleader
      :desc "Live preview (in Emacs)" "p" #'+my/markdown-preview-toggle
      :desc "Preview in browser"      "P" #'markdown-preview)

(map! :after markdown-ts-mode
      :map markdown-ts-mode-map
      :localleader
      :desc "Live preview (in Emacs)" "p" #'+my/markdown-preview-toggle
      :desc "Preview in browser"      "P" #'markdown-preview)

;; The preview's pane (see above): keys of a WebKit page (config/webkit.el).
(defvar +md-preview-page-mode-map (make-sparse-keymap)
  "Keys of a Markdown preview's pane (see `+md-preview-page-mode').")

(map! :map +md-preview-page-mode-map
      "s-c"         #'+my/webkit-copy
      :nm "j"       #'+my/webkit-scroll-down
      :nm "k"       #'+my/webkit-scroll-up
      :nm "<down>"  #'+my/webkit-scroll-down
      :nm "<up>"    #'+my/webkit-scroll-up
      :nm "C-d"     #'+my/webkit-half-screen-down
      :nm "C-u"     #'+my/webkit-half-screen-up
      :nm "C-f"     #'+my/webkit-screen-down
      :nm "C-b"     #'+my/webkit-screen-up
      :nm "<next>"  #'+my/webkit-screen-down
      :nm "<prior>" #'+my/webkit-screen-up
      :nm "gg"      #'+my/webkit-top
      :nm "G"       #'+my/webkit-bottom
      :nm "<home>"  #'+my/webkit-top
      :nm "<end>"   #'+my/webkit-bottom
      :nm "y"       #'+my/webkit-copy
      :gnm "q"      #'kill-current-buffer)

;; Clicks are WebKit's: Emacs only selects the window (config/webkit.el).
(+my/webkit-bind-clicks +md-preview-page-mode-map)

;; ====== CODE ======

(defconst +md-preview--alerts-filter
  (expand-file-name "markdown-alerts.lua" (file-name-directory (or load-file-name buffer-file-name)))
  "The pandoc filter that gives GitHub's alerts (> [!NOTE]...) GitHub's look.")

(defun +md-preview--fragment ()
  "Render the current buffer to an HTML fragment with pandoc (source lines kept).
Math becomes MathML (rendered natively by WebKit); code is left for highlight.js;
GitHub's alerts get GitHub's markup (`+md-preview--alerts-filter')."
  (let ((src (current-buffer)))
    (with-temp-buffer
      (insert-buffer-substring src)
      (call-process-region (point-min) (point-max) "pandoc" t '(t nil) nil
                           "-f" "gfm+sourcepos" "-t" "html5"
                           "--syntax-highlighting=none"
                           "-L" +md-preview--alerts-filter)
      (buffer-string))))

(defun +md-preview--page (fragment)
  "Wrap FRAGMENT in a page styled like Doom's markdown preview (GitHub look)."
  (concat
   "<!doctype html><html><head><meta charset='utf-8'>"
   ;; In dark mode the whole page is GitHub's dark background, also before its
   ;; stylesheet arrives (a CDN; not WebKit's white) and below the text (the
   ;; stylesheet colours only the body, as tall as the text).
   "<meta name='color-scheme' content='light dark'>"
   (format "<style>@media (prefers-color-scheme: dark){html{background:%s}}</style>"
           (+md-preview--page-color 'dark))
   ;; Encoded: a folder named C# would otherwise end at its #.
   (format "<base href=\"%s\">"
           (+my/webkit-file-url (file-name-directory (or buffer-file-name default-directory))))
   (format "<title>Preview: %s</title>" (buffer-name))
   "<meta name='viewport' content='width=device-width, initial-scale=1'>"
   ;; github-markdown-css follows the OS light/dark setting, but highlight.js's
   ;; github theme is light-only; pick its light or dark variant to match.
   (mapconcat (lambda (css) (format "<link rel='stylesheet' href='%s'>" css))
              (seq-remove (lambda (css) (string-match-p "highlightjs" css))
                          markdown-css-paths)
              "")
   "<link rel='stylesheet' media='(prefers-color-scheme: light)' href='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/styles/github.min.css'>"
   "<link rel='stylesheet' media='(prefers-color-scheme: dark)' href='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/styles/github-dark.min.css'>"
   ;; As wide as the pane. (GitHub's stylesheet sets `.markdown-body''s margin,
   ;; which beat a plain `body' rule: the text stayed in a 740 px column on the
   ;; left, empty space on the right.)
   "<style>body.markdown-body{box-sizing:border-box;max-width:none;width:100%;margin:0;padding:24px 28px;}</style>"
   "<script src='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/highlight.min.js'></script>"
   "<script>" +md-preview--anchors-js
   "document.addEventListener('DOMContentLoaded',function(){"
   +md-preview--highlight-js "});</script>"
   "</head><body class='markdown-body'>" fragment "</body></html>"))

(defun +md-preview--live-p ()
  "Non-nil while this Markdown buffer's preview is open."
  (buffer-live-p +md-preview--buffer))

(defun +md-preview--run (script)
  "Run SCRIPT in the preview, in each of its views (one per window showing it,
config/webkit.el)."
  (when (+md-preview--live-p)
    (with-current-buffer +md-preview--buffer
      (+my/webkit-execute script t))))

(defun +md-preview--scroll ()
  (+md-preview--run (format +md-preview--scroll-js (line-number-at-pos))))

(defun +md-preview--update-script ()
  "JavaScript showing the Markdown as it is now, at the cursor's line, in a
page as it was (swapping its content, not reloading it)."
  (concat "document.body.innerHTML=" (json-encode (+md-preview--fragment)) ";"
          +md-preview--highlight-js
          (format +md-preview--scroll-js (line-number-at-pos))))

(defun +md-preview--update (buf)
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (when (+md-preview--live-p)
        (+md-preview--run (+md-preview--update-script))))))

(defun +md-preview--after-change-h (&rest _)
  (when (timerp +md-preview--timer) (cancel-timer +md-preview--timer))
  (setq +md-preview--timer
        (run-with-idle-timer 0.3 nil #'+md-preview--update (current-buffer))))

(defun +md-preview--post-command-h ()
  (let ((line (line-number-at-pos)))
    (unless (eql line +md-preview--line)
      (setq +md-preview--line line)
      (+md-preview--scroll))))

(defun +md-preview--page-color (&optional mode)
  "The preview page's background: GitHub's dark or light one, following the
system's setting (MODE: `dark' or `light' to choose)."
  (pcase (or mode (bound-and-true-p ns-system-appearance)
             (frame-parameter nil 'background-mode))
    ('light "#ffffff")
    (_ "#0d1117")))

;; THE PREVIEW'S PANE
;; A WebKit page (config/webkit.el) in the page's colour (also its cover while
;; a view loads: its stylesheet comes from a CDN), each new view written anew
;; from the Markdown as it is, then scrolled to the cursor's line.
(defun +md-preview--url (_window)
  "The page a new view of the preview loads (see VIEWS in config/webkit.el),
written anew: the Markdown as it is now."
  (let ((src +md-preview--source))
    (when (buffer-live-p src)
      (with-current-buffer src
        (let ((page (+md-preview--page (+md-preview--fragment))))
          (with-temp-file +md-preview--file
            (insert page)))
        (+my/webkit-file-url +md-preview--file)))))

(defun +md-preview--loaded (xwidget)
  "XWIDGET's page has loaded: the Markdown as it is now (back from a link,
WebKit loads the page's file again, as it was written), at the cursor's
line."
  (let ((src +md-preview--source))
    (when (buffer-live-p src)
      (+my/webkit-execute (with-current-buffer src (+md-preview--update-script))
                          xwidget))))

(defun +md-preview--follow (url)
  "A link out of the preview, to URL: a file opens in Emacs, in the Markdown
file's pane (else beside the preview); anything else in the browser."
  (if (not (string-prefix-p "file:" url))
      (browse-url url)
    (let ((file (+my/webkit-url-file url))
          (window (and (buffer-live-p +md-preview--source)
                       (get-buffer-window +md-preview--source))))
      (if (not window)
          (find-file-other-window file)
        (select-window window)
        (find-file file)))))

(defvar +md-preview-mode)               ; below

(defun +md-preview--closed-h ()
  "The preview's pane closed (q, its tab's ✕...): its Markdown buffer's
preview off."
  (let ((preview (current-buffer))
        (src +md-preview--source))
    (when (buffer-live-p src)
      (with-current-buffer src
        (when (and +md-preview-mode (eq +md-preview--buffer preview))
          (setq +md-preview--buffer nil)  ; it's going already
          (+md-preview-mode -1))))))

(define-derived-mode +md-preview-page-mode +my/webkit-mode "Preview"
  "A Markdown buffer's live preview, in WebKit (see `+md-preview-mode').

\\{+md-preview-page-mode-map}"
  (setq-local +my/webkit-url-function #'+md-preview--url
              +my/webkit-background #'+md-preview--page-color
              +my/webkit-link-function #'+md-preview--follow)
  (add-hook '+my/webkit-load-functions #'+md-preview--loaded nil t)
  ;; What the views don't cover, in the page's colour.
  (face-remap-add-relative 'default :background (+md-preview--page-color))
  (add-hook 'kill-buffer-hook #'+md-preview--closed-h nil t))

(after! evil
  (evil-set-initial-state '+md-preview-page-mode 'normal))

(defvar +my/focus-new-windows)          ; config/window.el

(defun +md-preview--off-h ()
  "The Markdown buffer killed, or its mode set again (its variables, this mode's
too, gone): its preview goes too."
  (+md-preview-mode -1))

(define-minor-mode +md-preview-mode
  "Live, cursor-following markdown preview in a WebKit pane beside the file."
  :lighter " MdPrev"
  (if +md-preview-mode
      (let ((src (current-buffer))
            (preview (generate-new-buffer (format "Preview: %s" (buffer-name)))))
        (setq +md-preview--file (make-temp-file "md-preview-" nil ".html")
              +md-preview--buffer preview)
        (with-current-buffer preview
          (+md-preview-page-mode)
          (setq +md-preview--source src))
        ;; Beside the file, half its window's width (a float would be half the
        ;; frame's: in a narrow window the file was left a few columns). The
        ;; cursor stays in the Markdown buffer: the preview follows it.
        (let ((+my/focus-new-windows nil))
          (display-buffer preview
                          `(display-buffer-in-direction
                            (direction . right)
                            (window-width . ,(/ (window-total-width) 2)))))
        (add-hook 'after-change-functions #'+md-preview--after-change-h nil t)
        (add-hook 'post-command-hook #'+md-preview--post-command-h nil t)
        (add-hook 'kill-buffer-hook #'+md-preview--off-h nil t)
        (add-hook 'change-major-mode-hook #'+md-preview--off-h nil t))
    (remove-hook 'after-change-functions #'+md-preview--after-change-h t)
    (remove-hook 'post-command-hook #'+md-preview--post-command-h t)
    (remove-hook 'kill-buffer-hook #'+md-preview--off-h t)
    (remove-hook 'change-major-mode-hook #'+md-preview--off-h t)
    (when (timerp +md-preview--timer) (cancel-timer +md-preview--timer))
    (when (+md-preview--live-p)
      (let ((preview +md-preview--buffer))
        (setq +md-preview--buffer nil)
        (dolist (window (get-buffer-window-list preview nil t))
          ;; The frame's only window: it shows another buffer once the
          ;; preview is gone.
          (ignore-errors (delete-window window)))
        (let ((kill-buffer-query-functions nil))
          (kill-buffer preview))))
    (when (and +md-preview--file (file-exists-p +md-preview--file))
      (delete-file +md-preview--file))
    (setq +md-preview--file nil +md-preview--line nil)))

(defun +my/markdown-preview-live-p ()
  "Non-nil if the live preview works here (GUI, xwidgets, pandoc)."
  (and (+my/webkit-p) (executable-find "pandoc")))

(defun +my/markdown-preview-toggle ()
  "SPC m p: live preview in Emacs (WebKit in GUI, eww in a terminal)."
  (interactive)
  (if (+my/markdown-preview-live-p)
      (+md-preview-mode 'toggle)
    (markdown-live-preview-mode 'toggle)))

;; PREVIEW NOTICE (see above)
(defun +my/markdown-preview-notice-h ()
  (when (and +my/markdown-preview-notice
             buffer-file-name
             (not (bound-and-true-p +md-preview-mode))
             (+my/markdown-preview-live-p))
    (+my/banner-show
     'markdown-preview
     "See this file rendered next to it, updated as you type (SPC m p)."
     :actions '(("Open preview" . +my/markdown-preview-toggle)))))

(add-hook 'markdown-mode-hook #'+my/markdown-preview-notice-h)

(add-hook 'markdown-ts-mode-hook #'+my/markdown-preview-notice-h)

(add-hook '+md-preview-mode-hook
          (defun +my/markdown-preview-notice-close-h ()
            (when +md-preview-mode
              (+my/banner-close 'markdown-preview))))

;; MARKSMAN DIAGNOSTICS
;; Two false warnings from marksman (the Markdown language server) about links
;; that work, dropped when the link is a path to an existing file:
;; - "Ambiguous link to document": marksman takes every top-level `#' heading
;;   of a document as its title, so a link to a file with more than one, e.g.
;;   [README](the-game/README.md), was "ambiguous" though it names one file.
;;   Genuinely ambiguous links (e.g. [[README]] matching several files) are
;;   still reported.
;; - "Link to non-existent document": marksman doesn't index files git
;;   ignores, so a link to one (a report kept out of the repository) pointed
;;   "nowhere". Links to files that really are missing are still reported.
(defun +md--drop-false-link-warnings (params workspace)
  "Filter for `lsp-diagnostic-filter': see the comment above."
  (when (eq (lsp--workspace-server-id workspace) 'marksman)
    (let ((dir (file-name-directory
                (lsp--uri-to-path (lsp:publish-diagnostics-params-uri params)))))
      (setq params
            (lsp-put params :diagnostics
                     (vconcat
                      (seq-remove
                       (lambda (diagnostic)
                         (let ((message (lsp:diagnostic-message diagnostic)))
                           (and (string-match "\\`\\(?:Ambiguous link to\\|Link to non-existent\\) document '\\(.+\\)'\\'"
                                              message)
                                (file-regular-p
                                 (expand-file-name
                                  (url-unhex-string ; %20 etc.
                                   (car (split-string (match-string 1 message) "#")))
                                  dir)))))
                       (lsp:publish-diagnostics-params-diagnostics params)))))))
  params)
