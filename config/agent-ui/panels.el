;;; $DOOMDIR/config/agent-ui/panels.el -*- lexical-binding: t; -*-
;; Agent UI's project panels: a panel kept in its project's repository, a
;; file of its own, opened on demand, its data fetched afresh each time it
;; opens (none is kept). Loaded from config/agent-ui.el, after staging.el (its
;; compiling). No Doom here.
;;
;; PROJECT/.agent-ui/panels/NAME.el holds one form:
;;
;;   (agent-ui-panel
;;    :version 1
;;    :ui (:type "panel" :id "service" :title "Service" :layout "row"
;;         :children ((:type "table" :id "ci" :title "CI" :columns ("Run" "Status"))
;;                    (:type "gauge" :id "dirty" :title "Unsaved buffers" :max 20)))
;;    :every 30
;;    :fetch (lambda (panel) ...))
;;
;; :ui is what it shows, an element (usually a panel of elements) with its
;; data left out: read as it is, never evaluated, so it's drawn before its
;; code is trusted. :every, :fetch, :start and :stop are its script, which
;; fills it. The UI and its code in one file: ids defined and used in one
;; place. `agent-ui-panel-check' checks a file as the agent writes it.

(require 'cl-lib)
(require 'subr-x)

;; ====== VARIABLES ======

(defcustom agent-ui-panel-directory ".agent-ui/panels/"
  "Where a project's panels are, in its root."
  :type 'string :group 'agent-ui)

(defconst agent-ui-panel-version 1
  "The panel files this Agent UI reads: their :version.")

(defconst agent-ui-panel--keys '(:version :ui :every :fetch :start :stop)
  "What a panel's form has.")

(defconst agent-ui-panel-blocking
  '(shell-command-to-string shell-command call-process call-process-region
    call-process-shell-command process-file process-lines
    url-retrieve-synchronously sleep-for)
  "Calls that wait, Emacs frozen meanwhile: never in a panel's script (it runs
every so often, in the user's Emacs). `agent-ui-panel-run' instead.")

;; ====== THE FORM ======

