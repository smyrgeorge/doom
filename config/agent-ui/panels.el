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

(defconst agent-ui-panels--keys '(:version :ui :every :fetch :start :stop)
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
           unless (memq key agent-ui-panels--keys)
           do (error "agent-ui-panel has %S: it has %s" key
                     (mapconcat (lambda (k) (substring (symbol-name k) 1)) agent-ui-panels--keys ", ")))
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

(defun agent-ui-panels--forms (file what)
  "FILE's top-level forms, read, not evaluated; an error for WHAT saying
where it doesn't read."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (goto-char (point-min))
    (let (forms)
      (condition-case err
          ;; Lisp's comments skipped (a plain buffer has none: a comment
          ;; after the last form was read as one, cut short).
          (with-syntax-table emacs-lisp-mode-syntax-table
            (while (progn (forward-comment (buffer-size)) (not (eobp)))
              (push (read (current-buffer)) forms)))
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
         (forms (agent-ui-panels--forms file what))
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
             unless (memq key agent-ui-panels--keys)
             do (agent-ui--fail "%s has %s: a panel has %s" what (agent-ui--show-value key)
                                (mapconcat (lambda (k) (substring (symbol-name k) 1)) agent-ui-panels--keys ", ")))
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

(defun agent-ui-panels--blocking (file)
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

(defun agent-ui-panels--compile (file name)
  "FILE's code (panel NAME's) compiled, its warnings (an error if it doesn't
compile), their lines FILE's. In a function: at top level, a lambda's body
isn't looked at (its warnings unsaid)."
  (let ((temp (make-temp-file "agent-ui-panel-" nil ".el")))
    (unwind-protect
        (progn
          (with-temp-file temp
            (setq-local coding-system-for-write 'utf-8)
            (insert ";;; -*- lexical-binding: t; -*-\n(defun agent-ui-panels--checking ()\n")
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
                           (agent-ui-panels--compile file name))))
    (append (list :ok t :panel name :file file
                  :type (format "%s" (plist-get (plist-get panel :ui) :type)))
            (when (plist-get panel :every) (list :every (plist-get panel :every)))
            (list :warnings (vconcat warnings)
                  :blocking (vconcat (agent-ui-panels--blocking file))))))

(declare-function agent-ui--byte-compile "staging")

;; ====== OPENING ONE ======
;; On demand: a canvas of its own (no session's), named after the panel and
;; its project, in its own pane (config/tiling places it), selected; its
;; directory the project's root (its commands run there, its files are
;; there). Its :ui drawn as it is, empty; its script fills it. Opened again
;; while it's open: its pane shown. q kills it; opened later (after a
;; restart too), it's read again and fetched anew: nothing of it is kept.

(cl-defstruct (agent-ui-panels--state (:constructor agent-ui-panels--make)
                                     (:conc-name agent-ui-panels--))
  "An open project panel, in its canvas (`agent-ui-panels--state'): what its
script is given as PANEL. Its :ui (read), its script (its form evaluated),
its fetches' timer, its commands running, its last error."
  name file root canvas ui script timer processes error
  ;; A fetch missed while it was hidden; what's wrong now, by key ((KEY TEXT
  ;; . ELEMENT) ...: said on ELEMENT's title, else on its line); the queries
  ;; running, by key (:process :start :element); the titles of its elements
  ;; marked (loading, failed), as they were ((ID . TITLE) ...); the timer
  ;; saying how long they've been loading.
  stale errors (running (make-hash-table :test #'equal)) titles ticker)

(defvar-local agent-ui-panels--state nil
  "In a project panel's canvas: the panel (an `agent-ui-panels--state').")

(defun agent-ui-panel-canvas-name (name root)
  "The name of panel NAME's canvas, of the project at ROOT: \"NAME (PROJECT)\"
\(no session's: tied to none)."
  (format "%s (%s)" name (file-name-nondirectory (directory-file-name root))))

(defun agent-ui-panels--read-name ()
  "A panel of the current project, picked."
  (let ((panels (agent-ui-panels)))
    (unless panels
      (user-error (if (agent-ui-panel-root)
                      (format "This project has no panels (%s)" agent-ui-panel-directory)
                    "No project here")))
    (completing-read "Panel: " panels nil t)))

(defun agent-ui-open-panel (name &optional dir noselect here)
  "Open panel NAME of DIR's project (default: the current buffer's; NAME
ending .el: a file): its :ui drawn in a canvas of its own, in its pane,
selected (NOSELECT: shown only, its code started a moment later, after the
agent's request is answered: asking to let it, if it must, then; HERE: in
the selected window instead, `agent-ui-open-panel-here'). Open already: its
pane shown (HERE: shown here). Interactively, the project's panels to pick
from. Returns its canvas."
  (interactive (list (agent-ui-panels--read-name)))
  (let* ((file (agent-ui-panel-file name dir))
         (root (or (agent-ui-panel-root (file-name-directory file))
                   (file-name-directory file)))
         (canvas-name (agent-ui-panel-canvas-name (file-name-base file) root))
         (open (get-buffer (agent-ui-canvas-buffer-name canvas-name))))
    (if (and open (buffer-local-value 'agent-ui-panels--state open))
        (progn (cond (noselect (display-buffer open))
                     (here (switch-to-buffer open))
                     (t (pop-to-buffer open)))
               open)
      ;; Read first: a wrong one leaves no canvas behind.
      (let* ((read (agent-ui-panel-read file))
             (canvas (let ((default-directory root))
                       (agent-ui-canvas canvas-name)))
             (panel (agent-ui-panels--make :name (plist-get read :name) :file file :root root
                                          :canvas canvas :ui (plist-get read :ui))))
        (with-current-buffer canvas
          (setq default-directory root
                agent-ui-panels--state panel)
          (add-hook 'kill-buffer-hook #'agent-ui-panels--closed nil t)
          (add-hook 'window-buffer-change-functions #'agent-ui-panels--shown nil t))
        (condition-case err
            ;; Its elements' sources (commands) not started yet: they're
            ;; its code too, run once it's allowed to.
            (agent-ui-panels--draw panel (agent-ui-persist--without-sources (plist-get read :ui)))
          (error (kill-buffer canvas)
                 (signal (car err) (cdr err))))
        (if noselect
            (progn (display-buffer canvas)
                   (run-with-timer 0 nil #'agent-ui-panels--start panel (plist-get read :form)))
          (if here (switch-to-buffer canvas) (pop-to-buffer canvas))
          (agent-ui-panels--start panel (plist-get read :form)))
        canvas))))

(defun agent-ui-open-panel-here (name &optional dir)
  "Open panel NAME of DIR's project as `agent-ui-open-panel' does, but in
the selected window, not a pane of its own (SPC o U)."
  (interactive (list (agent-ui-panels--read-name)))
  (agent-ui-open-panel name dir nil t))

(defun agent-ui-panel-canvas (name &optional dir)
  "The canvas of panel NAME of DIR's project, open; an error if it isn't."
  (let* ((root (or (agent-ui-panel-root dir) (agent-ui--fail "panel %s: no project here" name)))
         (buffer (get-buffer (agent-ui-canvas-buffer-name (agent-ui-panel-canvas-name name root)))))
    (unless (and buffer (buffer-local-value 'agent-ui-panels--state buffer))
      (agent-ui--fail "panel %s isn't open: agent-ui open %s" name name))
    buffer))

(defun agent-ui-panels--draw (panel ui)
  "UI, PANEL's elements, shown in its canvas (its files its root's)."
  (let ((agent-ui-display-function #'ignore)
        (agent-ui-file-directory (agent-ui-panels--root panel)))
    (agent-ui-show ui :canvas (agent-ui-panels--canvas panel))))

;; ====== ITS SCRIPT ======
;; Its code runs as Emacs itself: allowed first (`agent-ui-panel-allow-
;; function'), then its form evaluated (lexical, nothing global defined), its
;; :ui drawn again with its sources, :start called, :fetch at once and every
;; :every seconds; :stop when its canvas closes, its timer stopped, its
;; commands killed. Each called with PANEL, in its root (`default-
;; directory'); an error of one kept in PANEL and said, the others go on.

(defvar agent-ui-panel-allow-function #'agent-ui-panels--allowed-p
  "Called with a panel (an `agent-ui-panels--state') whose code (its script,
its elements' sources) is to run: non-nil lets it.")

;; ====== TRUSTING ONE ======
;; A panel's file comes from a repository and runs as Emacs itself: before
;; its code first runs, the user is asked (run it, view its file first, or not
;; now); run, it's remembered by its file's content (sha256), in
;; `agent-ui-panel-trust-file': asked again once it changes. Not now: drawn,
;; nothing run, said on it; gR asks again.

(defcustom agent-ui-panel-trust-file (locate-user-emacs-file "agent-ui/trusted-panels.eld")
  "Where the panels whose code the user let run are remembered: their
files' content's sha256."
  :type 'file :group 'agent-ui)

(defun agent-ui-panels--hash (file)
  "FILE's content's sha256."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun agent-ui-panels--trusted ()
  "The trusted panels: ((HASH FILE TIME) ...)."
  (when (file-readable-p agent-ui-panel-trust-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents agent-ui-panel-trust-file)
          (let ((data (read (current-buffer))))
            (and (listp data) data)))
      (error nil))))

(defun agent-ui-panel-trusted-p (file)
  "Whether panel FILE's code, as it is now, was let run."
  (and (assoc (agent-ui-panels--hash file) (agent-ui-panels--trusted)) t))

(defun agent-ui-panel-trust (file)
  "Remember panel FILE's code, as it is now, as let run (its older contents
forgotten)."
  (let* ((file (expand-file-name file))
         (entries (cons (list (agent-ui-panels--hash file) file (format-time-string "%FT%T%z"))
                        (seq-remove (lambda (e) (equal (nth 1 e) file)) (agent-ui-panels--trusted)))))
    (make-directory (file-name-directory agent-ui-panel-trust-file) t)
    (with-temp-file agent-ui-panel-trust-file
      (let ((print-length nil) (print-level nil))
        (insert ";; Agent UI: the project panels whose code was let run, by content (sha256).\n")
        (prin1 entries (current-buffer))
        (insert "\n")))))

(defun agent-ui-panels--allowed-p (panel)
  "Whether PANEL's code may run: its file trusted as it is; else the user
asked (it view-ed first if they say), a yes remembered."
  (let ((file (agent-ui-panels--file panel)))
    (or (agent-ui-panel-trusted-p file)
        (let ((answer nil))
          (while (not answer)
            (pcase (car (read-multiple-choice
                         (format "Panel %s runs code from %s, as Emacs itself (its commands too). Run it?"
                                 (agent-ui-panels--name panel) (abbreviate-file-name file))
                         '((?y "run it" "Let its code run, remembered until its file changes")
                           (?v "view it" "Its file first, read-only; asked again after")
                           (?n "not now" "Drawn, nothing run (gR asks again)"))))
              (?y (agent-ui-panel-trust file) (setq answer 'yes))
              (?v (view-file-other-window file))
              (_ (setq answer 'no))))
          (eq answer 'yes)))))

(defun agent-ui-panels--code-p (form ui)
  "Whether a panel (its FORM, its UI) has code to run: a script, or a source
in its elements."
  (or (cl-some (lambda (key) (plist-get (cdr form) key)) '(:fetch :start :stop))
      (let ((found nil))
        (cl-labels ((walk (e)
                      (when (agent-ui--plist-p e)
                        (when (plist-get e :source) (setq found t))
                        (mapc #'walk (plist-get e :children)))))
          (walk ui))
        found)))

(defun agent-ui-panels--failed (panel what err &optional key element)
  "PANEL's WHAT (\"fetch\", a command...) failed with ERR (an error, or a
message): kept by KEY (default WHAT) until it goes well, said: on ELEMENT's
title if given, else on the panel's line."
  (let ((text (format "%s: %s" what (if (stringp err) err (agent-ui-error-message err))))
        (key (or key what)))
    (setf (agent-ui-panels--error panel) text
          (alist-get key (agent-ui-panels--errors panel) nil nil #'equal) (cons text element))
    (message "Agent UI: panel %s: %s" (agent-ui-panels--name panel) text)
    (agent-ui-panels--said panel)
    nil))

(defun agent-ui-panels--well (panel key)
  "PANEL's KEY (a query, \"fetch\") went well: its error gone."
  (when (assoc key (agent-ui-panels--errors panel))
    (setf (agent-ui-panels--errors panel)
          (cl-remove key (agent-ui-panels--errors panel) :key #'car :test #'equal))
    (unless (agent-ui-panels--errors panel)
      (setf (agent-ui-panels--error panel) nil))
    (agent-ui-panels--said panel)))

(defun agent-ui-panels--said (panel)
  "What's wrong with PANEL, and what's loading, said: its line (errors of no
element, one line each), its elements' titles (loading, how long; failed)."
  (when (agent-ui-panels--live-p panel)
    (let ((lines (delq nil (mapcar (lambda (e) (unless (cddr e) (concat "⚠ " (cadr e))))
                                   (reverse (agent-ui-panels--errors panel))))))
      (agent-ui-panels--status panel (and lines (string-join lines "\n"))))
    (agent-ui-panels--mark panel)))

(defun agent-ui-panels--mark (panel)
  "PANEL's elements' titles: one loading, \"⟳ loading, 1m 12s\" after it;
one failed, its error; the others as they were."
  (let ((canvas (agent-ui-panels--canvas panel))
        (now (float-time))
        (marks nil))
    (maphash (lambda (_key run)
               (when-let* ((id (plist-get run :element)))
                 (let ((took (- now (plist-get run :start))))
                   (unless (and (assoc id marks) (< took (cdr (assoc id marks))))
                     (setf (alist-get id marks nil nil #'equal) took)))))
             (agent-ui-panels--running panel))
    (setq marks (mapcar (lambda (m) (cons (car m) (concat "⟳ loading, " (agent-ui-format-duration (cdr m)))))
                        marks))
    (dolist (e (agent-ui-panels--errors panel))
      (when-let* ((id (cddr e)))
        (unless (assoc id marks)
          (push (cons id (concat "⚠ " (cadr e))) marks))))
    (let ((agent-ui-display-function #'ignore))
      (pcase-dolist (`(,id . ,mark) marks)
        (unless (assoc id (agent-ui-panels--titles panel))
          (when-let* ((element (ignore-errors (agent-ui-get id :canvas canvas))))
            (push (cons id (plist-get element :title)) (agent-ui-panels--titles panel))))
        (when-let* ((entry (assoc id (agent-ui-panels--titles panel))))
          (ignore-errors
            (agent-ui-update id (list :title (if (cdr entry) (concat (cdr entry) "  " mark) mark))
                             :canvas canvas))))
      ;; Marked no more: as it was.
      (dolist (entry (agent-ui-panels--titles panel))
        (unless (assoc (car entry) marks)
          (ignore-errors (agent-ui-update (car entry) (list :title (cdr entry)) :canvas canvas))
          (setf (agent-ui-panels--titles panel) (delq entry (agent-ui-panels--titles panel))))))))

(defun agent-ui-panels--tick (panel)
  "PANEL's loading elements' times, said; none loading: the ticker stops."
  (let ((loading nil))
    (maphash (lambda (_key run) (when (plist-get run :element) (setq loading t)))
             (agent-ui-panels--running panel))
    (if (and loading (agent-ui-panels--live-p panel))
        (agent-ui-panels--mark panel)
      (when (timerp (agent-ui-panels--ticker panel))
        (cancel-timer (agent-ui-panels--ticker panel)))
      (setf (agent-ui-panels--ticker panel) nil))))

(defconst agent-ui-panels--status-id "panel.status"
  "The id of the line under a panel saying what went wrong.")

(defun agent-ui-panels--status (panel text)
  "PANEL's lines under it saying TEXT (what went wrong, a line each, \"⚠\"
before), or gone (TEXT nil)."
  (when (agent-ui-panels--live-p panel)
    (let ((canvas (agent-ui-panels--canvas panel))
          (agent-ui-display-function #'ignore))
      (if text
          (agent-ui-show (list :type "text" :id agent-ui-panels--status-id :face "error"
                               :text text)
                         :canvas canvas)
        (when (member agent-ui-panels--status-id (buffer-local-value 'agent-ui--order canvas))
          (agent-ui-remove agent-ui-panels--status-id :canvas canvas))))))

(defun agent-ui-panels--call (panel key)
  "PANEL's script's KEY (:fetch, :start, :stop) called with it, in its root;
an error of it kept and said. Non-nil if it went well."
  (if-let* ((fn (plist-get (agent-ui-panels--script panel) key)))
      (let ((default-directory (agent-ui-panels--root panel)))
        (condition-case err
            (progn (funcall fn panel) t)
          (error (agent-ui-panels--failed panel (substring (symbol-name key) 1) err))))
    t))

(defun agent-ui-panels--live-p (panel)
  (buffer-live-p (agent-ui-panels--canvas panel)))

(defun agent-ui-panels--start (panel form)
  "PANEL's code started, if it has some and it's allowed: FORM (its file's)
evaluated, its :ui drawn again with its sources, :start, :fetch now and
every :every seconds."
  (when (and (agent-ui-panels--code-p form (agent-ui-panels--ui panel))
             (or (funcall agent-ui-panel-allow-function panel)
                 (agent-ui-panels--failed panel "its code" "not run, not let: gR asks again"))
             (agent-ui-panels--live-p panel))
    (let ((script (condition-case err
                      (let ((default-directory (agent-ui-panels--root panel)))
                        (eval form t))
                    (error (agent-ui-panels--failed panel "its code" err)))))
      (setf (agent-ui-panels--script panel) script)
      (condition-case err
          (agent-ui-panels--draw panel (agent-ui-panels--ui panel))
        (error (agent-ui-panels--failed panel "its :ui" err)))
      (when script
        (agent-ui-panels--call panel :start)
        (agent-ui-panels--fetch panel)
        (when-let* ((every (plist-get script :every)))
          (setf (agent-ui-panels--timer panel)
                (run-with-timer every every #'agent-ui-panels--fetch panel)))))))

(defcustom agent-ui-panel-slow 0.1
  "Seconds a panel's fetch may take itself (its commands apart), Emacs
frozen meanwhile, before it's said."
  :type 'number :group 'agent-ui)

(defun agent-ui-panels--visible-p (panel)
  (get-buffer-window (agent-ui-panels--canvas panel) t))

(defun agent-ui-panels--fetch (panel)
  "PANEL's :fetch, once: not while it's hidden (fetched when it's shown
again); its canvas gone, stopped. Its queries each their own: one still
running isn't started again, the others are (`agent-ui-panel-run'). Taking
long itself (Emacs frozen), said."
  (cond
   ((not (agent-ui-panels--live-p panel)) (agent-ui-panels--stop panel))
   ((not (agent-ui-panels--visible-p panel)) (setf (agent-ui-panels--stale panel) t))
   (t
    (setf (agent-ui-panels--stale panel) nil)
    (let* ((start (float-time))
           (well (agent-ui-panels--call panel :fetch))
           (took (- (float-time) start)))
      (cond
       ((> took agent-ui-panel-slow)
        (agent-ui-panels--failed
         panel "fetch" (format "took %.2f s itself, Emacs frozen meanwhile: run commands with agent-ui-panel-run"
                               took)))
       (well (agent-ui-panels--well panel "fetch")))))))

(defun agent-ui-panels--shown (window)
  "WINDOW shows a panel's canvas now (its `window-buffer-change-functions'):
a fetch missed while it was hidden, done."
  (when-let* ((buffer (window-buffer window))
              (panel (buffer-local-value 'agent-ui-panels--state buffer))
              ((agent-ui-panels--stale panel))
              ((agent-ui-panels--script panel)))
    (run-with-timer 0 nil #'agent-ui-panels--fetch panel)))

(defun agent-ui-panels--stop (panel)
  "PANEL's timer stopped, its commands killed, its :stop called."
  (when (timerp (agent-ui-panels--timer panel))
    (cancel-timer (agent-ui-panels--timer panel)))
  (setf (agent-ui-panels--timer panel) nil)
  (when (timerp (agent-ui-panels--ticker panel))
    (cancel-timer (agent-ui-panels--ticker panel)))
  (setf (agent-ui-panels--ticker panel) nil)
  (dolist (process (agent-ui-panels--processes panel))
    (when (process-live-p process) (delete-process process)))
  (setf (agent-ui-panels--processes panel) nil)
  (clrhash (agent-ui-panels--running panel))
  (when (agent-ui-panels--script panel)
    (agent-ui-panels--call panel :stop)
    (setf (agent-ui-panels--script panel) nil)))

(defun agent-ui-panels--closed ()
  "A panel's canvas closes (`kill-buffer-hook'): its script stopped."
  (when agent-ui-panels--state
    (agent-ui-panels--stop agent-ui-panels--state)))

(defun agent-ui-panel-reload ()
  "The project panel here read again from its file (edited), drawn anew,
its code run again (gR). Its file wrong now: said on it, it goes on as it
was."
  (interactive)
  (let ((panel agent-ui-panels--state))
    (unless panel
      (user-error "Not a project panel: gR reloads one (SPC o u opens one)"))
    (condition-case err
        (let* ((read (agent-ui-panel-read (agent-ui-panels--file panel)))
               (ui (plist-get read :ui))
               (canvas (agent-ui-panels--canvas panel)))
          (agent-ui-panels--stop panel)
          (setf (agent-ui-panels--ui panel) ui
                (agent-ui-panels--error panel) nil
                (agent-ui-panels--errors panel) nil
                (agent-ui-panels--titles panel) nil
                (agent-ui-panels--stale panel) nil)
          ;; Drawn first, the others removed after: never empty (an empty
          ;; canvas closes its pane).
          (agent-ui-panels--draw panel (agent-ui-persist--without-sources ui))
          (let ((id (plist-get ui :id)))
            (dolist (old (buffer-local-value 'agent-ui--order canvas))
              (unless (equal old id)
                (agent-ui-remove old :canvas canvas))))
          (agent-ui-panels--start panel (plist-get read :form))
          (message "Panel %s: read again" (agent-ui-panels--name panel)))
      (agent-ui-error (agent-ui-panels--failed panel "its file" err)))))

;; ====== WHAT ITS SCRIPT CALLS ======

(defun agent-ui-panels--change (panel id props change)
  "Element ID of PANEL changed by PROPS (a plist) with CHANGE
\(`agent-ui-update' or `agent-ui-append'); a closed panel: nothing."
  (when (agent-ui-panels--live-p panel)
    (funcall change id props :canvas (agent-ui-panels--canvas panel))))

(defun agent-ui-panel-update (panel id &rest props)
  "Change PANEL's element ID by PROPS, as agent-ui update does:
\(agent-ui-panel-update panel \"ci\" :rows rows). A property nil: back to its
default. An error if PANEL has no element ID or the change makes it wrong."
  (agent-ui-panels--change panel id props #'agent-ui-update))

(defun agent-ui-panel-append (panel id &rest props)
  "Add PROPS' lists to PANEL's element ID, as agent-ui append does: a table's
rows (replaced by its key), a chart's values: (agent-ui-panel-append panel
\"errors\" :values (list 3))."
  (agent-ui-panels--change panel id props #'agent-ui-append))

(defun agent-ui-panel-get (panel id)
  "PANEL's element ID, its properties as they are now (a plist)."
  (agent-ui-get id :canvas (agent-ui-panels--canvas panel)))

(defun agent-ui-panels--output (text)
  "A command's output TEXT: parsed JSON (objects as alists, arrays as
lists, null and false nil) when it reads so; else TEXT."
  (or (and (string-match-p "\\`[ \t\n]*[[{]" text)
           (condition-case nil
               (json-parse-string text :object-type 'alist :array-type 'list
                                  :null-object nil :false-object nil)
             (error nil)))
      text))

(cl-defun agent-ui-panel-run (panel command callback &key element timeout)
  "Run COMMAND (a list: a program and its arguments; a string: by the shell)
in PANEL's root, without waiting, however long it takes: CALLBACK then
called with its output (see `agent-ui-panels--output'), if it ends well
\(exit 0); else its error is said. ELEMENT: the id of the element it fills,
its title saying it's loading (and how long) meanwhile, its data kept, its
error said on it. A query (its ELEMENT, else its COMMAND) still running
isn't started again: nil then; the others are, each on its own. TIMEOUT:
seconds, it killed after them (an error). Killed when PANEL closes.
Returns its process."
  (let ((key (or element (if (stringp command) command (string-join command " "))))
        (running (agent-ui-panels--running panel)))
    (unless (gethash key running)
      (let* ((default-directory (agent-ui-panels--root panel))
             (name (format "agent-ui-panel-%s" (agent-ui-panels--name panel)))
             (out (generate-new-buffer (format " *%s*" name) t))
             (err (generate-new-buffer (format " *%s stderr*" name) t))
             (program (if (stringp command) command (car command)))
             (timed-out nil)
             (process
              (make-process
               :name name :buffer out :stderr err :noquery t :connection-type 'pipe
               :command (if (stringp command) (list shell-file-name shell-command-switch command) command)
               :sentinel
               (lambda (process _event)
                 (unless (process-live-p process)
                   (setf (agent-ui-panels--processes panel) (delq process (agent-ui-panels--processes panel)))
                   (when (eq (plist-get (gethash key running) :process) process)
                     (remhash key running))
                   (let ((text (with-current-buffer out (buffer-string)))
                         (errors (string-trim (with-current-buffer err (buffer-string))))
                         (code (process-exit-status process)))
                     (kill-buffer out)
                     (when (buffer-live-p err) (kill-buffer err))
                     (when (agent-ui-panels--live-p panel)
                       (cond
                        (timed-out
                         (agent-ui-panels--failed panel program (format "timed out after %s s" timeout) key element))
                        ((and (eq (process-status process) 'exit) (= code 0))
                         (when (let ((default-directory (agent-ui-panels--root panel)))
                                 (condition-case e
                                     (progn (funcall callback (agent-ui-panels--output text)) t)
                                   (error (agent-ui-panels--failed panel program e key element))))
                           (agent-ui-panels--well panel key)))
                        (t
                         (agent-ui-panels--failed
                          panel program
                          (format "exit %s%s" code
                                  (let ((last (car (last (split-string (if (string-empty-p errors) text errors)
                                                                       "\n" t)))))
                                    (if last (concat ": " last) "")))
                          key element)))
                       ;; Its element loading no more.
                       (agent-ui-panels--mark panel))))))))
        ;; Its stderr's pipe: no query, no "finished" line in what it said.
        (when-let* ((stderr (get-buffer-process err)))
          (set-process-query-on-exit-flag stderr nil)
          (set-process-sentinel stderr #'ignore))
        (push process (agent-ui-panels--processes panel))
        (puthash key (list :process process :start (float-time) :element element) running)
        (when timeout
          (run-with-timer timeout nil (lambda ()
                                        (when (process-live-p process)
                                          (setq timed-out t)
                                          (delete-process process)))))
        (when element
          (agent-ui-panels--mark panel)
          (unless (timerp (agent-ui-panels--ticker panel))
            (setf (agent-ui-panels--ticker panel)
                  (run-with-timer 1 1 #'agent-ui-panels--tick panel))))
        process))))

(declare-function agent-ui-persist--without-sources "persist")

;; ====== SAVING ONE ======
;; S on a canvas: the element at point (a top-level one; a child: its panel)
;; saved as one of the project's panels, as it was shown (its data, the
;; updates and its sources' changes, left out), with a :fetch to write;
;; the user made it: trusted as it's written.

(defun agent-ui-panels--file-text (name ui)
  "A panel file's text: panel NAME showing UI, its code to write."
  (concat
   (format ";;; %s.el --- Agent UI panel%s -*- lexical-binding: t; -*-\n" name
           (if-let* ((title (plist-get ui :title))) (concat ": " title) ""))
   ";; Saved from a canvas (S): what it shows, its data left out. Its code fills it:\n"
   ";; see the agent-ui skill's references/panels.md (agent-ui check NAME checks it).\n"
   "(agent-ui-panel\n :version 1\n :ui "
   (string-trim (replace-regexp-in-string "\n" "\n     " (pp-to-string ui)))
   "\n :every 30\n :fetch (lambda (panel)\n          ;; (agent-ui-panel-update panel \"ID\" :prop value)\n"
   "          (ignore panel)))\n"))

(defun agent-ui-save-panel (name)
  "Save the element at point, as it was shown, as the project's panel NAME
\(S): its file, .agent-ui/panels/NAME.el, written (asked before replacing
one), trusted (the user made it)."
  (interactive
   (progn
     (unless (derived-mode-p 'agent-ui-canvas-mode) (user-error "Not a canvas"))
     (list (read-string "Save as the project's panel: "
                        (agent-ui--entry-id (car (agent-ui--resolve (agent-ui--element-at-point))))))))
  (unless (string-match-p "\\`[A-Za-z0-9][A-Za-z0-9_.-]*\\'" name)
    (user-error "A panel's name: letters, digits, _ . -"))
  (let* ((root (or (agent-ui-panel-root)
                   (user-error "No project here (this canvas's folder: %s)" default-directory)))
         (id (agent-ui--entry-id (car (agent-ui--resolve (agent-ui--element-at-point)))))
         (ui (agent-ui-shown-element id :canvas (current-buffer)))
         (folder (expand-file-name agent-ui-panel-directory root))
         (file (expand-file-name (concat name ".el") folder)))
    (when (and (file-exists-p file)
               (not (y-or-n-p (format "Panel %s is there already: replace it? " name))))
      (user-error "Not saved"))
    (make-directory folder t)
    (with-temp-file file
      (setq-local coding-system-for-write 'utf-8)
      (insert (agent-ui-panels--file-text name ui)))
    (agent-ui-panel-trust file)
    (message "Saved as panel %s (%s): SPC o u opens it; its :fetch is to write"
             name (abbreviate-file-name file))
    file))

(declare-function agent-ui--element-at-point "snapshot")
