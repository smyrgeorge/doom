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

(defconst +md-preview--alerts-filter
  (expand-file-name "alerts.lua" (file-name-directory (or load-file-name buffer-file-name)))
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
