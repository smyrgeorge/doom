;;; $DOOMDIR/config/mermaid/render.el -*- lexical-binding: t; -*-
;; Mermaid's source drawn as an SVG by mmdc, in the background, cached.
;; Loaded from config/mermaid.el.

;; THE RENDERER (see config/mermaid.el)
(defconst +my/mermaid--install
  "Mermaid diagrams need mmdc: npm install -g @mermaid-js/mermaid-cli (scripts/tools.sh installs it)."
  "What a diagram says without mmdc.")

;; Emacs's SVG library (librsvg) drops the space a <tspan> starts with, and
;; Mermaid writes each word of a label in one: "Write the code" showed as
;; "Writethecode". The SVG's root keeps them (xml:space), once mmdc wrote it.
(defun +my/mermaid-fix-svg (file)
  "FILE, an SVG mmdc wrote, made to show in Emacs (see above); a buffer
visiting it shows it anew."
  (when (and (stringp file) (string-suffix-p ".svg" file t) (file-exists-p file))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (and (re-search-forward "<svg\\b" nil t)
                 (not (looking-at "[^>]*xml:space=")))
        (insert " xml:space=\"preserve\"")
        (let ((coding-system-for-write 'utf-8-unix))
          (write-region nil nil file nil 'silent))))
    (when-let* ((buffer (find-buffer-visiting file)))
      (with-current-buffer buffer
        (revert-buffer t t t)))))

;; ====== THE CACHE ======

(defun +my/mermaid--key (source json)
  "SOURCE's key in the theme whose config is JSON."
  (secure-hash 'sha1 (concat json "\n" source)))

(defun +my/mermaid--svg (key)
  "The cached SVG of KEY (drawn or not)."
  (expand-file-name (concat key ".svg") +my/mermaid-cache-directory))

(defun +my/mermaid-cached (source)
  "SOURCE's SVG in the current theme's colours if it's drawn already, else
nil. Used: kept a month longer."
  (let ((file (+my/mermaid--svg (+my/mermaid--key source (+my/mermaid-theme-json)))))
    (when (file-exists-p file)
      (ignore-errors (set-file-times file))
      file)))

(defvar +my/mermaid--pruned nil "Non-nil once this session pruned the cache.")

(defun +my/mermaid--prune ()
  "Delete the cached SVGs unused for `+my/mermaid-cache-days', once a session."
  (unless +my/mermaid--pruned
    (setq +my/mermaid--pruned t)
    (when (file-directory-p +my/mermaid-cache-directory)
      (let ((old (time-subtract nil (days-to-time +my/mermaid-cache-days))))
        (dolist (file (directory-files +my/mermaid-cache-directory t "\\.svg\\'"))
          (when (time-less-p (file-attribute-modification-time (file-attributes file)) old)
            (ignore-errors (delete-file file))))))))

;; ====== RUNS ======

(defvar +my/mermaid--waiting (make-hash-table :test #'equal)
  "KEY: the callbacks waiting for its drawing (running or queued).")

(defvar +my/mermaid--queue nil "(KEY . SOURCE) waiting for a run, oldest first.")

(defvar +my/mermaid--running 0 "How many mmdc run.")

(defun +my/mermaid--chrome ()
  "The Chrome mmdc runs: `+my/mermaid-chrome', else on Linux on ARM (Chrome's
headless shell has no build there) the system's chromium; nil: puppeteer's."
  (or +my/mermaid-chrome
      (and (eq system-type 'gnu/linux)
           (string-match-p "\\`\\(aarch64\\|arm\\)" system-configuration)
           (or (executable-find "chromium") (executable-find "chromium-browser")))))

(defun +my/mermaid--puppeteer-config ()
  "A config for mmdc's Chrome where it needs one, written to Doom's cache: as
root (a container's user), Chrome runs only without its sandbox; another
Chrome than puppeteer's (`+my/mermaid--chrome'). Nil elsewhere."
  (let* ((chrome (+my/mermaid--chrome))
         (config (append (when chrome (list (cons 'executablePath chrome)))
                         (when (zerop (user-uid)) (list (cons 'args ["--no-sandbox"]))))))
    (when config
      (let ((file (expand-file-name "mermaid/puppeteer.json" doom-cache-dir))
            (json (json-serialize config)))
        (unless (and (file-exists-p file)
                     (equal json (with-temp-buffer (insert-file-contents file) (buffer-string))))
          (make-directory (file-name-directory file) t)
          (write-region json nil file nil 'silent))
        file))))

(defun +my/mermaid--arguments (output)
  "mmdc's arguments: the source on its input, the SVG to OUTPUT, the theme's
config, no background."
  (append (list "-q" "-i" "-" "-o" output "-c" (+my/mermaid-write-config) "-b" "transparent")
          (when-let* ((puppeteer (+my/mermaid--puppeteer-config)))
            (list "-p" puppeteer))))

(defun +my/mermaid--message (output status)
  "Mermaid's message in mmdc's OUTPUT (it exited with STATUS): its lines up to
the stack trace, without \"Error: \"."
  (let ((lines (cl-loop for line in (split-string output "\n")
                        until (string-match-p "\\`[ \t]*at \\|([a-z]+://" line)
                        collect line)))
    (or (let ((text (string-trim (string-join lines "\n"))))
          (unless (string-empty-p text)
            (string-remove-prefix "Error: " text)))
        (format "mmdc failed (%s)" status))))

(defun +my/mermaid--done (key file message)
  "KEY's drawing done: each callback waiting for it called with FILE, or nil
and MESSAGE."
  (let ((callbacks (gethash key +my/mermaid--waiting)))
    (remhash key +my/mermaid--waiting)
    (dolist (callback (reverse callbacks))
      (with-demoted-errors "Mermaid: %S"
        (funcall callback file message)))))

(defun +my/mermaid--next ()
  "Start the queued drawings there's room for (`+my/mermaid-jobs')."
  (while (and +my/mermaid--queue (< +my/mermaid--running +my/mermaid-jobs))
    (pcase-let ((`(,key . ,source) (pop +my/mermaid--queue)))
      (+my/mermaid--start key source))))

(defun +my/mermaid--start (key source)
  "Run mmdc drawing SOURCE into KEY's SVG."
  (let* ((file (+my/mermaid--svg key))
         ;; mmdc tells the format by the name's end.
         (part (concat (file-name-sans-extension file) ".part.svg"))
         (buffer (generate-new-buffer " *mermaid mmdc*"))
         (default-directory (file-name-as-directory (expand-file-name doom-cache-dir)))
         process)
    (make-directory +my/mermaid-cache-directory t)
    (condition-case err
        (setq process (make-process :name "mmdc"
                                    :buffer buffer
                                    :command (cons +my/mermaid-mmdc (+my/mermaid--arguments part))
                                    :connection-type 'pipe
                                    :coding 'utf-8
                                    :noquery t
                                    :sentinel #'+my/mermaid--sentinel))
      (error
       (kill-buffer buffer)
       (+my/mermaid--done key nil (error-message-string err))))
    (when process
      (cl-incf +my/mermaid--running)
      (process-put process '+my/mermaid (list key file part))
      (process-put process '+my/mermaid-timer
                   (run-at-time +my/mermaid-timeout nil #'+my/mermaid--stop process))
      (process-send-string process source)
      (process-send-eof process))))

(defun +my/mermaid--stop (process)
  "PROCESS ran for longer than `+my/mermaid-timeout': stopped."
  (when (process-live-p process)
    (process-put process '+my/mermaid-timed-out t)
    (delete-process process)))

(defun +my/mermaid--sentinel (process _event)
  "mmdc finished: its SVG in the cache, or Mermaid's message; the next run."
  (unless (process-live-p process)
    (pcase-let ((`(,key ,file ,part) (process-get process '+my/mermaid))
                (buffer (process-buffer process)))
      (when-let* ((timer (process-get process '+my/mermaid-timer)))
        (cancel-timer timer))
      (cl-decf +my/mermaid--running)
      (if (and (eq (process-status process) 'exit) (zerop (process-exit-status process))
               (file-exists-p part))
          (progn
            (+my/mermaid-fix-svg part)
            (rename-file part file t)
            (+my/mermaid--done key file nil))
        (ignore-errors (delete-file part))
        (+my/mermaid--done
         key nil
         (if (process-get process '+my/mermaid-timed-out)
             (format "mmdc took longer than %s s: stopped" +my/mermaid-timeout)
           (+my/mermaid--message (if (buffer-live-p buffer)
                                     (with-current-buffer buffer (buffer-string))
                                   "")
                                 (process-exit-status process)))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer))
      (+my/mermaid--next))))

;; ====== DRAWING ======

(defun +my/mermaid-render (source callback)
  "Draw SOURCE (Mermaid) as an SVG in the theme's colours, in the background.
Drawn already (this theme): its file, CALLBACK not called. Else nil, and
CALLBACK called later with the SVG's file and nil, or nil and a message:
Mermaid's error, or what to install. Several asking for the same drawing
share its run."
  (or (+my/mermaid-cached source)
      (let ((key (+my/mermaid--key source (+my/mermaid-theme-json))))
        (cond
         ((not (executable-find +my/mermaid-mmdc))
          (run-at-time 0 nil callback nil +my/mermaid--install))
         ((gethash key +my/mermaid--waiting)
          (push callback (gethash key +my/mermaid--waiting)))
         (t
          (+my/mermaid--prune)
          (puthash key (list callback) +my/mermaid--waiting)
          (setq +my/mermaid--queue (append +my/mermaid--queue (list (cons key source))))
          (+my/mermaid--next)))
        nil)))
