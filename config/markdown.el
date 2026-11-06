;;; $DOOMDIR/config/markdown.el -*- lexical-binding: t; -*-
;; Markdown live preview inside Emacs. Loaded from config.el.

;; ====== VARIABLES ======

;; MARKDOWN
;; Live preview inside Emacs (GUI, xwidget WebKit): re-renders as you type and
;; scrolls to the cursor line. pandoc's `sourcepos' tags each element with its
;; source line (data-pos="L:C-L:C"), which the scroll script uses.
;; Terminal: falls back to markdown-mode's eww preview (updates on save).
;; PREVIEW NOTICE
;; A Markdown file opens with a notice at the top (config/banner.el) offering
;; the live preview: it goes once the preview opens (SPC m p, or its button) or
;; with its ✕, and doesn't come back for that buffer. Only where the live
;; preview works (GUI, xwidgets, pandoc), and for files.
(defvar +my/markdown-preview-notice t
  "Offer the live preview in a notice when a Markdown file opens.")

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

;; ====== CODE ======

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
   ;; Before GitHub's stylesheet arrives (a CDN), the page is the buffer's
   ;; colour in dark mode, not WebKit's white.
   "<meta name='color-scheme' content='light dark'>"
   (format "<style>@media (prefers-color-scheme: dark){html{background:%s}}</style>"
           (face-background 'default nil t))
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
   ;; As wide as the pane. (GitHub's stylesheet sets `.markdown-body''s margin,
   ;; which beat a plain `body' rule: the text stayed in a 740 px column on the
   ;; left, empty space on the right.)
   "<style>body.markdown-body{box-sizing:border-box;max-width:none;width:100%;margin:0;padding:24px 28px;}</style>"
   "<script src='https://cdn.jsdelivr.net/gh/highlightjs/cdn-release/build/highlight.min.js'></script>"
   "<script>document.addEventListener('DOMContentLoaded',function(){"
   +md-preview--highlight-js "});</script>"
   "</head><body class='markdown-body'>" fragment "</body></html>"))

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

;; NO WHITE FLASH
;; WebKit's view is white until its page has loaded (GitHub's stylesheet, from
;; a CDN, included): the preview flashed white before its colours appeared.
;; Its window opens at once (WebKit only loads while on screen) under a
;; borderless frame in the editor's background colour, like the notices'
;; (config/banner.el), which goes once WebKit says the page has loaded, or
;; after 2 s (e.g. offline). No JavaScript is run to ask the page instead:
;; closing a preview while such a call was pending crashed Emacs.
(defvar +md-preview--cover nil
  "(XWIDGET FRAME TIMER): the frame over a preview whose page is loading.")

(defun +md-preview--uncover (&optional xwidget)
  "Take the cover off XWIDGET's preview (any preview's, by default)."
  (pcase +md-preview--cover
    (`(,covered ,frame ,timer)
     (when (or (null xwidget) (eq covered xwidget))
       (setq +md-preview--cover nil)
       (when (timerp timer) (cancel-timer timer))
       (+my/banner--delete-frame frame)))))

(defun +md-preview--cover-window (window)
  "Cover WINDOW in the editor's background colour, for 2 s at most (see above)."
  (+md-preview--uncover)
  (when (and (window-live-p window) (display-graphic-p (window-frame window))
             (fboundp '+my/banner--make-frame))
    (let ((frame (+my/banner--make-frame (window-frame window)))
          (edges (window-pixel-edges window))
          (frame-resize-pixelwise t))
      (set-frame-parameter frame 'background-color (face-background 'default nil t))
      (set-frame-size frame (- (nth 2 edges) (nth 0 edges))
                      (- (nth 3 edges) (nth 1 edges)) t)
      (set-frame-position frame (nth 0 edges) (nth 1 edges))
      (make-frame-visible frame)
      (setq +md-preview--cover
            (list nil frame (run-at-time 2 nil #'+md-preview--uncover))))))

(defun +md-preview--watch (xwidget)
  "Take the cover off once XWIDGET's page has loaded."
  (when +md-preview--cover
    (setf (car +md-preview--cover) xwidget)))

(defadvice! +md-preview--loaded-a (xwidget event-type)
  :after #'xwidget-webkit-callback
  (when (and (eq event-type 'load-changed)
             (equal (nth 3 last-input-event) "load-finished")
             (eq (car +md-preview--cover) xwidget))
    ;; A moment for WebKit to paint it.
    (run-at-time 0.05 nil #'+md-preview--uncover xwidget)))

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
        ;; The preview's window first, beside the file, covered (see NO WHITE
        ;; FLASH), then WebKit in it: made elsewhere and shown there after, its
        ;; page never answered (or said it had loaded). The cursor stays in the
        ;; Markdown buffer: the preview follows it. Half of the file's window
        ;; (a float would be half the frame's: in a narrow window the file was
        ;; left a few columns).
        (let* ((+my/focus-new-windows nil)
               (window (display-buffer
                        (get-buffer-create " *md-preview*")
                        `(display-buffer-in-direction
                          (direction . right)
                          (window-width . ,(/ (window-total-width) 2))))))
          (+md-preview--cover-window window)
          (with-selected-window window
            (xwidget-webkit-browse-url (concat "file://" file) t))
          (setq +md-preview--xwidget
                (with-current-buffer xwidget-webkit-last-session-buffer
                  ;; Its tab's name: the page's title, `Preview: FILE' (it was
                  ;; made from the placeholder's, hidden, then
                  ;; `*xwidget-webkit: ...*').
                  (setq-local xwidget-webkit-buffer-name-format "%T")
                  (rename-buffer (format "Preview: %s" (buffer-name src)) t)
                  (xwidget-webkit-current-session)))
          (+md-preview--watch +md-preview--xwidget))
        (add-hook 'after-change-functions #'+md-preview--after-change-h nil t)
        (add-hook 'post-command-hook #'+md-preview--post-command-h nil t)
        (add-hook 'kill-buffer-hook (lambda () (+md-preview-mode -1)) nil t)
        (run-with-timer 0.6 nil (lambda (b) (when (buffer-live-p b)
                                              (with-current-buffer b (+md-preview--scroll))))
                        src))
    (when +md-preview--xwidget
      (+md-preview--uncover +md-preview--xwidget))
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

(defun +my/markdown-preview-live-p ()
  "Non-nil if the live preview works here (GUI, xwidgets, pandoc)."
  (and (display-graphic-p) (featurep 'xwidget-internal)
       (executable-find "pandoc")))

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
