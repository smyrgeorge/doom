;;; $DOOMDIR/config/markdown/page.el -*- lexical-binding: t; -*-
;; The preview's page: pandoc's HTML, updated as you type. Loaded from config/markdown.el.

(defvar-local +md-preview--buffer nil
  "In a Markdown buffer: its preview's buffer (see `+md-preview-page-mode').")

(defvar-local +md-preview--source nil
  "In a preview's buffer: its Markdown buffer.")

(defvar-local +md-preview--timer nil)

(defvar-local +md-preview--line nil)

(defvar-local +md-preview--file nil)

(defconst +md-preview--highlight-js
  "document.querySelectorAll('pre:not(.mermaid) > code').forEach(function(c){
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

(defconst +md-preview--alerts-filter
  (expand-file-name "alerts.lua" (file-name-directory (or load-file-name buffer-file-name)))
  "The pandoc filter that gives GitHub's alerts (> [!NOTE]...) GitHub's look.")

(defvar +md-preview--pandoc-args nil
  "The pandoc arguments that differ by its version, once known (see
`+md-preview--version-args').")

(defun +md-preview--pandoc-version ()
  "The installed pandoc's version (\"3.13\"), or nil."
  (with-temp-buffer
    (and (eql 0 (ignore-errors (call-process "pandoc" nil t nil "--version")))
         (progn (goto-char (point-min))
                (and (re-search-forward "\\`pandoc[^ \n]* \\([0-9.]+\\)" nil t)
                     (match-string 1))))))

