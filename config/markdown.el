;;; $DOOMDIR/config/markdown.el -*- lexical-binding: t; -*-
;; Markdown live preview inside Emacs. Loaded from config.el.

;; MARKDOWN
;; Live preview inside Emacs (GUI, xwidget WebKit): re-renders as you type and
;; scrolls to the cursor line. pandoc's `sourcepos' tags each element with its
;; source line (data-pos="L:C-L:C"), which the scroll script uses.
;; Terminal: falls back to markdown-mode's eww preview (updates on save).
(defvar-local +md-preview--xwidget nil)
(defvar-local +md-preview--timer nil)
(defvar-local +md-preview--line nil)
(defvar-local +md-preview--file nil)

(defconst +md-preview--highlight-js
  "document.querySelectorAll('pre > code').forEach(function(c){
     var l=(c.parentElement.className||'').split(' ')[0];
     if(l && c.className.indexOf('language-')<0) c.classList.add('language-'+l);
     if(window.hljs && !c.dataset.highlighted) hljs.highlightElement(c);
   });")

(defun +md-preview--fragment ()
  "Render the current buffer to an HTML fragment with pandoc (source lines kept).
Math becomes MathML (rendered natively by WebKit); code is left for highlight.js."
  (let ((src (current-buffer)))
    (with-temp-buffer
      (insert-buffer-substring src)
      (call-process-region (point-min) (point-max) "pandoc" t '(t nil) nil
                           "-f" "gfm+sourcepos" "-t" "html5"
                           "--syntax-highlighting=none")
      (buffer-string))))

(defun +md-preview--page (fragment)
  "Wrap FRAGMENT in a page styled like Doom's markdown preview (GitHub look)."
  (concat
   "<!doctype html><html><head><meta charset='utf-8'>"
   (format "<base href='file://%s'>"
           (file-name-directory (or buffer-file-name default-directory)))
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
   "<style>body{box-sizing:border-box;max-width:740px;width:100%;margin:40px auto;padding:0 10px;}</style>"
   "<script src='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/highlight.min.js'></script>"
   "<script>document.addEventListener('DOMContentLoaded',function(){"
   +md-preview--highlight-js "});</script>"
   "</head><body class='markdown-body'>" fragment "</body></html>"))

(defconst +md-preview--scroll-js
  "(function(line){
     var best=null, bestLine=-1;
     document.querySelectorAll('[data-pos]:not([data-wrapper])').forEach(function(el){
       var m=/^(\\d+):/.exec(el.getAttribute('data-pos')); if(!m) return;
       var l=+m[1]; if(l<=line && l>=bestLine){best=el; bestLine=l;}
     });
     if(best) window.scrollTo(0, best.getBoundingClientRect().top + window.scrollY - window.innerHeight/3);
   })(%d);")

(defun +md-preview--live-p ()
  (and +md-preview--xwidget (xwidget-live-p +md-preview--xwidget)))

(defun +md-preview--scroll ()
  (when (+md-preview--live-p)
    (xwidget-webkit-execute-script
     +md-preview--xwidget (format +md-preview--scroll-js (line-number-at-pos)))))

(defun +md-preview--update (buf)
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (when (+md-preview--live-p)
        (xwidget-webkit-execute-script
         +md-preview--xwidget
         (concat "document.body.innerHTML=" (json-encode (+md-preview--fragment)) ";"
                 +md-preview--highlight-js
                 (format +md-preview--scroll-js (line-number-at-pos))))))))

(defun +md-preview--after-change-h (&rest _)
  (when (timerp +md-preview--timer) (cancel-timer +md-preview--timer))
  (setq +md-preview--timer
        (run-with-idle-timer 0.3 nil #'+md-preview--update (current-buffer))))

(defun +md-preview--post-command-h ()
  (let ((line (line-number-at-pos)))
    (unless (eql line +md-preview--line)
      (setq +md-preview--line line)
      (+md-preview--scroll))))

(define-minor-mode +md-preview-mode
  "Live, cursor-following markdown preview in an xwidget WebKit side window."
  :lighter " MdPrev"
  (if +md-preview-mode
      (let ((src (current-buffer))
            (file (make-temp-file "md-preview-" nil ".html")))
        (require 'xwidget)
        (with-temp-file file
          (insert (with-current-buffer src (+md-preview--page (+md-preview--fragment)))))
        (setq +md-preview--file file)
        (save-window-excursion
          (xwidget-webkit-browse-url (concat "file://" file) t))
        (let ((xw-buf xwidget-webkit-last-session-buffer))
          (setq +md-preview--xwidget (with-current-buffer xw-buf (xwidget-webkit-current-session)))
          (display-buffer xw-buf '(display-buffer-in-direction
                                   (direction . right) (window-width . 0.5))))
        (add-hook 'after-change-functions #'+md-preview--after-change-h nil t)
        (add-hook 'post-command-hook #'+md-preview--post-command-h nil t)
        (add-hook 'kill-buffer-hook (lambda () (+md-preview-mode -1)) nil t)
        (run-with-timer 0.6 nil (lambda (b) (when (buffer-live-p b)
                                              (with-current-buffer b (+md-preview--scroll))))
                        src))
    (remove-hook 'after-change-functions #'+md-preview--after-change-h t)
    (remove-hook 'post-command-hook #'+md-preview--post-command-h t)
    (when (timerp +md-preview--timer) (cancel-timer +md-preview--timer))
    (when (+md-preview--live-p)
      (let ((buf (xwidget-buffer +md-preview--xwidget)))
        (when (buffer-live-p buf)
          (mapc #'delete-window (get-buffer-window-list buf nil t))
          (let ((kill-buffer-query-functions nil)) (kill-buffer buf)))))
    (when (and +md-preview--file (file-exists-p +md-preview--file))
      (delete-file +md-preview--file))
    (setq +md-preview--xwidget nil +md-preview--file nil +md-preview--line nil)))

(defun +my/markdown-preview-toggle ()
  "SPC m p: live preview in Emacs (WebKit in GUI, eww in a terminal)."
  (interactive)
  (if (and (display-graphic-p) (featurep 'xwidget-internal) (executable-find "pandoc"))
      (+md-preview-mode 'toggle)
    (markdown-live-preview-mode 'toggle)))

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
