;;; $DOOMDIR/config/agent-ui/elements/issues.el -*- lexical-binding: t; -*-
;; Agent UI's issues: a project's Beads issues as a board. Loaded from
;; config/agent-ui/elements.el.
;;
;; Columns Ready (open, nothing blocking them: bd ready), In progress,
;; Blocked (open, waiting on others), Done (closed, the latest first): each
;; issue's id and title, P0/P1 marked. DIR is the project (the agent's
;; directory); PARENT shows an epic's issues only, LABEL those with it. The
;; issues are fetched by bd in the background, kept a while, and fetched
;; again when the element is shown, or `agent-ui-issues-refresh' says (this
;; config: after the agent's bd commands). RET on an issue opens it
;; (`agent-ui-open-issue-function'). Narrow: the columns one under another.

(require 'cl-lib)
(require 'subr-x)

(defcustom agent-ui-open-issue-function #'agent-ui-issues-show
  "Opens an issue, given its id and its project's directory."
  :type 'function :group 'agent-ui)

(defcustom agent-ui-issues-limit 200
  "The most closed issues fetched, the latest (bd list --limit): every one
not closed is."
  :type 'natnum :group 'agent-ui)

(defvar agent-ui-issues--cache (make-hash-table :test #'equal)
  "Projects' issues, by directory: (:issues LIST :ready IDS :error TEXT).")

(defvar agent-ui-issues--fetching nil "Directories whose issues are being fetched.")

;; ====== FETCHING ======

(defun agent-ui-issues--parse (text)
  "bd's output: its ready issues, then those not closed, then the latest
closed, after separator lines."
  (cl-flet ((parse (json) (ignore-errors (json-parse-string json :object-type 'plist :array-type 'list
                                                            :null-object nil))))
    (pcase-let ((`(,ready ,open ,closed) (split-string text "^@@AGENT-UI@@$")))
      (list :ready (mapcar (lambda (i) (plist-get i :id)) (parse ready))
            :issues (append (parse open) (and closed (parse closed)))))))

(defun agent-ui-issues--redraw (dir)
  "Redraw the issues elements of DIR, everywhere: those in a panel too (its
board stayed \"fetching the issues…\")."
  (cl-flet ((board-p (element)
              (and (equal (plist-get element :type) "issues")
                   (equal (file-name-as-directory (or (plist-get element :dir) "")) dir))))
    (dolist (canvas (agent-ui-canvases))
      (with-current-buffer canvas
        (agent-ui--dirty
         (cl-loop for id in agent-ui--order
                  for element = (agent-ui--entry-element (gethash id agent-ui--entries))
                  when (or (board-p element) (seq-some #'board-p (agent-ui--descendants element)))
                  collect id))))))

(defun agent-ui-issues-refresh (dir)
  "Fetch DIR's issues again (in the background), its boards redrawn after."
  (let ((dir (file-name-as-directory (expand-file-name dir))))
    (unless (member dir agent-ui-issues--fetching)
      (if (not (executable-find "bd"))
          (progn (puthash dir (list :error "bd isn't installed") agent-ui-issues--cache)
                 (agent-ui-issues--redraw dir))
        (push dir agent-ui-issues--fetching)
        (let* ((default-directory dir)
               (output (generate-new-buffer " *agent-ui bd*")))
          (make-process
           :name "agent-ui-issues" :buffer output :noquery t :connection-type 'pipe
           ;; Every issue not closed (a limit over all of them, by priority,
           ;; let closed ones push open ones off the board), the latest closed.
           :command (list "sh" "-c" (format (concat "bd ready --json --limit 0; echo; echo @@AGENT-UI@@; "
                                                    "bd list --json --limit 0; echo; echo @@AGENT-UI@@; "
                                                    "bd list --status closed --sort closed --json --limit %d")
                                            agent-ui-issues-limit))
           :sentinel (lambda (process _event)
                       (when (memq (process-status process) '(exit signal))
                         (setq agent-ui-issues--fetching (delete dir agent-ui-issues--fetching))
                         (puthash dir
                                  (if (zerop (process-exit-status process))
                                      (agent-ui-issues--parse (with-current-buffer output (buffer-string)))
                                    (list :error "no Beads issues here (bd failed)"))
                                  agent-ui-issues--cache)
                         (kill-buffer output)
                         (agent-ui-issues--redraw dir)))))))))

(defun agent-ui-issues--shown (_id element)
  "An issues element shown: its issues fetched again."
  (when (equal (plist-get element :type) "issues")
    (agent-ui-issues-refresh (or (plist-get element :dir) default-directory))))

(add-hook 'agent-ui-shown-functions #'agent-ui-issues--shown)

(defun agent-ui-issues-show (id dir)
  "Show issue ID of DIR's project (bd show) in a buffer."
  (let ((default-directory dir)
        (buffer (get-buffer-create (format "*bd show %s*" id))))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (call-process "bd" nil t nil "show" id))
      (special-mode)
      (goto-char (point-min)))
    (pop-to-buffer buffer)))

;; ====== DRAWING ======

(defun agent-ui-issues--under-p (issue parent by-id)
  "Whether ISSUE is PARENT's (its child, or a child's): its id under
PARENT's (p.1, p.1.2), or its parent field's chain (bd dep add --type
parent-child: any id) reaching it; BY-ID the issues by id."
  (let ((prefix (concat parent "."))
        (up (plist-get issue :parent))
        (seen nil)
        (found (string-prefix-p (concat parent ".") (plist-get issue :id))))
    (while (and (not found) up (not (member up seen)))
      (push up seen)
      (if (or (equal up parent) (string-prefix-p prefix up))
          (setq found t)
        (setq up (plist-get (gethash up by-id) :parent))))
    found))

(defun agent-ui-issues--columns (props data)
  "DATA's issues in their columns, as PROPS filters them: ((TITLE . ISSUES)...)."
  (let* ((parent (plist-get props :parent))
         (label (plist-get props :label))
         (ready (plist-get data :ready))
         (by-id (let ((table (make-hash-table :test #'equal)))
                  (dolist (i (plist-get data :issues) table) (puthash (plist-get i :id) i table))))
         (issues (seq-filter (lambda (i)
                               (and (not (equal (plist-get i :issue_type) "epic"))
                                    (or (null parent) (agent-ui-issues--under-p i parent by-id))
                                    (or (null label) (member label (plist-get i :labels)))))
                             (plist-get data :issues)))
         (by-priority (lambda (l) (cl-sort (copy-sequence l) #'< :key (lambda (i) (or (plist-get i :priority) 9))))))
    (list (cons "Ready" (funcall by-priority (seq-filter (lambda (i) (and (equal (plist-get i :status) "open")
                                                                         (member (plist-get i :id) ready)))
                                                        issues)))
          (cons "In progress" (funcall by-priority (seq-filter (lambda (i) (equal (plist-get i :status) "in_progress")) issues)))
          (cons "Blocked" (funcall by-priority (seq-filter (lambda (i) (or (equal (plist-get i :status) "blocked")
                                                                           (and (equal (plist-get i :status) "open")
                                                                                (not (member (plist-get i :id) ready)))))
                                                          issues)))
          (cons "Done" (cl-sort (seq-filter (lambda (i) (equal (plist-get i :status) "closed")) issues)
                                #'string> :key (lambda (i) (or (plist-get i :closed_at) "")))))))

(defconst agent-ui-issues--lead "\\`[^:]\\{1,30\\}: "
  "A title's lead (\"Agent UI element: \"), left out when they all have one.")

(defun agent-ui-issues--card (issue width dir &optional short pick)
  "ISSUE as a line WIDTH wide: its id, its title (without its lead if
SHORT); a button opening it. PICK: its pick mark's maker, before it (select)."
  (if pick
      (concat (funcall pick (plist-get issue :id))
              (agent-ui-issues--card issue (max 1 (- width 4)) dir short))
  (let* ((priority (plist-get issue :priority))
         (id (plist-get issue :id))
         (title (plist-get issue :title))
         (title (if short (replace-regexp-in-string agent-ui-issues--lead "" title) title))
         (line (agent-ui-truncate
                (concat (propertize id 'face (if (and priority (<= priority 1)) 'agent-ui-warning 'agent-ui-muted))
                        " " title)
                width)))
    (agent-ui-button (agent-ui-pad line width)
                     (lambda () (funcall agent-ui-open-issue-function id dir))
                     (format "RET: open %s" id)))))

(defun agent-ui-issues--draw (props ctx)
  (let* ((dir (file-name-as-directory (plist-get props :dir)))
         (data (gethash dir agent-ui-issues--cache))
         (width (plist-get ctx :width))
         (limit (plist-get props :limit)))
    (cond
     ((null data) (propertize "fetching the issues…" 'face 'agent-ui-muted))
     ((plist-get data :error) (propertize (plist-get data :error) 'face 'agent-ui-muted))
     (t
      (let* ((columns (agent-ui-issues--columns props data))
             (wide (>= width 72))
             (col-width (if wide (/ (- width 6) 4) width))
             ;; Their titles all led alike ("Agent UI element: ..."): the lead
             ;; left out, the room kept for what tells them apart.
             (all (apply #'append (mapcar #'cdr columns)))
             (short (and all (cl-every (lambda (i) (string-match-p agent-ui-issues--lead (plist-get i :title))) all)))
             ;; Asking (select): a mark before each card, picking its issue.
             (select (plist-get props :select))
             (pick (when select
                     (let ((multiple (agent-ui-ask-multiple-p select))
                           (live (and (not (plist-get props :answered)) (not (plist-get ctx :still)))))
                       (lambda (id)
                         (let ((mark (agent-ui-ask-mark (agent-ui-ask-picked-p props id) multiple)))
                           (concat (if live (agent-ui-ask-pick-button mark props ctx id multiple) mark) " "))))))
             (drawn (mapcar (lambda (column)
                              (let ((issues (cdr column)))
                                (append (list (propertize (agent-ui-pad (format "%s (%d)" (car column) (length issues)) col-width)
                                                          'face 'bold))
                                        (mapcar (lambda (i) (agent-ui-issues--card i col-width dir short pick))
                                                (seq-take issues limit))
                                        (when (> (length issues) limit)
                                          (list (propertize (agent-ui-pad (format "… %d more" (- (length issues) limit)) col-width)
                                                            'face 'agent-ui-muted))))))
                            columns)))
        (let ((board
               (if (not wide)
                   (mapconcat (lambda (lines) (mapconcat #'string-trim-right lines "\n")) drawn "\n\n")
                 ;; Side by side: line by line, each column padded to its width.
                 (let ((height (apply #'max (mapcar #'length drawn))))
                   (mapconcat (lambda (row)
                                (string-trim-right
                                 (mapconcat (lambda (lines) (or (nth row lines) (make-string col-width ?\s))) drawn "  ")))
                              (number-sequence 0 (1- height)) "\n")))))
          (if select
              ;; The ids shown, in the board's order: what All picks.
              (agent-ui-ask-around props ctx board
                                   (cl-loop for column in columns
                                            append (mapcar (lambda (i) (plist-get i :id))
                                                           (seq-take (cdr column) limit))))
            board)))))))

(agent-ui-define issues
  "The project's Beads issues as a board: Ready (open, nothing blocking),
In progress, Blocked, Done (the latest first), each issue's id and title
\(P0/P1 marked). DIR the project (default: your directory); PARENT an
epic's issues only; LABEL those with it; LIMIT per column. Fetched by bd
in the background and refreshed after bd commands; RET opens an issue."
  :props ((dir file "The project (default: your directory)" :default :here)
          (parent string "An epic's id: its issues only")
          (label string "Only issues with this label")
          (limit integer "The most issues a column shows" :default 8)
          (select any "Ask the user to pick issues: {\"question\", \"multiple\", \"note\", \"submit\"}; the answer names their ids")
          (selected list "The issues picked so far (their ids): a default, or the user's")
          (note-text string "The user's note")
          (answered string "The answer given (then it can't be changed)"))
  :example (:title "Agent UI's issues" :label "agent-ui" :limit 5)
  ;; Below 0: \"… 4 more\" for a column of 3.
  :check (lambda (props)
           (when (< (plist-get props :limit) 0)
             (agent-ui--fail "issues: limit must be 0 or more, not %d" (plist-get props :limit)))
           ;; Asking: its select; its issues come later (fetched): one only
           ;; checked, not which.
           (when-let* ((select (plist-get props :select)))
             (agent-ui-ask-select-check "issues" select)
             (agent-ui-ask-check "issues" (plist-get props :selected) (plist-get props :selected)
                                 (agent-ui-ask-multiple-p select)))
           props)
  :text #'agent-ui-issues--draw)