(defun +md-preview--version-args ()
  "Pandoc's arguments for no highlighting of its own and math as MathML:
since pandoc 3.8, --syntax-highlighting=none (MathML is its default there,
--no-highlight and --mathml only warn); before (Debian's and Ubuntu's
pandoc, where the new one is an error), --no-highlight and --mathml."
  (or +md-preview--pandoc-args
      (setq +md-preview--pandoc-args
            (let ((version (+md-preview--pandoc-version)))
              (if (and version (version<= "3.8" version))
                  '("--syntax-highlighting=none")
                '("--no-highlight" "--mathml"))))))

(defun +md-preview--fragment ()
  "Render the current buffer to an HTML fragment with pandoc (source lines kept).
Math becomes MathML (rendered natively by WebKit); code is left for highlight.js;
GitHub's alerts get GitHub's markup (`+md-preview--alerts-filter')."
  (let ((src (current-buffer)))
    (with-temp-buffer
      (insert-buffer-substring src)
      (apply #'call-process-region (point-min) (point-max) "pandoc" t '(t nil) nil
             "-f" "gfm+sourcepos" "-t" "html5"
             (append (+md-preview--version-args)
                     (list "-L" +md-preview--alerts-filter)))
      (buffer-string))))

(defun +md-preview--page (fragment)
  "Wrap FRAGMENT in a page styled like Doom's markdown preview (GitHub look)."
  (concat
   "<!doctype html><html><head><meta charset='utf-8'>"
   ;; Dark or light as the theme is (not the OS: `+md-preview--mode'). The
   ;; whole page in its background, also before the stylesheet arrives (a
   ;; CDN; not WebKit's white) and below the text (the stylesheet colours only
   ;; the body, as tall as the text).
   (format "<meta id='md-scheme' name='color-scheme' content='%s'>" (+md-preview--mode))
   (format "<style id='md-background'>html{background:%s}</style>" (+md-preview--page-color))
   ;; Encoded: a folder named C# would otherwise end at its #.
   (format "<base href=\"%s\">"
           (+my/webkit-file-url (file-name-directory (or buffer-file-name default-directory))))
   (format "<title>Preview: %s</title>" (buffer-name))
   "<meta name='viewport' content='width=device-width, initial-scale=1'>"
   ;; GitHub's stylesheets, their dark or light variant (the theme's).
   (let ((n 0))
     (mapconcat (lambda (css)
                  (format "<link id='md-css-%d' rel='stylesheet' href='%s'>" (cl-incf n) css))
                (+md-preview--stylesheets)
                ""))
   ;; As wide as the pane. (GitHub's stylesheet sets `.markdown-body''s margin,
   ;; which beat a plain `body' rule: the text stayed in a 740 px column on the
   ;; left, empty space on the right.)
   "<style>body.markdown-body{box-sizing:border-box;max-width:none;width:100%;margin:0;padding:24px 28px;}</style>"
   "<script src='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/highlight.min.js'></script>"
   "<script>" +md-preview--anchors-js
   "document.addEventListener('DOMContentLoaded',function(){"
   +md-preview--highlight-js "});</script>"
   ;; ```mermaid blocks as diagrams (markdown/mermaid.el).
   (+md-preview--mermaid-head)
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
          (+md-preview--mermaid-draw-script)
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

(defun +md-preview--mode ()
  "The preview's look, `dark' or `light': the theme's (its background), not
the OS's: beside a light theme, a light page."
  (if (eq (frame-parameter nil 'background-mode) 'light) 'light 'dark))

(defun +md-preview--page-color (&optional mode)
  "The preview page's background: GitHub's dark or light one, the theme's
(MODE: `dark' or `light' to choose)."
  (pcase (or mode (+md-preview--mode))
    ('light "#ffffff")
    (_ "#0d1117")))

(defun +md-preview--stylesheets (&optional mode)
  "GitHub's stylesheets (Doom's `markdown-css-paths'), their MODE variant
(default: the theme's): github-markdown-css's and highlight.js's, which
otherwise follow the OS (one) or are light only (the other)."
  (let ((mode (or mode (+md-preview--mode))))
    (append
     (mapcar (lambda (css)
               (replace-regexp-in-string
                "/github-markdown\\(?:-light\\|-dark\\)?\\(\\.min\\)?\\.css\\'"
                (format "/github-markdown-%s\\1.css" mode) css t))
             (seq-remove (lambda (css) (string-match-p "highlightjs" css)) markdown-css-paths))
     (list (format "https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/styles/%s.min.css"
                   (if (eq mode 'light) "github" "github-dark"))))))

;; THE THEME, CHANGED
;; An open preview takes the theme's look at once (SPC h t, its previews too):
;; its stylesheets, background and colour scheme swapped, not reloaded (its
;; place kept).
(defun +md-preview--theme-script ()
  "JavaScript giving a page the theme's look now (see above)."
  (let ((n 0))
    (concat
     (format "document.getElementById('md-scheme').content=%S;" (symbol-name (+md-preview--mode)))
     (format "document.getElementById('md-background').textContent='html{background:%s}';"
             (+md-preview--page-color))
     (mapconcat (lambda (css)
                  (format "var l=document.getElementById('md-css-%d');if(l)l.href=%S;" (cl-incf n) css))
                (+md-preview--stylesheets)
                "")
     (+md-preview--mermaid-theme-script))))

(defvar-local +md-preview--background-cookie nil
  "The preview pane's background remap (`face-remap-add-relative').")

(defun +md-preview--paint-background ()
  "The preview pane's background, what its views don't cover: the page's."
  (when +md-preview--background-cookie
    (face-remap-remove-relative +md-preview--background-cookie))
  (setq +md-preview--background-cookie
        (face-remap-add-relative 'default :background (+md-preview--page-color))))

(defun +md-preview-theme-h ()
  "The theme changed: each preview in its look (see above)."
  (dolist (buffer (buffer-list))
    (when (eq (buffer-local-value 'major-mode buffer) '+md-preview-page-mode)
      (with-current-buffer buffer
        (+md-preview--paint-background)
        (+my/webkit-execute (+md-preview--theme-script) t)))))

(add-hook 'doom-load-theme-hook #'+md-preview-theme-h)
