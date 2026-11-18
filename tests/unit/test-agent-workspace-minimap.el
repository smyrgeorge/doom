;;; tests/unit/test-agent-workspace-minimap.el -*- lexical-binding: t; -*-
;; config/agent-workspace/minimap.el: the crew's minimap under the issue list.
;; Its lanes from what the agents did (activity.el's, stood in for), drawn
;; again as they do things (a burst: once), not while it's hidden; m hides it,
;; crew.json keeps that; RET, o, d on a lane and on a conflict; each agent's
;; role's icon after its avatar; a cell a column, every │ at the same one, no
;; line past the window's edge. Agents' sessions plain buffers (no agent
;; runs); bd not run. A terminal's glyphs (batch); a glyph drawn wider stood
;; in for, its width stubbed.

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(+test-load "config/agent-shell" "config/agent-ui" "config/tiling" "config/agent-workspace")
(remove-hook '+my/agent-shell-claude-context-functions #'+my/agent-shell-beads-context)

;; ====== HELPERS ======

(defun +test-awm--git (&rest args)
  (with-temp-buffer
    (unless (eql 0 (apply #'call-process "git" nil t nil args))
      (error "git %S: %s" args (buffer-string)))
    (string-trim (buffer-string))))

(defun +test-awm--project (name)
  "A git repository NAME in the temp folder, with a commit (README,
src/a.el): its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "awm/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory (expand-file-name "src" dir) t)
    (let ((default-directory dir))
      (+test-awm--git "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (write-region "(a)\n(b)\n(c)\n(d)\n" nil "src/a.el")
      (+test-awm--git "add" ".")
      (+test-awm--git "-c" "user.name=Test" "-c" "user.email=test@example.com" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-awm (name &rest body)
  "BODY in a new project NAME (`project'), a frame 220x40, no app or crew
before or after; agents' sessions plain buffers, at the desk; bd not run;
the minimap shown (as by default)."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-awm--project ,name))
            (default-directory project)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--activity (make-hash-table :test #'eq :weakness 'key))
            (agent-workspace--minimap-shown (make-hash-table :test #'equal))
            (agent-workspace--minimap-measured (make-hash-table :test #'eq :weakness 'key))
            (agent-workspace-minimap t))
       (set-frame-size (selected-frame) 220 40)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                      (with-current-buffer buffer (setq agent-workspace--agent agent))
                      (setf (agent-workspace-agent-buffer agent) buffer
                            (agent-workspace-agent-state agent) 'desk)
                      (agent-workspace--changed agent 'session)
                      buffer)))
                 ((symbol-function 'agent-workspace--stop)
                  (lambda (agent state &rest _)
                    (when (buffer-live-p (agent-workspace-agent-buffer agent))
                      (kill-buffer (agent-workspace-agent-buffer agent)))
                    (setf (agent-workspace-agent-buffer agent) nil
                          (agent-workspace-agent-state agent) state)
                    nil))
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore))
         (unwind-protect (progn ,@body)
           (when (agent-workspace--app project) (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-awm--windows ()
  "The frame's windows: (BUFFER-NAME WIDTH HEIGHT), from its first."
  (mapcar (lambda (window) (list (buffer-name (window-buffer window))
                                 (window-total-width window) (window-total-height window)))
          (window-list nil 'nomini (frame-first-window))))

(defun +test-awm--text (project)
  "PROJECT's minimap as drawn, without properties."
  (with-current-buffer (agent-workspace--minimap-buffer project)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun +test-awm--tool (agent kind &optional file line)
  "AGENT's tool call of KIND (ACP's), at FILE (in its worktree) and LINE."
  (agent-workspace--activity-event
   agent `((:event . tool-call-update)
           (:data . ((:tool-call . ((:kind . ,kind)
                                    (:locations . ,(and file (vector `((path . ,(expand-file-name
                                                                                 file (agent-workspace-agent-worktree agent)))
                                                                       (line . ,line))))))))))))

(defmacro +test-awm--wide (&rest body)
  "BODY with ✎ drawn a column wider than it is (a font without it: another
font's, wider), its cells' glyphs measured afresh."
  (declare (indent 0))
  `(let ((agent-workspace--minimap-measured (make-hash-table :test #'eq :weakness 'key)))
     (cl-letf* ((width (symbol-function 'string-pixel-width))
                ((symbol-function 'string-pixel-width)
                 (lambda (text &rest args)
                   (+ (apply width text args) (* (frame-char-width) (cl-count ?✎ text))))))
       ,@body)))

(defun +test-awm--bar (lane)
  "LANE's │: how far in it's drawn (the space before it aligned), and that
space's display."
  (let ((at (string-search "│" lane)))
    (list (string-pixel-width (substring lane 0 at)) (get-text-property (1- at) 'display lane))))

(defun +test-awm--goto (project text)
  "Point (and the minimap's window's) at the line with TEXT in PROJECT's
minimap; its buffer current."
  (set-buffer (agent-workspace--minimap-buffer project))
  (goto-char (point-min))
  (should (search-forward text nil t))
  (beginning-of-line)
  (when-let* ((window (get-buffer-window (current-buffer))))
    (set-window-point window (point))))

(defconst +test-awm--twelve
  '(("ada" "builder") ("sam" "investigator") ("kim" "reviewer") ("bo" "builder")
    ("cy" "builder") ("di" "builder") ("ed" "investigator") ("fay" "reviewer")
    ("gus" "tester") ("hal" "tester") ("ivy" "designer") ("jo" "planner"))
  "Twelve agents (NAME ROLE), no role past its most.")

(defun +test-awm--crew (n &optional from)
  "The first N of `+test-awm--twelve' made, but the FROM first (made
already): the agents made."
  (mapcar (lambda (spec) (agent-workspace-create :role (cadr spec) :name (car spec)))
          (nthcdr (or from 0) (seq-take +test-awm--twelve n))))

(defun +test-awm--rows (project)
  "The rows of PROJECT's minimap's window."
  (window-total-height (get-buffer-window (agent-workspace--minimap-buffer project))))

;; ====== TESTS ======

(ert-deftest agent-workspace-minimap/under-the-issues ()
  "Under the issue list, as tall as its lines (one agent: its lane, its
header line); m hides it (the issues the whole column) and shows it again;
crew.json keeps it hidden, and a crew started again from it opens without
it."
  (+test-awm "under"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-open t)
    (let ((windows (+test-awm--windows)))
      (should (equal (nth 0 windows) '("*issues · under*" 50 37)))
      (should (equal (nth 1 windows) '("*minimap · under*" 50 2))))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-minimap-toggle))
    (should (equal (nth 0 (+test-awm--windows)) '("*issues · under*" 50 39)))
    (should-not (get-buffer-window (agent-workspace--minimap-buffer project)))
    (agent-workspace-crew-save project)
    (should (string-search "\"minimap\": false" (with-temp-buffer
                                              (insert-file-contents (agent-workspace--crew-path project))
                                              (buffer-string))))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-minimap-toggle))
    (should (equal (nth 1 (+test-awm--windows)) '("*minimap · under*" 50 2)))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-minimap-toggle))
    ;; Closed, then started again from crew.json: hidden as it was.
    (agent-workspace-crew-save project)
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-quit))
    (clrhash agent-workspace--minimap-shown)
    (agent-workspace-open t)
    (should (agent-workspace-agent "ada" project))
    (should-not (seq-find (lambda (window) (string-prefix-p "*minimap" (car window))) (+test-awm--windows)))))

(ert-deftest agent-workspace-minimap/no-room-for-it ()
  "m in a frame too low for the minimap (a terminal's 24 rows, twelve
agents, one at work: its 10 lanes, axis and legend): refused, saying how
many rows it needs, nothing changed; hiding it works anywhere
\(doom-pbk.87)."
  (+test-awm "no-room"
    (+test-awm--tool (car (+test-awm--crew 12)) "read" "README" 1)
    (agent-workspace-open t)
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-minimap-toggle))
    (should-not (agent-workspace-minimap-shown-p project))
    (set-frame-size (selected-frame) 80 24)
    (agent-workspace-layout (agent-workspace--app project))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (should (string-match-p "\\`No room for the minimap: it needs 26 rows, the frame has [0-9]+\\'"
                              (cadr (should-error (agent-workspace-minimap-toggle) :type 'user-error)))))
    (should-not (agent-workspace-minimap-shown-p project))))

(ert-deftest agent-workspace-minimap/as-tall-as-its-lines ()
  "The minimap as tall as its lines, its header line above them: no agents,
its one line; a lane an agent, growing as they come and shrinking as one's
forgotten; the axis and legend under them while a lane has cells; at most
`agent-workspace-minimap-lines' lanes (10), then it scrolls. Its own change:
the app's sizes taken, not a border dragged."
  (+test-awm "tall"
    (let ((app (agent-workspace-open t)))
      (cl-flet ((drawn ()
                  (agent-workspace--minimap-draw project)
                  (should (equal (agent-workspace--app-sizes app) (agent-workspace--sizes-now (selected-frame))))
                  (+test-awm--rows project)))
        (should (= (+test-awm--rows project) 2))
        (should (string-search "No agents yet" (+test-awm--text project)))
        (let ((agents (+test-awm--crew 3)))
          (should (= (drawn) 4))
          ;; ada reads: her lane has cells, the axis and legend under the lanes.
          (+test-awm--tool (car agents) "read" "README" 1)
          (should (= (drawn) 6)))
        ;; Twelve: 10 lanes shown, the rest scrolled to.
        (+test-awm--crew 12 3)
        (should (= (length (agent-workspace-agents project)) 12))
        (should (= (drawn) 13))
        (should (= (agent-workspace--minimap-lines project) 12))
        (with-current-buffer (agent-workspace--minimap-buffer project)
          (should (= (count-lines (point-min) (point-max)) 14)))
        ;; Four forgotten: 8 lanes.
        (dolist (name '("fay" "gus" "hal" "ivy"))
          (agent-workspace-forget (agent-workspace-agent name project) 'keep))
        (should (= (drawn) 11))))))

(ert-deftest agent-workspace-minimap/the-lanes ()
  "A line for each agent, in the crew's order: one that did something its
avatar and role's icon, a cell a minute (what it did most), its state's
glyph, where it is now (its file and line, what it asks); a quiet one its
name in the cells' place, its state in words; a file two agents changed,
⚠; the axis and the legend (doom-pbk.91)."
  (+test-awm "lanes"
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (sam (agent-workspace-create :role "investigator" :name "sam"))
           (ken (agent-workspace-create :role "builder" :name "ken"))
           (now (float-time)))
      (cl-letf (((symbol-function 'float-time) (lambda (&rest _) now)))
        (setq now (- (float-time) 180))
        (+test-awm--tool ada "read" "README" 1)
        (+test-awm--tool ada "search")
        (setq now (+ now 180))
        (+test-awm--tool ada "read" "src/a.el" 2)
        (+test-awm--tool ada "edit" "src/a.el" 3)
        (+test-awm--tool sam "execute")
        (+test-awm--tool sam "read" "src/a.el" 1))
      (agent-workspace--set-state sam 'hand)
      (setf (agent-workspace-agent-ask sam) '(:kind permission :title "npm install"))
      (agent-workspace--set-state ada 'working)
      (agent-workspace--add-changed ada '("src/a.el"))
      (agent-workspace--add-changed sam '("src/a.el" "README"))
      (agent-workspace-open t)
      (let ((lines (split-string (+test-awm--text project) "\n")))
        ;; ada, a builder (⚙): read 3 minutes ago, edited now; working, at
        ;; src/a.el:3.
        (should (string-match-p (concat "\\`  ?▌A ⚙ " (make-string (- agent-workspace-activity-minutes 4) ?·)
                                        "⌕··✎ │ ⚙  ?src/a\\.el:3\\'")
                                (nth 0 lines)))
        ;; ken, a builder too, quiet: his name, his state in words.
        (should (string-match-p "\\`  ?▌K ⚙ ken +│ ○  ?at the desk\\'" (nth 1 lines)))
        ;; sam, an investigator (⌕): ran a command now (over a read), its hand
        ;; raised; what it asks 2 columns shorter for its icon.
        (should (string-match-p "▌S ⌕ ·+▶ │ !  ?wants to use npm ins…" (nth 2 lines)))
        (should (string-match-p "⚠ ada \\+ sam: src/a\\.el" (nth 3 lines)))
        (should-not (string-search "quiet" (+test-awm--text project)))
        (should (equal (string-trim (nth 4 lines)) "-15m    -5m now"))
        ;; The axis under the cells, after the avatar and icon.
        (should (= (string-search "-15m" (nth 4 lines)) (string-search "·" (nth 0 lines))))
        (should (string-search "⌕ read  ✎ edit  ▶ run  ! asks you" (nth 5 lines)))
        (should (= (length lines) 6)))
      ;; Every line's │ at the same column, a space aligned to it.
      (let ((lanes (with-current-buffer (agent-workspace--minimap-buffer project)
                     (split-string (buffer-string) "\n"))))
        (should (equal (+test-awm--bar (nth 0 lanes))
                       (list (+ 7 agent-workspace-activity-minutes)
                             `(space :align-to ,(+ 7 agent-workspace-activity-minutes)))))
        (should (equal (+test-awm--bar (nth 1 lanes)) (+test-awm--bar (nth 0 lanes))))
        (should (equal (+test-awm--bar (nth 2 lanes)) (+test-awm--bar (nth 0 lanes)))))
      (ignore ken))))

(ert-deftest agent-workspace-minimap/each-agent-s-role ()
  "Each agent's role's icon right after its avatar, on its lane or its quiet
line: in its colour, dimmed while it is (not shadow); its name and role on
hover, avatar and icon. A project's role without an icon: ▶, its lane's │
where the others' are."
  (+test-awm "roles"
    (make-directory (expand-file-name ".agent-workspace/roles" project) t)
    (write-region "---\ndescription: triages what comes in\n---\nTriage.\n" nil
                  (expand-file-name ".agent-workspace/roles/triager.md" project))
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (tess (agent-workspace-create :role "triager" :name "tess"))
          (rex (agent-workspace-create :role "reviewer" :name "rex")))
      (+test-awm--tool ada "edit" "src/a.el" 1)
      (+test-awm--tool tess "read" "README" 1)
      (agent-workspace--set-state rex 'asleep)
      (agent-workspace-open t)
      (let* ((lines (with-current-buffer (agent-workspace--minimap-buffer project)
                      (split-string (buffer-string) "\n")))
             (line (lambda (text) (seq-find (lambda (line) (string-search text line)) lines)))
             (ada-lane (funcall line "▌A"))
             (tess-lane (funcall line "▌T"))
             (quiet (funcall line "▌R")))
        (should (string-prefix-p " ▌A ⚙ " ada-lane))
        (should (string-prefix-p " ▌T ▶ " tess-lane))
        (should (string-match-p "\\` ▌R ◎ rex +│ ⏻  ?asleep" quiet))
        (should (equal (+test-awm--bar quiet) (+test-awm--bar ada-lane)))
        (should (equal (+test-awm--bar tess-lane) (+test-awm--bar ada-lane)))
        ;; ada's icon in its colour; its name and role on avatar and icon.
        (should (equal (get-text-property 4 'face ada-lane) (agent-workspace--fg ada)))
        (should (equal (get-text-property 1 'help-echo ada-lane) "ada · builder"))
        (should (equal (get-text-property 4 'help-echo ada-lane) "ada · builder"))
        (should (equal (get-text-property 4 'help-echo tess-lane) "tess · triager"))
        ;; rex asleep: its icon dimmed as its avatar is, not shadow.
        (let ((at (string-search "◎" quiet)))
          (should (equal (get-text-property at 'face quiet)
                         (list :foreground (agent-ui-blend (agent-ui-background)
                                                           (agent-ui-color (agent-workspace-agent-face rex)) 0.4))))
          (should (equal (get-text-property (string-search "▌R" quiet) 'help-echo quiet) "rex · reviewer"))
          (should (equal (get-text-property at 'help-echo quiet) "rex · reviewer")))))))

(ert-deftest agent-workspace-minimap/a-cell-a-column ()
  "A cell's glyph drawn wider than a column (✎ from another font) is its
kind's next one, a column wide (±): in its cells and the legend; one drawn
a column wide kept. Measured once a frame, again when its font changes."
  (let ((agent (agent-workspace--make-agent :name "ada" :role "builder" :colour "blue" :project "/p/"))
        (measured 0))
    (let ((agent-workspace--minimap-measured (make-hash-table :test #'eq :weakness 'key)))
      (should (equal (agent-workspace--minimap-glyph 'edit) "✎"))
      (should (equal (agent-workspace--minimap-cell agent '(edit read)) "✎")))
    (+test-awm--wide
      (cl-letf* ((width (symbol-function 'string-pixel-width))
                 ((symbol-function 'string-pixel-width)
                  (lambda (&rest args) (cl-incf measured) (apply width args))))
        (should (equal (agent-workspace--minimap-cell agent '(edit read)) "±"))
        (should (memq 'bold (get-text-property 0 'face (agent-workspace--minimap-cell agent '(edit)))))
        (should (string-search "⌕ read  ± edit  ▶ run  ! asks you" (agent-workspace--minimap-legend 60)))
        (should (equal (mapcar #'agent-workspace--minimap-glyph '(read run asked none)) '("⌕" "▶" "!" "·")))
        ;; Once a frame: not measured again.
        (setq measured 0)
        (agent-workspace--minimap-cell agent '(edit))
        (should (= measured 0))
        ;; Another font: measured again.
        (cl-letf (((symbol-function 'face-font) (lambda (&rest _) "another font")))
          (should (equal (agent-workspace--minimap-glyph 'edit) "±")))
        (should (> measured 0))))))

(ert-deftest agent-workspace-minimap/a-lane-never-past-its-edge ()
  "A lane fitting its columns but drawn wider (glyphs from wider fonts) is
cut to its pixels, … at its end; its │ where every lane's is."
  (+test-awm "edge"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (+test-awm--tool ada "edit" "src/✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎✎.el" 3)
      (+test-awm--wide
        (let ((lane (agent-workspace--minimap-lane ada 50)))
          (should (<= (string-pixel-width lane) 50))
          (should (string-suffix-p "…" lane))
          (should (string-search "±" lane))
          (should (eq (get-text-property (1- (length lane)) 'agent-workspace-minimap-agent lane) ada))
          (should (equal (nth 1 (+test-awm--bar lane)) `(space :align-to ,(+ 7 agent-workspace-activity-minutes)))))
        ;; Drawn: no line past the window's edge.
        (agent-workspace-open t)
        (let ((window (get-buffer-window (agent-workspace--minimap-buffer project))))
          (with-current-buffer (window-buffer window)
            (dolist (line (split-string (buffer-string) "\n"))
              (should (< (string-pixel-width line) (window-body-width window t))))))))))

(ert-deftest agent-workspace-minimap/drawn-as-they-do-things ()
  "Drawn again as an agent does things, a burst once, a quarter of a second
on; not while the app is left; no redraw waiting once it's closed."
  (+test-awm "live"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (draws 0))
      (agent-workspace-open t)
      (should (string-search "ada │ ○  at the desk" (+test-awm--text project)))
      (cl-letf* ((draw (symbol-function 'agent-workspace--minimap-draw))
                 ((symbol-function 'agent-workspace--minimap-draw)
                  (lambda (project) (cl-incf draws) (funcall draw project))))
        (dotimes (_ 5) (+test-awm--tool ada "read" "README" 1))
        (should (= draws 0))
        (should (+test-wait-for (lambda () (string-search "README:1" (+test-awm--text project))) 2))
        (should (= draws 1))
        ;; A redraw waits for the next minute (its cells move on).
        (should (timerp (gethash project agent-workspace--minimap-timers)))
        ;; Left: nothing drawn, nothing waiting for it.
        (with-current-buffer (agent-workspace--issues-buffer project)
          (agent-workspace-leave t))
        (+test-awm--tool ada "edit" "src/a.el" 2)
        (+test-sleep 0.4)
        (should (= draws 1))
        (should (string-search "README:1" (+test-awm--text project)))
        ;; Back: drawn as it is now (the frame's size again: a wait in batch
        ;; gives it the terminal's).
        (set-frame-size (selected-frame) 220 40)
        (agent-workspace-open t)
        (should (string-search "src/a.el:2" (+test-awm--text project)))
        (agent-workspace--close-app project)
        (should-not (gethash project agent-workspace--minimap-timers))))))

(ert-deftest agent-workspace-minimap/a-quiet-agent-s-line ()
  "Every agent on a line of its own, the quiet ones too: n/p reach each,
RET selects its agent, o says it's in no file yet (its agent, not \"No
agent on this line\"); five quiet agents in a 48-column minimap, all shown,
none cut (doom-pbk.91)."
  (+test-awm "quiet"
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (ken (agent-workspace-create :role "builder" :name "ken"))
           (liz (agent-workspace-create :role "builder" :name "liz")))
      (+test-awm--tool ada "edit" "src/a.el" 1)
      (agent-workspace-open t)
      (agent-workspace-select ada)
      (+test-awm--goto project "▌A")
      (agent-workspace-minimap-next)
      (should (eq (get-text-property (point) 'agent-workspace-minimap-agent) ken))
      (agent-workspace-minimap-next)
      (should (eq (get-text-property (point) 'agent-workspace-minimap-agent) liz))
      (agent-workspace-minimap-previous)
      (should (eq (get-text-property (point) 'agent-workspace-minimap-agent) ken))
      (should (equal (cadr (should-error (agent-workspace-minimap-open) :type 'user-error))
                     "ken is in no file yet"))
      (agent-workspace-minimap-select)
      (should (eq (agent-workspace--app-selected (agent-workspace--app project)) ken))))
  (+test-awm "five-quiet"
    (pcase-dolist (`(,name ,role) '(("ada" "builder") ("ken" "builder") ("liz" "scribe")
                                    ("max" "reviewer") ("zoe" "investigator")))
      (agent-workspace-create :role role :name name))
    (let ((lines (agent-workspace-minimap-text project 48)))
      (should (= (length lines) 5))
      (dolist (line lines)
        (should-not (string-suffix-p "…" line))
        (should (string-match-p "│ ○  ?at the desk\\'" line))))))

(ert-deftest agent-workspace-minimap/its-keys ()
  "On a lane: j/k between lanes, RET selects its agent, o opens its file in
its worktree at its line. On a ⚠: d shows both agents' changes to its file."
  (+test-awm "keys"
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (ken (agent-workspace-create :role "builder" :name "ken")))
      (write-region "(a ada)\n" nil (expand-file-name "src/a.el" (agent-workspace-agent-worktree ada)))
      (write-region "(a ken)\n(b)\n(c)\n" nil (expand-file-name "src/a.el" (agent-workspace-agent-worktree ken)))
      (+test-awm--tool ada "edit" "src/a.el" 1)
      (+test-awm--tool ken "read" "src/a.el" 3)
      (agent-workspace--activity-event ada '((:event . turn-complete)))
      (agent-workspace--activity-event ken '((:event . turn-complete)))
      ;; What they changed, worked out in the background.
      (should (+test-wait-for (lambda () (agent-workspace-conflicts project)) 10))
      (agent-workspace-open t)
      (agent-workspace-select ada)
      ;; j from ada's lane: ken's; RET selects ken.
      (+test-awm--goto project "▌A")
      (agent-workspace-minimap-next)
      (should (eq (get-text-property (point) 'agent-workspace-minimap-agent) ken))
      (agent-workspace-minimap-select)
      (should (eq (agent-workspace--app-selected (agent-workspace--app project)) ken))
      ;; A key of the app's acts on the lane's agent.
      (+test-awm--goto project "▌A")
      (should (eq (agent-workspace--current) ada))
      ;; o: ken's file, in its worktree, at its line.
      (+test-awm--goto project "▌K")
      (save-window-excursion
        (agent-workspace-minimap-open)
        (should (equal (buffer-file-name)
                       (expand-file-name "src/a.el" (agent-workspace-agent-worktree ken))))
        (should (= (line-number-at-pos) 3))
        (kill-buffer))
      ;; d on the conflict: both diffs.
      (agent-workspace-open t)
      (+test-awm--goto project "⚠")
      (save-window-excursion
        (agent-workspace-minimap-diff)
        (should (equal (buffer-name) "*ada + ken: src/a.el*"))
        (let ((text (buffer-string)))
          (should (string-search "# ada (agent/ada)" text))
          (should (string-search "+(a ada)" text))
          (should (string-search "# ken (agent/ken)" text))
          (should (string-search "+(a ken)" text)))
        (kill-buffer)))))
