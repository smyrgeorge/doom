;;; $DOOMDIR/config/agent-workflow/core.el -*- lexical-binding: t; -*-
;; What the rest of agent-workflow uses: a project (its main checkout), the
;; places its workflows and profiles come from, their problems, the
;; variables a prompt may name. Loaded from config/agent-workflow.el. No Doom
;; here.
;;
;; A project's workflows and profiles come from three places, in order, a
;; later one's replacing an earlier one's of the same name: the starters
;; (shipped here, config/agent-workflow/workflows/ and profiles/), the
;; project's (.agent-workflow/, committed: read from your checkout, the
;; project's main one, never an agent's worktree) and yours
;; (.agent-shell/agent-workflow/, out of git).
;;
;; A problem is (LEVEL "FILE:LINE: what" FILE LINE "what"), LEVEL error or
;; warning: an error leaves its file out, a warning doesn't.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

;; ====== THE PROJECT ======

(defun agent-workflow-project (&optional directory)
  "The project of DIRECTORY (default: `default-directory'): its git
repository's main checkout (from one of its worktrees too), or nil."
  (let ((default-directory (file-name-as-directory
                            (expand-file-name (or directory default-directory)))))
    (when-let* ((common (and (file-directory-p default-directory)
                             (agent-workflow--git-line "rev-parse" "--path-format=absolute"
                                                       "--git-common-dir"))))
      ;; The common folder is the main checkout's .git (a bare repository
      ;; has none).
      (when (equal (file-name-nondirectory (directory-file-name common)) ".git")
        (file-name-as-directory (file-truename (file-name-directory (directory-file-name common))))))))