(defmacro agent-ui-panel (&rest props)
  "A project panel (see the top of this file): PROPS, its :ui as it is
\(data, not evaluated), the others evaluated (:fetch a function...)."
  (cl-loop for (key _) on props by #'cddr
           unless (memq key agent-ui-panel--keys)
           do (error "agent-ui-panel has %S: it has %s" key
                     (mapconcat (lambda (k) (substring (symbol-name k) 1)) agent-ui-panel--keys ", ")))
  `(list ,@(cl-loop for (key value) on props by #'cddr
                    append (list key (if (eq key :ui) (list 'quote value) value)))))

;; ====== A PROJECT'S PANELS ======

(defun agent-ui-panel-root (&optional dir)
  "The project of DIR (default: `default-directory'), its root: the folder
holding its panels (`agent-ui-panel-directory'), else its project's root;
nil if neither."
  (let ((dir (expand-file-name (or dir default-directory))))
    (when-let* ((root (or (locate-dominating-file dir agent-ui-panel-directory)
                          (when-let* (((fboundp 'project-current))
                                      (project (project-current nil dir)))
                            (project-root project)))))
      (file-name-as-directory (expand-file-name root)))))

(defun agent-ui-panels (&optional dir)
  "The names of the panels of DIR's project (see `agent-ui-panel-root'),
sorted; nil if it has none."
  (when-let* ((root (agent-ui-panel-root dir))
              (folder (expand-file-name agent-ui-panel-directory root))
              ((file-directory-p folder)))
    (sort (mapcar #'file-name-base (directory-files folder nil "\\`[^.#].*\\.el\\'"))
          #'string<)))

(defun agent-ui-panel-file (name &optional dir)
  "The file of panel NAME, of DIR's project; NAME ending in .el, a file taken
as it is (relative to DIR). An error naming the project's panels if there's
none."
  (let* ((root (agent-ui-panel-root dir))
         (file (cond ((string-suffix-p ".el" name) (expand-file-name name (or dir default-directory)))
                     (root (expand-file-name (concat name ".el")
                                             (expand-file-name agent-ui-panel-directory root))))))
    (unless (and file (file-readable-p file))
      (let ((panels (and root (agent-ui-panels root))))
        (agent-ui--fail "panel %s: %s" name
                        (cond (panels (format "not one of this project's: %s" (string-join panels ", ")))
                              (root (format "this project has no panels (%s)" agent-ui-panel-directory))
                              (t "no project here")))))
    file))

;; ====== READING ONE ======

(defun agent-ui-panel--forms (file what)
  "FILE's top-level forms, read, not evaluated; an error for WHAT saying
where it doesn't read."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (goto-char (point-min))
    (let (forms)
      (condition-case err
          (while (progn (forward-comment (buffer-size)) (not (eobp)))
            (push (read (current-buffer)) forms))
        (end-of-file
         (agent-ui--fail "%s: its file ends inside a form (a parenthesis or a quote missing?)" what))
        (error (agent-ui--fail "%s: its file doesn't read, at line %d: %s"
                               what (line-number-at-pos) (error-message-string err))))
      (nreverse forms))))

(defun agent-ui-panel-read (file)
  "FILE, a panel's (see the top of this file), read, never evaluated: a
plist, :name (its file's), :file, :ui (its element, right as show has it),
:every and :form (the whole, for its script). An error saying what's wrong
with it."
  (let* ((name (file-name-base file))
         (what (format "panel %s" name))
         (forms (agent-ui-panel--forms file what))
         (form (car forms))
         (props (cdr-safe form)))
    (unless (and (= (length forms) 1) (eq (car-safe form) 'agent-ui-panel))
      (agent-ui--fail "%s: its file holds one form, (agent-ui-panel :ui ... :fetch ...), not %s"
                      what (if (= (length forms) 1)
                               (truncate-string-to-width (format "%S" form) 50 nil nil "…")
                             (format "%d forms" (length forms)))))
    (unless (and (listp props) (cl-evenp (length props)))
      (agent-ui--fail "%s: agent-ui-panel takes keys and their values (:ui ..., :fetch ...)" what))
    (cl-loop for (key _) on props by #'cddr
             unless (memq key agent-ui-panel--keys)
             do (agent-ui--fail "%s has %s: a panel has %s" what (agent-ui--show-value key)
                                (mapconcat (lambda (k) (substring (symbol-name k) 1)) agent-ui-panel--keys ", ")))
    (let ((version (plist-get props :version)))
      (unless (memql version (list nil agent-ui-panel-version))
        (agent-ui--fail "%s is version %s: this Agent UI reads version %d"
                        what (agent-ui--show-value version) agent-ui-panel-version)))
    (let ((every (plist-get props :every)))
      (unless (or (null every) (and (numberp every) (> every 0)))
        (agent-ui--fail "%s: every is how many seconds between fetches, a number above 0, not %s"
                        what (agent-ui--show-value every))))
    (let ((ui (plist-get props :ui)))
      (unless (agent-ui--plist-p ui)
        (agent-ui--fail "%s: its :ui is what it shows, an element: (:type \"panel\" :id ... :children (...))" what))
      (condition-case err
          (agent-ui--checked ui)
        (agent-ui-error (agent-ui--fail "%s: its :ui: %s" what (agent-ui-error-message err))))
      (list :name name :file file :ui ui :every (plist-get props :every) :form form))))

;; ====== CHECKING ONE ======

(defun agent-ui-panel--blocking (file)
  "The calls in FILE's code that wait (`agent-ui-panel-blocking', and
accept-process-output with no timeout), outside its comments and strings:
\"line N: NAME ...\" each."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (with-syntax-table emacs-lisp-mode-syntax-table
      (let ((re (concat "\\(?:(\\|#'\\)\\("
                        (regexp-opt (mapcar #'symbol-name (cons 'accept-process-output agent-ui-panel-blocking)))
                        "\\)\\_>"))
            (found nil))
        (goto-char (point-min))
        (while (re-search-forward re nil t)
          (let ((start (match-beginning 0))
                (call (match-string 1)))
            (unless (or (nth 8 (save-excursion (syntax-ppss start)))
                        ;; With a timeout, it returns.
                        (and (equal call "accept-process-output")
                             (eq (char-after start) ?\()
                             (>= (length (ignore-errors (save-excursion (goto-char start)
                                                                        (read (current-buffer)))))
                                 3)))
              (push (format "line %d: %s waits, Emacs frozen meanwhile: use agent-ui-panel-run"
                            (line-number-at-pos start) call)
                    found))))
        (nreverse found)))))

(defun agent-ui-panel--compile (file name)
  "FILE's code (panel NAME's) compiled, its warnings (an error if it doesn't
compile), their lines FILE's. In a function: at top level, a lambda's body
isn't looked at (its warnings unsaid)."
  (let ((temp (make-temp-file "agent-ui-panel-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp
            (setq-local coding-system-for-write 'utf-8)
            (insert ";;; -*- lexical-binding: t; -*-\n(defun agent-ui-panel--checking ()\n")
            (let ((coding-system-for-read 'utf-8))
              (insert-file-contents file))
            (goto-char (point-max))
            (insert "\n)\n"))
          (agent-ui--byte-compile temp 2 (format "panel %s" name)))
      (delete-file temp))))

(defun agent-ui-panel-check (file)
  "FILE, a panel's, checked as the agent writes it, nothing run: read (its
:ui as show checks it), compiled (an error refuses it; its warnings said),
its waiting calls found. Returns (:ok t :panel NAME :file FILE :type TYPE
:every N :warnings [...] :blocking [...]); an error saying what's wrong."
  (let* ((panel (agent-ui-panel-read file))
         (name (plist-get panel :name))
         (cookie (with-temp-buffer
                   (insert-file-contents file nil 0 300)
                   (string-match-p "lexical-binding: *t" (buffer-substring (point-min) (line-end-position)))))
         (warnings (append (unless cookie
                             (list "line 1: no -*- lexical-binding: t; -*- there (its code is read so anyway)"))
                           (agent-ui-panel--compile file name))))
    (append (list :ok t :panel name :file file
                  :type (format "%s" (plist-get (plist-get panel :ui) :type)))
            (when (plist-get panel :every) (list :every (plist-get panel :every)))
            (list :warnings (vconcat warnings)
                  :blocking (vconcat (agent-ui-panel--blocking file))))))

(declare-function agent-ui--byte-compile "staging")

;; ====== OPENING ONE ======
;; On demand: a canvas of its own (no session's), named after the panel and
;; its project, in its own pane (config/tiling places it), selected; its
;; directory the project's root (its commands run there, its files are
;; there). Its :ui drawn as it is, empty; its script fills it. Opened again
;; while it's open: its pane shown. q kills it; opened later (after a
;; restart too), it's read again and fetched anew: nothing of it is kept.

(cl-defstruct (agent-ui-panel--state (:constructor agent-ui-panel--make)
                                     (:conc-name agent-ui-panel--))
  "An open project panel, in its canvas (`agent-ui-panel--state')."
  name file root canvas)

(defvar-local agent-ui-panel--state nil
  "In a project panel's canvas: the panel (an `agent-ui-panel--state').")

(defun agent-ui-panel-canvas-name (name root)
  "The name of panel NAME's canvas, of the project at ROOT: \"NAME (PROJECT)\"
\(no session's: tied to none)."
  (format "%s (%s)" name (file-name-nondirectory (directory-file-name root))))

(defun agent-ui-panel--read-name ()
  "A panel of the current project, picked."
  (let ((panels (agent-ui-panels)))
    (unless panels
      (user-error (if (agent-ui-panel-root)
                      (format "This project has no panels (%s)" agent-ui-panel-directory)
                    "No project here")))
    (completing-read "Panel: " panels nil t)))

(defun agent-ui-open-panel (name &optional dir)
  "Open panel NAME of DIR's project (default: the current buffer's; NAME
ending .el: a file): its :ui drawn in a canvas of its own, in its pane,
selected. Open already: its pane shown. Interactively, the project's panels
to pick from. Returns its canvas."
  (interactive (list (agent-ui-panel--read-name)))
  (let* ((file (agent-ui-panel-file name dir))
         (root (or (agent-ui-panel-root (file-name-directory file))
                   (file-name-directory file)))
         (canvas-name (agent-ui-panel-canvas-name (file-name-base file) root))
         (open (get-buffer (agent-ui-canvas-buffer-name canvas-name))))
    (if (and open (buffer-local-value 'agent-ui-panel--state open))
        (progn (pop-to-buffer open) open)
      ;; Read first: a wrong one leaves no canvas behind.
      (let* ((panel (agent-ui-panel-read file))
             (canvas (let ((default-directory root))
                       (agent-ui-canvas canvas-name))))
        (with-current-buffer canvas
          (setq default-directory root
                agent-ui-panel--state (agent-ui-panel--make :name (plist-get panel :name) :file file
                                                            :root root :canvas canvas)))
        (condition-case err
            (let ((agent-ui-display-function #'ignore)
                  (agent-ui-file-directory root))
              (agent-ui-show (plist-get panel :ui) :canvas canvas))
          (error (kill-buffer canvas)
                 (signal (car err) (cdr err))))
        (pop-to-buffer canvas)
        canvas))))