(defun agent-workflow--git-line (&rest args)
  "The first line git prints for ARGS in `default-directory', or nil if it
fails."
  (with-temp-buffer
    (when (eql 0 (apply #'process-file "git" nil '(t nil) nil args))
      (goto-char (point-min))
      (let ((line (buffer-substring-no-properties (point) (line-end-position))))
        (unless (string-empty-p line) line)))))

;; ====== WHERE THEY COME FROM ======

(defvar agent-workflow-starters-directory
  (expand-file-name "agent-workflow/" (file-name-directory (or load-file-name buffer-file-name)))
  "Where the starters are: its workflows/ and profiles/, shipped with
this config.")

(defvar agent-workflow-directory)
(defvar agent-workflow-local-directory)

(defun agent-workflow--places (project kind)
  "Where PROJECT's KIND (\"workflows\" or \"profiles\") come from, in
order (a later one's replace an earlier one's of the same name): ((ORIGIN .
FOLDER)...), ORIGIN starter, project or local."
  (cons (cons 'starter (expand-file-name kind agent-workflow-starters-directory))
        (when project
          (list (cons 'project (expand-file-name kind (expand-file-name agent-workflow-directory project)))
                (cons 'local (expand-file-name kind (expand-file-name agent-workflow-local-directory project)))))))

(defun agent-workflow--files (project kind regexp)
  "PROJECT's KIND files whose names match REGEXP, in order (see
`agent-workflow--places'): ((ORIGIN . FILE)...)."
  (seq-mapcat (lambda (place)
                (when (file-directory-p (cdr place))
                  (mapcar (lambda (file) (cons (car place) file))
                          (directory-files (cdr place) t regexp))))
              (agent-workflow--places project kind)))

(defun agent-workflow--stamp (files)
  "FILES ((ORIGIN . FILE)...) and their modification times: whether one
changed since."
  (mapcar (lambda (file)
            (cons (cdr file) (file-attribute-modification-time (file-attributes (cdr file)))))
          files))

(defconst agent-workflow--name-regexp "\\`[a-z][a-z0-9-]*\\'"
  "A workflow's, a profile's, a job's name: a lowercase letter, then
lowercase letters, digits or -.")

;; ====== PROBLEMS ======

(defun agent-workflow--problem (level file line format &rest args)
  "A problem of FILE at LINE: (LEVEL \"FILE:LINE: what\" FILE LINE
\"what\"), what FORMAT with ARGS."
  (let ((what (apply #'format format args)))
    (list level (format "%s:%d: %s" (abbreviate-file-name file) line what) file line what)))

(defun agent-workflow--by-line (problems)
  "PROBLEMS (a file's) in the order of their lines, those of one line as
they were."
  (sort (copy-sequence problems) (lambda (a b) (< (nth 3 a) (nth 3 b)))))

(defun agent-workflow--listed (names)
  "NAMES as a problem lists them: a, b, c; none."
  (if names (string-join names ", ") "none"))

(defun agent-workflow--errors-p (problems)
  "Non-nil if PROBLEMS have an error."
  (assq 'error problems))

;; ====== DURATIONS ======

(defun agent-workflow--duration (value)
  "VALUE (a number of seconds, or text: 45s, 10m, 3h, 1h30m) as seconds,
or nil if it isn't one."
  (cond
   ((and (integerp value) (> value 0)) value)
   ((and (stringp value) (string-match-p "\\`\\(?:[0-9]+[hms]\\)+\\'" value))
    (let ((seconds 0) (start 0))
      (while (string-match "\\([0-9]+\\)\\([hms]\\)" value start)
        (cl-incf seconds (* (string-to-number (match-string 1 value))
                            (pcase (match-string 2 value) ("h" 3600) ("m" 60) ("s" 1))))
        (setq start (match-end 0)))
      (and (> seconds 0) seconds)))))

;; ====== VARIABLES ======

(defconst agent-workflow-variables
  '("issue" "issue.title" "issue.description" "issue.acceptance" "issue.notes"
    "branch" "main" "main-branch" "worktree" "project" "diff.stat"
    "output" "note" "round" "try")
  "The variables a step's prompt and a profile may name, as {NAME}; and
{jobs.JOB.outcome}, {jobs.JOB.notes}, JOB one of the workflow's jobs.")

(defconst agent-workflow--variable-regexp "{\\([a-z][a-z0-9-]*\\(?:\\.[a-z0-9-]+\\)*\\)}"
  "A {variable} in a text: what looks like one ({ \"a\": 1 } doesn't).")

(defun agent-workflow-variables-in (text)
  "The variables TEXT names: ((NAME . OFFSET)...), in order."
  (let ((start 0) found)
    (while (string-match agent-workflow--variable-regexp text start)
      (push (cons (match-string 1 text) (match-beginning 0)) found)
      (setq start (match-end 0)))
    (nreverse found)))

(defun agent-workflow--variable-job (name)
  "The job NAME (a variable) is about, jobs.JOB.outcome or jobs.JOB.notes;
nil if it isn't one of those."
  (when (string-match "\\`jobs\\.\\([a-z][a-z0-9-]*\\)\\.\\(outcome\\|notes\\)\\'" name)
    (match-string 1 name)))

(defun agent-workflow-variable-p (name)
  "Non-nil if NAME is a variable: one of `agent-workflow-variables', or a
job's outcome or notes."
  (or (member name agent-workflow-variables) (agent-workflow--variable-job name)))

(defun agent-workflow-fill (text values)
  "TEXT, its variables filled in from VALUES (an alist of a variable's name
and its value, a string or nil: empty); one VALUES lacks left as it is."
  (replace-regexp-in-string
   agent-workflow--variable-regexp
   (lambda (match)
     (let ((name (match-string 1 match)))
       (if-let* ((value (assoc name values)))
           (or (cdr value) "")
         match)))
   text t t))

;; ====== A LINE OF A YAML FILE ======
;; yaml.el gives no positions: a problem's line is found again in the text,
;; by indentation (a block's keys more indented than it).

(defun agent-workflow--yaml-lines (text)
  "TEXT's lines as YAML has them: a vector of (INDENT DASH KEY) each, INDENT
the spaces before it (before its dash), DASH the length of its \"- \" (0
without), KEY the mapping key it starts with (nil: none, a blank line or a
comment)."
  (vconcat
   (mapcar (lambda (line)
             (if (string-match "\\`\\([ ]*\\)\\(-[ ]+\\)?\\([^ #:][^:]*\\)?:\\(?:[ ]\\|\\'\\)" line)
                 (list (length (match-string 1 line)) (length (or (match-string 2 line) ""))
                       (match-string 3 line))
               (string-match "\\`\\([ ]*\\)\\(-[ ]+\\)?" line)
               (list (length (match-string 1 line)) (length (or (match-string 2 line) ""))
                     (and (match-string 2 line) (not (string-blank-p (substring line (match-end 0)))) ""))))
           (split-string text "\n"))))

(defun agent-workflow--yaml-line (text path)
  "The line of TEXT (a YAML file's) where PATH is: a list of keys and, for
a list's item, its index from 0 (\"jobs\" \"build\" \"steps\" 1 \"run\").
The deepest found; 1 if not even the first."
  (let* ((lines (agent-workflow--yaml-lines text))
         (from 0) (to (length lines)) (best 1))
    (cl-flet* ((indent (i) (nth 0 (aref lines i)))
               (inner (i) (+ (nth 0 (aref lines i)) (nth 1 (aref lines i))))
               (dash-p (i) (> (nth 1 (aref lines i)) 0))
               (key (i) (nth 2 (aref lines i)))
               (first (from to) (cl-loop for i from from below to when (key i) return i))
               (block-end (i limit)
                 ;; The next line, after I, as little indented as LIMIT.
                 (cl-loop for j from (1+ i) below (length lines)
                          when (and (key j) (<= (indent j) limit)) return j
                          finally return (length lines))))
      (catch 'done
        (dolist (step path)
          (let* ((head (or (first from to) (throw 'done nil)))
                 (found
                  (if (integerp step)
                      (let ((n -1))
                        (cl-loop for i from from below to
                                 when (and (key i) (dash-p i) (= (indent i) (indent head))
                                           (= (cl-incf n) step))
                                 return i))
                    (cl-loop for i from from below to
                             when (and (key i) (= (inner i) (inner head)) (equal (key i) step))
                             return i))))
            (unless found (throw 'done nil))
            (setq best (1+ found))
            (if (integerp step)
                ;; Its first key is on its dash's line.
                (setq from found to (block-end found (indent found)))
              (setq from (1+ found) to (block-end found (inner found))))))))
    best))

(defun agent-workflow--offset-line (text offset)
  "The line of TEXT at OFFSET (from 0)."
  (1+ (cl-count ?\n (substring text 0 (min (max 0 offset) (length text))))))
