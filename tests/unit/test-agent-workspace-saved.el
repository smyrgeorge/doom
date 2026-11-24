;;; tests/unit/test-agent-workspace-saved.el -*- lexical-binding: t; -*-
;; config/agent-workspace/saved.el: the crew's configuration in
;; .agent-shell/agent-workspace/crew.json, per machine. Written when the crew
;; changes (stable, one agent a line, only what differs), read as JSON (never
;; evaluated, a wrong agent said by its place and name, a wrong file said and
;; nothing started), the crew started again from it (fresh, asleep ones
;; asleep, one that can't start saying why, the layout as it was), read again
;; by hand; a crew round-trips. An agent's open panels in it by name, kept as
;; the crew closes, opened again with it. In throwaway git repositories;
;; sessions are plain buffers (no agent runs).
;; run.sh: slow (~45 s: stand-in sessions).

(setenv "GIT_CONFIG_GLOBAL" "/dev/null")
(setenv "GIT_CONFIG_NOSYSTEM" "1")

(require 'agent-shell)
(+test-load "config/agent-ui" "config/agent-workspace")

;; ====== HELPERS ======

(defun +test-aws2--project (name)
  "A git repository NAME in the temp folder, with a commit: its folder."
  (let ((dir (file-name-as-directory (expand-file-name (concat "aws2/" name) +test-tmp))))
    (when (file-exists-p dir) (delete-directory dir t))
    (make-directory dir t)
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q" "-b" "main")
      (write-region "hello\n" nil "README")
      (call-process "git" nil nil nil "add" "README")
      (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "first"))
    (file-name-as-directory (file-truename dir))))

(defmacro +test-aws2 (name &rest body)
  "BODY in a new project NAME (`project'), no crew or app before or after;
sessions plain buffers (`started' lists the agents started); crew.json
written at once (no wait). Loops wait for you (`agent-workspace-loop' nil:
a looping agent started again asleep, a new one not looping), as these
tests were written; test-agent-workspace-loops.el tests the default."
  (declare (indent 1))
  `(+test-with-reset
     (let* ((project (+test-aws2--project ,name))
            (default-directory project)
            (agent-workspace-loop nil)
            (agent-workspace--crews (make-hash-table :test #'equal))
            (agent-workspace--apps (make-hash-table :test #'equal))
            (agent-workspace--crew-timers (make-hash-table :test #'equal))
            (agent-workspace--crew-closed (make-hash-table :test #'equal))
            (agent-workspace--crew-kept (make-hash-table :test #'equal))
            (started nil))
       (ignore started)
       (set-frame-size (selected-frame) 160 40)
       (cl-letf (((symbol-function 'agent-workspace--start)
                  (lambda (agent)
                    (push (agent-workspace-agent-name agent) started)
                    (let ((buffer (get-buffer-create (agent-workspace-buffer-name agent))))
                      (with-current-buffer buffer (setq agent-workspace--agent agent))
                      (setf (agent-workspace-agent-buffer agent) buffer)
                      (agent-workspace--set-state agent 'desk)
                      (agent-workspace--changed agent 'session)
                      buffer)))
                 ((symbol-function 'agent-workspace--stop)
                  (lambda (agent state &rest _)
                    (when (buffer-live-p (agent-workspace-agent-buffer agent))
                      (kill-buffer (agent-workspace-agent-buffer agent)))
                    (setf (agent-workspace-agent-buffer agent) nil)
                    (agent-workspace--set-state agent state)
                    nil))
                 ((symbol-function 'agent-workspace--issues-refresh) #'ignore)
                 ((symbol-function 'run-at-time)
                  (let ((run-at-time (symbol-function 'run-at-time)))
                    (lambda (time repeat fn &rest args)
                      (if (eq fn #'agent-workspace-crew-save)
                          (progn (apply fn args) nil)
                        (apply run-at-time time repeat fn args))))))
         (unwind-protect (progn ,@body)
           (dolist (project (hash-table-keys agent-workspace--apps))
             (agent-workspace--close-app project))
           (agent-workspace-close-all))))))

(defun +test-aws2--path (project)
  "PROJECT's crew.json."
  (expand-file-name ".agent-shell/agent-workspace/crew.json" project))

(defun +test-aws2--compact (text)
  "crew.json's TEXT, read as JSON, as one line an agent, one the layout:
what these tests compare (crew.json is written as jq prints it: its own
test, agent-workspace-saved/as-jq-prints-it); TEXT itself if it isn't a
crew's JSON (a broken file written by a test)."
  (let ((data (ignore-errors (json-parse-string text :object-type 'plist :array-type 'array
                                                :null-object nil :false-object :false))))
    (if (not (and (consp data) (keywordp (car data)) (vectorp (plist-get data :agents))))
        text
      (concat "{\"version\": " (agent-workspace--crew-json (plist-get data :version)) ",\n"
              " \"agents\": ["
              (let ((agents (plist-get data :agents)))
                (if (> (length agents) 0)
                    (concat "\n" (mapconcat (lambda (agent) (concat "  " (agent-workspace--crew-json agent)))
                                            agents ",\n")
                            "\n ")
                  ""))
              "]"
              (if (plist-member data :layout)
                  (concat ",\n \"layout\": " (agent-workspace--crew-json (plist-get data :layout)))
                "")
              "}\n"))))

(defun +test-aws2--file (project)
  "PROJECT's crew.json's text, or nil, as `+test-aws2--compact' has it."
  (let ((file (+test-aws2--path project)))
    (and (file-exists-p file)
         (+test-aws2--compact (with-temp-buffer (insert-file-contents file) (buffer-string))))))

(defun +test-aws2--write (project text)
  "PROJECT's crew.json now TEXT."
  (let ((file (+test-aws2--path project)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file (insert text))))

;; ====== WRITTEN ======

(ert-deftest agent-workspace-saved/its-text ()
  "JSON, one agent a line, in role order then by name; its model only when
not its role's, its mode only when not what it would have anyway (its
role's, else auto); asleep said; the layout."
  (+test-aws2 "text"
    (let ((sam (agent-workspace-create :role "investigator" :name "sam" :model "opus"))
          (ken (agent-workspace-create :role "builder" :name "ken" :colour "green" :mode "acceptEdits"))
          (ada (agent-workspace-create :role "builder" :name "ada" :mode "plan")))
      (agent-workspace-sleep ken)
      (ignore sam ada)
      (should (equal (+test-aws2--compact (agent-workspace-crew-text project))
                     "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"mode\": \"plan\"},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"mode\": \"acceptEdits\", \"asleep\": true},
  {\"name\": \"sam\", \"role\": \"investigator\", \"colour\": \"magenta\", \"model\": \"opus\"}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": null, \"open\": false, \"minimap\": true, \"talk\": \"on\", \"sources_off\": []}}
"))
      ;; JSON indeed, as jq and scripts read it.
      (should (equal (plist-get (json-parse-string (agent-workspace-crew-text project) :object-type 'plist) :version)
                     2))
      ;; Her own mode auto, the one she'd have anyway: not written.
      (setf (agent-workspace-agent-mode ada) "auto")
      (should (string-search "{\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\"}"
                             (+test-aws2--compact (agent-workspace-crew-text project))))))
  ;; No agents (all forgotten, its app open): an empty list.
  (+test-aws2 "text-empty"
    (agent-workspace-open t)
    (should (string-prefix-p "{\n  \"version\": 2,\n  \"agents\": [],\n  \"layout\": {\n"
                             (agent-workspace-crew-text project)))))

(ert-deftest agent-workspace-saved/as-jq-prints-it ()
  "crew.json written as jq . prints it: two spaces an indent, a key a line,
an array's elements a line each, an empty one [], a newline at its end;
an old file, one agent a line, read as it was and written so at the next
change; a write changing nothing leaves it as it is (doom-pbk.90)."
  (+test-aws2 "pretty"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"loop\": true, \"panels\": [\"logs\", \"tests\"]},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"asleep\": true}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ken\", \"open\": false, \"minimap\": false, \"talk\": \"on\", \"sources_off\": [[\"ci\", \"#reviewer\"]]}}
")
    (cl-letf (((symbol-function 'agent-workspace--loop-soon) #'ignore)
              ((symbol-function 'agent-workspace--loop-watch-update) #'ignore))
      (agent-workspace-open t)
      (agent-workspace-recolour (agent-workspace-agent "ken" project) "cyan")
      (let ((text (with-temp-buffer (insert-file-contents (+test-aws2--path project)) (buffer-string))))
        (should (equal text "{
  \"version\": 2,
  \"agents\": [
    {
      \"name\": \"ada\",
      \"role\": \"builder\",
      \"colour\": \"blue\",
      \"asleep\": true,
      \"loop\": true,
      \"panels\": [
        \"logs\",
        \"tests\"
      ]
    },
    {
      \"name\": \"ken\",
      \"role\": \"builder\",
      \"colour\": \"cyan\",
      \"asleep\": true
    }
  ],
  \"layout\": {
    \"view\": \"stage\",
    \"room\": \"right\",
    \"selected\": \"ken\",
    \"open\": false,
    \"minimap\": false,
    \"talk\": \"on\",
    \"sources_off\": [
      [
        \"ci\",
        \"#reviewer\"
      ]
    ]
  }
}
"))
        ;; As jq prints it.
        (when (executable-find "jq")
          (should (equal (with-temp-buffer
                           (call-process "jq" (+test-aws2--path project) t nil ".")
                           (buffer-string))
                         text)))
        ;; A write changing nothing: the file as it was.
        (set-file-times (+test-aws2--path project) (time-subtract nil 100))
        (let ((before (file-attribute-modification-time (file-attributes (+test-aws2--path project)))))
          (agent-workspace-crew-save project)
          (should (equal (file-attribute-modification-time (file-attributes (+test-aws2--path project)))
                         before)))))))

(ert-deftest agent-workspace-saved/written-when-the-crew-changes ()
  "Made, recoloured, put to sleep, woken, forgotten: written, in
.agent-shell/agent-workspace/crew.json, nothing in .agent-workspace/; a
state alone (working, done): not."
  (+test-aws2 "written"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (should (string-search "{\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\"}"
                             (+test-aws2--file project)))
      (should-not (file-exists-p (expand-file-name ".agent-workspace" project)))
      (agent-workspace-recolour ada "cyan")
      (should (string-search "\"colour\": \"cyan\"" (+test-aws2--file project)))
      (agent-workspace-sleep ada)
      (should (string-search "\"asleep\": true" (+test-aws2--file project)))
      (agent-workspace-wake ada)
      (should-not (string-search "\"asleep\"" (+test-aws2--file project)))
      (let ((before (file-attribute-modification-time (file-attributes (+test-aws2--path project)))))
        (agent-workspace--set-state ada 'working)
        (agent-workspace--set-state ada 'done)
        (should (equal (file-attribute-modification-time (file-attributes (+test-aws2--path project)))
                       before)))
      (agent-workspace-create :role "builder" :name "ken")
      (agent-workspace-forget ada 'keep)
      (should-not (string-search "ada" (+test-aws2--file project)))
      (should (string-search "ken" (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/closing-keeps-it ()
  "Closing the crew leaves crew.json as it was (every agent in it, none asleep
that wasn't); a write still to come is done first."
  (+test-aws2 "closing"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (let ((text (+test-aws2--file project)))
      (agent-workspace-close project)
      (should (equal (+test-aws2--file project) text))))
  ;; Debounced for real: closing flushes it.
  (+test-aws2 "flushed"
    (cl-letf* ((run-at-time (symbol-function 'run-at-time))
               ((symbol-function 'run-at-time)
                (lambda (&rest _) (funcall run-at-time 3600 nil #'ignore))))
      (agent-workspace-create :role "builder" :name "ada")
      (should-not (+test-aws2--file project))
      (agent-workspace-close project)
      (should (string-search "ada" (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/nothing-written-once-closed ()
  "Closed with its app still open: whatever changes after (an agent
selected, the minimap hidden) writes nothing, crew.json keeping every agent;
a new agent made there, a new crew, written again (doom-51z.15)."
  (+test-aws2 "closed-app-open"
    (agent-workspace-open t)
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (let ((text (+test-aws2--file project)))
      (should (string-search "ken" text))
      (agent-workspace-close project)
      (should (agent-workspace--app project))
      (run-hook-with-args 'agent-workspace-layout-functions project)
      (agent-workspace-crew-save project)
      (should (equal (+test-aws2--file project) text)))
    (agent-workspace-create :role "builder" :name "sam")
    (should (string-search "sam" (+test-aws2--file project)))))

;; ====== READ ======

(ert-deftest agent-workspace-saved/read-as-json ()
  "Read as JSON, never evaluated: what isn't JSON, or isn't a crew (an
object with a list of agents), is said, nothing run; no file, nothing."
  (+test-aws2 "read"
    (dolist (case '(("(progn (setq +test-aws2-evaluated t))\n" . "crew.json: not a crew: not JSON (line 1)")
                    ("{\"agents\": [\n  {\"name\": \"ada\",}\n]}\n" . "crew.json: not a crew: not JSON (line 2)")
                    ("{\"agents\": []} trailing\n" . "crew.json: not a crew: not JSON (line 1)")
                    ("[{\"name\": \"ada\", \"role\": \"builder\"}]\n" . "crew.json: not a crew: not a JSON object")
                    ("{}\n" . "crew.json: not a crew: not a JSON object")
                    ("{\"version\": 2}\n" . "crew.json: not a crew: its \"agents\" aren't a list")
                    ("{\"agents\": {\"name\": \"ada\"}}\n" . "crew.json: not a crew: its \"agents\" aren't a list")))
      (+test-aws2--write project (car case))
      (should (equal (agent-workspace-crew-read project) (list nil (cdr case)))))
    (should-not (boundp '+test-aws2-evaluated))
    (should-not (agent-workspace-crew-read (+test-aws2--project "none")))))

(ert-deftest agent-workspace-saved/a-wrong-file-starts-nothing ()
  "SPC o w with a crew.json that isn't JSON or isn't a crew: said, no agent
started, the file kept as it is for you to mend (the minimap hidden, the
talk switched meanwhile: nothing written); an agent made: written again."
  (dolist (text '("(agent-workspace-crew :agents ((:name \"ada\" :role \"builder\")))\n"
                  "{\"agents\": {\"name\": \"ada\", \"role\": \"builder\"}}\n"))
    (+test-aws2 "wrong-file"
      (+test-aws2--write project text)
      (let ((warned nil))
        (cl-letf (((symbol-function 'display-warning) (lambda (_type message &rest _) (push message warned))))
          (agent-workspace-open t))
        (should (= (length warned) 1))
        (should (string-prefix-p "crew.json: not a crew: " (car warned))))
      (should-not (agent-workspace-agents project))
      (with-current-buffer (agent-workspace--issues-buffer project)
        (agent-workspace-minimap-toggle))
      (agent-workspace-crew-save project)
      (should (equal (+test-aws2--file project) text))
      (agent-workspace-create :role "builder" :name "ken")
      (should (string-search "\"name\": \"ken\"" (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/a-wrong-agent-left-out ()
  "A wrong agent entry is left out, said by its place and name; the others
read; an unknown key said, ignored."
  (+test-aws2 "wrong"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\"},
  {\"name\": \"Bad Name\", \"role\": \"builder\"},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"pink\"},
  {\"name\": \"sam\", \"role\": \"investigator\", \"mode\": \"yolo\"},
  {\"name\": \"ada\", \"role\": \"scribe\"},
  {\"name\": \"tim\"},
  \"una\",
  {\"name\": \"vic\", \"role\": \"builder\", \"asleep\": \"yes\"},
  {\"name\": \"wes\", \"role\": \"builder\", \"kind\": \"robot\"},
  {\"name\": \"xan\", \"role\": \"builder\", \"model\": 4},
  {\"name\": \"yan\", \"role\": \"builder\", \"loop\": false, \"model\": null, \"panels\": []}
 ],
 \"colours\": 3,
 \"layout\": {\"selected\": \"ada\", \"open\": true}}
")
    (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
      (should (equal (plist-get crew :agents)
                     '((:name "ada" :role "builder" :colour "blue") (:name "yan" :role "builder"))))
      (should (equal (plist-get crew :layout) '(:selected "ada" :open t)))
      (should (equal problems
                     '("crew.json: unknown key \"colours\": ignored"
                       "crew.json: agent 2: not a name: \"Bad Name\": left out"
                       "crew.json: agent 3 (ken): its colour \"pink\" isn't one of blue, magenta, green, yellow, cyan, red, white, black: left out"
                       "crew.json: agent 4 (sam): its mode \"yolo\" isn't one of default, acceptEdits, plan, auto, dontAsk, bypassPermissions: left out"
                       "crew.json: agent 5 (ada): its name twice: left out"
                       "crew.json: agent 6 (tim): no role: left out"
                       "crew.json: agent 7: an agent is an object: {\"name\": ..., \"role\": ...}: left out"
                       "crew.json: agent 8 (vic): its asleep \"yes\" isn't true or false: left out"
                       "crew.json: agent 9 (wes): its kind \"robot\" isn't one of claude-code, codex, gemini-cli, opencode, qwen-code, copilot, goose, cursor: left out"
                       "crew.json: agent 10 (xan): its model 4 isn't a string: left out"))))))

(ert-deftest agent-workspace-saved/a-wrong-entry-kept-as-it-was ()
  "An entry left out as wrong (ken's colour pink) stays in crew.json, as it
was, after the running crew's agents, through every write after; mended
and read again (gR), it's an agent of the crew (doom-pbk.61)."
  (+test-aws2 "kept-wrong"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\"},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"pink\", \"model\": \"opus\", \"loop\": true}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ada\", \"open\": true}}
")
    (let ((agent-workspace--crew-left-out (make-hash-table :test #'equal))
          (agent-workspace--crew-seen (make-hash-table :test #'equal))
          (agent-workspace--crew-stale-said (make-hash-table :test #'equal)))
      (agent-workspace-open t)
      (let ((ada (agent-workspace-agent "ada" project)))
        (should-not (agent-workspace-agent "ken" project))
        (agent-workspace-recolour ada "cyan")
        (agent-workspace-create :role "investigator" :name "sam")
        (let ((text (+test-aws2--file project)))
          (should (string-search "{\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"cyan\"}" text))
          (should (string-search "{\"name\": \"sam\"" text))
          (should (string-search "  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"pink\", \"model\": \"opus\", \"loop\": true}\n ]"
                                 text)))
        ;; Mended by hand, read again: in the crew.
        (+test-aws2--write project (replace-regexp-in-string "pink" "green" (+test-aws2--file project)))
        (cl-letf (((symbol-function 'y-or-n-p) #'always)
                  ((symbol-function 'agent-workspace--loop-soon) #'ignore)
                  ((symbol-function 'agent-workspace--loop-watch-update) #'ignore))
          (with-current-buffer (agent-workspace--issues-buffer project)
            (agent-workspace-crew-reload)))
        (should (equal (agent-workspace-agent-colour (agent-workspace-agent "ken" project)) "green"))
        (should (= (with-temp-buffer (insert (+test-aws2--file project))
                                     (count-matches "\"name\": \"ken\"" (point-min) (point-max)))
                   1))))))

(ert-deftest agent-workspace-saved/edited-by-hand-not-overwritten ()
  "crew.json edited by hand and not read again: the crew changing doesn't
overwrite it, said once (the room, a message): gR reads it; read, it's
written again as the crew changes (doom-pbk.61)."
  (+test-aws2 "by-hand"
    (let ((agent-workspace--crew-left-out (make-hash-table :test #'equal))
          (agent-workspace--crew-seen (make-hash-table :test #'equal))
          (agent-workspace--crew-stale-said (make-hash-table :test #'equal)))
      (agent-workspace-open t)
      (let ((ada (agent-workspace-create :role "builder" :name "ada")))
        (should (string-search "\"colour\": \"blue\"" (+test-aws2--file project)))
        (let ((edited (replace-regexp-in-string "\"colour\": \"blue\"" "\"colour\": \"blue\", \"model\": \"haiku\""
                                                (+test-aws2--file project))))
          (+test-aws2--write project edited)
          (agent-workspace-recolour ada "cyan")
          (agent-workspace-recolour ada "red")
          (should (equal (+test-aws2--file project) edited))
          (let ((said (with-current-buffer (agent-workspace--room-buffer project) (buffer-string))))
            (should (= (with-temp-buffer (insert said)
                                         (count-matches "crew.json was changed outside this Emacs: gR reads it"
                                                        (point-min) (point-max)))
                       1))))
        ;; gR: read; written again after.
        (with-current-buffer (agent-workspace--issues-buffer project)
          (agent-workspace-crew-reload))
        (should (equal (agent-workspace-agent-colour ada) "blue"))
        (agent-workspace-recolour ada "green")
        (should (string-search "\"colour\": \"green\"" (+test-aws2--file project)))))))

(ert-deftest agent-workspace-saved/a-wrong-layout-said ()
  "A layout that isn't an object, or a value of it that's wrong: said,
ignored; the agents read."
  (+test-aws2 "wrong-layout"
    (+test-aws2--write project "{\"agents\": [{\"name\": \"ada\", \"role\": \"builder\"}], \"layout\": \"stage\"}\n")
    (should (equal (agent-workspace-crew-read project)
                   '((:agents ((:name "ada" :role "builder")) :layout nil)
                     "crew.json: its layout isn't an object: ignored")))
    (+test-aws2--write project "{\"agents\": [], \"layout\": {\"talk\": 3, \"selected\": \"ada\", \"sources_off\": [[\"ci\"]], \"minimap\": false}}\n")
    (should (equal (agent-workspace-crew-read project)
                   '((:agents nil :layout (:selected "ada" :minimap nil))
                     "crew.json: its layout's talk 3 isn't a name: ignored"
                     "crew.json: its layout's sources_off [[\"ci\"]] isn't a list of [source, target]: ignored")))))

;; ====== STARTED AGAIN ======

(ert-deftest agent-workspace-saved/its-role-s-kind ()
  "An agent runs its role's kind (kind:), else `agent-workspace-kind': that
one isn't written, and it comes back from its role; another is written."
  (+test-aws2 "role-kind"
    (let* ((agent-workspace-kinds (append agent-workspace-kinds '((robot :config ignore) (droid :config ignore))))
           (roles agent-workspace-role-function)
           (agent-workspace-role-function
            (lambda (project name)
              (let ((role (funcall roles project name)))
                (if (equal name "investigator") (plist-put (copy-sequence role) :kind 'robot) role)))))
      (let ((sam (agent-workspace-create :role "investigator" :name "sam"))
            (ada (agent-workspace-create :role "builder" :name "ada"))
            (ken (agent-workspace-create :role "builder" :name "ken" :kind 'droid)))
        (should (eq (agent-workspace-agent-kind sam) 'robot))
        (should (eq (agent-workspace-agent-kind ada) 'claude-code))
        (should (eq (agent-workspace-agent-kind ken) 'droid))
        (let ((text (+test-aws2--compact (agent-workspace-crew-text project))))
          (should (string-search "{\"name\": \"sam\", \"role\": \"investigator\", \"colour\": \"magenta\"}" text))
          (should (string-search "\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"kind\": \"droid\"" text))))
      (agent-workspace-crew-save project)
      (agent-workspace-close project)
      (agent-workspace-open t)
      (should (eq (agent-workspace-agent-kind (agent-workspace-agent "sam" project)) 'robot))
      (should (eq (agent-workspace-agent-kind (agent-workspace-agent "ada" project)) 'claude-code))
      (should (eq (agent-workspace-agent-kind (agent-workspace-agent "ken" project)) 'droid)))))

(ert-deftest agent-workspace-saved/started-again ()
  "SPC o w with no crew running: every agent in crew.json again, fresh, in its
worktree (reused), its colour, model, mode; asleep ones asleep (no session);
one whose role is gone stuck, saying why; the selected one's pane open."
  (+test-aws2 "again"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (write-region "work\n" nil (expand-file-name "wip" (agent-workspace-agent-worktree ada))))
    (agent-workspace-close project)
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\"},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"asleep\": true},
  {\"name\": \"sam\", \"role\": \"investigator\", \"colour\": \"magenta\", \"model\": \"opus\", \"mode\": \"plan\"},
  {\"name\": \"tim\", \"role\": \"wizard\", \"colour\": \"cyan\"}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"sam\", \"open\": true}}
")
    (setq started nil)
    (let ((app (agent-workspace-open t)))
      (should (equal (sort (copy-sequence started) #'string<) '("ada" "sam")))
      (let ((ada (agent-workspace-agent "ada" project))
            (ken (agent-workspace-agent "ken" project))
            (sam (agent-workspace-agent "sam" project))
            (tim (agent-workspace-agent "tim" project)))
        (should (eq (agent-workspace-agent-state ada) 'desk))
        (should (file-exists-p (expand-file-name "wip" (agent-workspace-agent-worktree ada))))
        (should (eq (agent-workspace-agent-state ken) 'asleep))
        (should-not (agent-workspace-agent-buffer ken))
        (should (file-directory-p (agent-workspace-agent-worktree ken)))
        (should (equal (list (agent-workspace-agent-colour sam) (agent-workspace-agent-model sam)
                             (agent-workspace-agent-mode sam))
                       '("magenta" "opus" "plan")))
        (should (eq (agent-workspace-agent-state tim) 'stuck))
        (should (equal (agent-workspace-agent-error tim) "its role wizard is gone"))
        (should (eq (agent-workspace--app-selected app) sam))
        (should (eq (agent-workspace--app-open app) sam))
        (should (get-buffer-window (agent-workspace-agent-buffer sam)))))
    ;; Started again: crew.json as it was (nothing written meanwhile).
    (should (string-search "{\"name\": \"tim\", \"role\": \"wizard\"" (+test-aws2--file project)))))

(ert-deftest agent-workspace-saved/its-talk-switch-kept ()
  "A new crew's agents message each other freely (`agent-workspace-talk',
on), crew.json saying so; a crew whose crew.json says ask keeps asking,
started again (each agent's session started once the switch is set, the
whole crew there), until T changes it (doom-pbk.137, doom-pbk.147)."
  (should (eq (default-value 'agent-workspace-talk) 'on))
  (+test-aws2 "talk-new"
    (agent-workspace-create :role "builder" :name "ada")
    (should (eq (agent-workspace-talk-mode project) 'on))
    (should (string-search "\"talk\": \"on\"" (+test-aws2--file project))))
  (+test-aws2 "talk-ask"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\"},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\"}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"talk\": \"ask\"}}
")
    (let ((told nil)
          (start (symbol-function 'agent-workspace--start)))
      ;; Each started with the whole crew there, the switch as crew.json
      ;; says (doom-pbk.147: set after they'd all started).
      (cl-letf (((symbol-function 'agent-workspace--start)
                 (lambda (agent)
                   (push (list (agent-workspace-agent-name agent) (agent-workspace-talk-mode project)
                               (mapcar #'agent-workspace-agent-name (agent-workspace-agents project)))
                         told)
                   (funcall start agent))))
        (agent-workspace-open t))
      (should (equal (reverse told) '(("ada" ask ("ada" "ken")) ("ken" ask ("ada" "ken"))))))
    (should (agent-workspace-agent "ada" project))
    (should (eq (agent-workspace-talk-mode project) 'ask))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-talk-cycle))
    (should (eq (agent-workspace-talk-mode project) 'on))
    (agent-workspace-crew-save project)
    (should (string-search "\"talk\": \"on\"" (+test-aws2--file project)))))

(ert-deftest agent-workspace-saved/an-agent-made-while-it-doesn-t-run ()
  "An agent made with no crew running (M-x, cmd, Lisp: no app open):
crew.json keeps its saved agents and its layout as they were, beside it; a
write after (it's recoloured) too. The app opened: they start beside it,
asleep ones asleep, its layout applied; crew.json then as the app has it
\(doom-pbk.56)."
  (+test-aws2 "made-meanwhile"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"loop\": true, \"panels\": [\"logs\", \"tests\"]},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"model\": \"opus\", \"asleep\": true},
  {\"name\": \"tim\", \"role\": \"builder\", \"colour\": \"cyan\"}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ken\", \"open\": false, \"minimap\": false, \"talk\": \"on\", \"sources_off\": [[\"ci\", \"#reviewer\"]]}}
")
    (let ((sam (agent-workspace-create :role "investigator" :name "sam")))
      (should (equal started '("sam")))
      (should (equal (+test-aws2--file project) "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"loop\": true, \"panels\": [\"logs\", \"tests\"]},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"model\": \"opus\", \"asleep\": true},
  {\"name\": \"tim\", \"role\": \"builder\", \"colour\": \"cyan\"},
  {\"name\": \"sam\", \"role\": \"investigator\", \"colour\": \"magenta\"}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ken\", \"open\": false, \"minimap\": false, \"talk\": \"on\", \"sources_off\": [[\"ci\", \"#reviewer\"]]}}
"))
      (agent-workspace-recolour sam "yellow")
      (should (string-search "{\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"model\": \"opus\", \"asleep\": true}"
                             (+test-aws2--file project)))
      (should (string-search "{\"name\": \"sam\", \"role\": \"investigator\", \"colour\": \"yellow\"}"
                             (+test-aws2--file project))))
    ;; The app opened: the saved ones start beside sam.
    (setq started nil)
    (cl-letf (((symbol-function 'agent-workspace--loop-soon) #'ignore)
              ((symbol-function 'agent-workspace--loop-watch-update) #'ignore))
      (let ((app (agent-workspace-open t)))
        (should (equal started '("tim")))
        (should (equal (mapcar #'agent-workspace-agent-name (agent-workspace-agents project))
                       '("sam" "ada" "ken" "tim")))
        (let ((ada (agent-workspace-agent "ada" project))
              (ken (agent-workspace-agent "ken" project)))
          (should (eq (agent-workspace-agent-state ada) 'asleep))
          (should (agent-workspace-agent-loop ada))
          (should (equal (gethash ada agent-workspace--crew-panels) '("logs" "tests")))
          (should (eq (agent-workspace-agent-state ken) 'asleep))
          (should (equal (agent-workspace-agent-model ken) "opus"))
          (should (eq (agent-workspace--app-selected app) ken)))
        (should (eq (agent-workspace--talk-switch project) 'on))
        (should (equal (agent-workspace-inbox-sources-off project) '(("ci" . "#reviewer"))))
        (should-not (gethash (agent-workspace--root project) agent-workspace--crew-kept))
        (agent-workspace-crew-save project)
        (let ((text (+test-aws2--file project)))
          (dolist (name '("ada" "ken" "sam" "tim"))
            (should (string-search (format "{\"name\": \"%s\"" name) text)))
          (should (string-search "\"selected\": \"ken\", \"open\": false" text)))))))

(ert-deftest agent-workspace-saved/a-crew-picked-while-it-doesn-t-run ()
  "A crew picked with no crew running (M-x, cmd: no app open): the agents
crew.json keeps are the crew's, counted as its running ones are, their names
and initials not given again (doom-pbk.128). Every agent of full kept:
nothing to add (its row in c's menu says so), nothing made, crew.json only
looked at. A scribe and a builder kept: a reviewer made; the app opened,
the three run, none asleep for its role's max."
  (+test-aws2 "crew-meanwhile"
    (let ((full "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"scribe\"},
  {\"name\": \"grace\", \"role\": \"builder\"},
  {\"name\": \"linus\", \"role\": \"reviewer\"}
 ]}
"))
      (+test-aws2--write project full)
      (should (equal (agent-workspace-crew-members project)
                     '(("ada" . "scribe") ("grace" . "builder") ("linus" . "reviewer"))))
      (should-not (agent-workspace-crew-missing
                   project (alist-get "full" (agent-workspace-crew-specs project) nil nil #'equal)))
      (should-not (plist-get (alist-get "full" (agent-workspace--crew-facts project) nil nil #'equal) :missing))
      (should (equal (agent-workspace-crew-make project "full") '(nil nil nil)))
      (should-not (agent-workspace-agents project))
      (should-not started)
      (should (equal (with-temp-buffer (insert-file-contents (+test-aws2--path project)) (buffer-string)) full))
      ;; Only looked at: one edited by hand meanwhile isn't taken as read.
      (should-not (gethash (agent-workspace--root project) agent-workspace--crew-seen)))
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"scribe\"},
  {\"name\": \"grace\", \"role\": \"builder\"}
 ]}
")
    (should (equal (agent-workspace-crew-agents-text
                    (plist-get (alist-get "full" (agent-workspace--crew-facts project) nil nil #'equal) :missing))
                   "reviewer"))
    (pcase-let ((`(,made ,failed ,text) (agent-workspace-crew-make project "full")))
      (should (equal (mapcar #'agent-workspace-agent-name made) '("linus")))
      (should-not failed)
      (should (equal text "crew full: + reviewer linus")))
    (should (equal (reverse started) '("linus")))
    (let ((text (+test-aws2--file project)))
      (dolist (name '("ada" "grace" "linus"))
        (should (string-search (format "{\"name\": \"%s\"" name) text))))
    ;; The app opened: the kept ones start beside them, none over its max.
    (setq started nil)
    (cl-letf (((symbol-function 'agent-workspace--loop-soon) #'ignore)
              ((symbol-function 'agent-workspace--loop-watch-update) #'ignore))
      (agent-workspace-open t)
      (should (equal (sort started #'string<) '("ada" "grace")))
      (should (equal (sort (mapcar #'agent-workspace-agent-name (agent-workspace-agents project)) #'string<)
                     '("ada" "grace" "linus")))
      (should-not (seq-some (lambda (agent) (eq (agent-workspace-agent-state agent) 'asleep))
                            (agent-workspace-agents project)))
      (should (equal (agent-workspace-crew-make project "full") '(nil nil nil))))))

(defun +test-aws2--request (op payload)
  "OP's reply (parsed) as cmd/agent-workspace gets it from
`default-directory': a request folder with PAYLOAD (JSON text)."
  (let ((dir (make-temp-file (+test-tmp-file "aws2-request-") t)))
    (with-temp-file (expand-file-name "request" dir) (insert op "\n" default-directory "\n"))
    (with-temp-file (expand-file-name "payload" dir) (insert payload))
    (should (eq (agent-workspace-request dir) t))
    (with-temp-buffer
      (insert-file-contents (expand-file-name "reply" dir))
      (json-parse-buffer :object-type 'plist :false-object nil :null-object nil))))

(ert-deftest agent-workspace-saved/a-saved-agent-s-name-and-colour ()
  "An agent crew.json keeps, not running, still has its name and colour
\(doom-pbk.138): a new agent named as it is refused, as for one running (c's
name prompt asks again, cmd new and a rename are refused), and crew.json
keeps it; a new agent's colour is none of theirs while one is free."
  (+test-aws2 "saved-names"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"scribe\", \"colour\": \"blue\"},
  {\"name\": \"grace\", \"role\": \"builder\", \"colour\": \"magenta\"}
 ]}
")
    (let ((said nil))
      ;; c, builder, ada: refused, asked again; tim made.
      (cl-letf* ((answers '("builder" "ada" "tim"))
                 (answer (lambda (&rest _) (or (pop answers) (error "Asked more"))))
                 ((symbol-function 'completing-read) answer)
                 ((symbol-function 'read-string) answer)
                 ((symbol-function 'sit-for) #'ignore)
                 ((symbol-function 'message)
                  (lambda (format &rest args) (when format (push (apply #'format format args) said)))))
        ;; Not running: crew.json read.
        (should (string-match-p "\\`There.s an agent named ada already\\'"
                                (plist-get (+test-aws2--request "new" "{\"role\":\"builder\",\"name\":\"ada\"}")
                                           :error)))
        (should (equal (agent-workspace-free-colour project "blue") "green"))
        (let ((tim (agent-workspace-new)))
          (should (seq-find (lambda (text) (string-match-p "\\`There.s an agent named ada already\\'" text)) said))
          (should (equal (agent-workspace-agent-name tim) "tim"))
          ;; The builder's blue is ada's, magenta grace's.
          (should (equal (agent-workspace-agent-colour tim) "green"))
          (should (equal (agent-workspace-agents project) (list tim)))
          ;; Running beside the kept crew: its names still taken.
          (should (string-match-p "\\`There.s an agent named grace already\\'"
                                  (plist-get (+test-aws2--request "new" "{\"role\":\"reviewer\",\"name\":\"grace\"}")
                                             :error)))
          (dolist (name '("ada" "grace"))
            (should (string-match-p (format "\\`There.s an agent named %s already\\'" name)
                                    (cadr (should-error (agent-workspace-rename tim name) :type 'user-error)))))
          (should (equal (agent-workspace-free-colour project "blue") "yellow"))
          (should (equal (agent-workspace-agents project) (list tim))))))
    (let ((text (+test-aws2--file project)))
      (should (string-search "{\"name\": \"ada\", \"role\": \"scribe\", \"colour\": \"blue\"}" text))
      (should (string-search "{\"name\": \"grace\", \"role\": \"builder\", \"colour\": \"magenta\"}" text))
      (should (string-search "{\"name\": \"tim\", \"role\": \"builder\", \"colour\": \"green\"}" text)))))

(ert-deftest agent-workspace-saved/no-more-than-its-role-allows ()
  "Five builders in crew.json (a builder's max 4): four start, the fifth
stays asleep, said; r on it is refused as s is, until one stops
\(doom-pbk.41)."
  (+test-aws2 "max"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\"},
  {\"name\": \"ben\", \"role\": \"builder\"},
  {\"name\": \"cal\", \"role\": \"builder\"},
  {\"name\": \"dan\", \"role\": \"builder\"},
  {\"name\": \"eve\", \"role\": \"builder\"}
 ]}
")
    (setq started nil)
    (agent-workspace-open t)
    (should (equal (sort (copy-sequence started) #'string<) '("ada" "ben" "cal" "dan")))
    (let ((eve (agent-workspace-agent "eve" project)))
      (should (eq (agent-workspace-agent-state eve) 'asleep))
      (should (string-search "eve      stays asleep: 4 builders run already, as many as the role allows"
                             (with-current-buffer (agent-workspace--room-buffer project) (buffer-string))))
      (should (equal (cadr (should-error (agent-workspace-restart eve) :type 'user-error))
                     "4 builders run already, as many as the role allows"))
      (should-error (agent-workspace-wake eve) :type 'user-error)
      (agent-workspace-sleep (agent-workspace-agent "ada" project))
      (agent-workspace-restart eve)
      (should (eq (agent-workspace-agent-state eve) 'desk)))))

(ert-deftest agent-workspace-saved/one-emacs-a-crew ()
  "The crew's lock naming another Emacs, alive: SPC o w and an agent made
are refused, saying where it runs. That Emacs gone: its lock taken over,
the crew starts here, the lock this Emacs's; closed, the lock goes
\(doom-pbk.66)."
  (+test-aws2 "lock"
    (let* ((lock (expand-file-name ".agent-shell/agent-workspace/crew.lock" project))
           (other (make-process :name "other-emacs" :noquery t :connection-type 'pipe
                                :command (list (expand-file-name invocation-name invocation-directory)
                                               "--batch" "-Q" (concat "--init-directory=" (+test-tmp-file "other-emacs/"))
                                               "--eval" "(sleep-for 60)"))))
      (unwind-protect
          (progn
            (make-directory (file-name-directory lock) t)
            (write-region (format "%d somewhere\n" (process-id other)) nil lock)
            (should (string-match-p "\\`The crew of lock runs in another Emacs (pid [0-9]+): open it there\\'"
                                    (cadr (should-error (agent-workspace-open t) :type 'user-error))))
            (should-not (agent-workspace--app project))
            (should-error (agent-workspace-create :role "builder" :name "ada") :type 'user-error)
            (should-not (agent-workspace-agents project)))
        (delete-process other))
      ;; `delete-process' only sends its kill: the process may still run a
      ;; moment after (on Linux CI the lock was refused once more).
      (should (+test-wait-for (lambda () (not (agent-workspace--crew-lock-holder project))) 5))
      ;; Gone: taken over.
      (agent-workspace-open t)
      (agent-workspace-create :role "builder" :name "ada")
      (should (string-prefix-p (format "%d " (emacs-pid))
                               (with-temp-buffer (insert-file-contents lock) (buffer-string))))
      (agent-workspace-close project)
      (should-not (file-exists-p lock)))))

(ert-deftest agent-workspace-saved/closed-and-opened-again ()
  "Q, then SPC o w: the same agents (names, roles, colours, models, modes),
fresh, waiting; the asleep one asleep; the same agent selected."
  (+test-aws2 "cycle"
    (agent-workspace-open t)
    (agent-workspace-create :role "builder" :name "ada" :colour "yellow")
    (agent-workspace-create :role "investigator" :name "sam" :model "haiku")
    (let ((ken (agent-workspace-create :role "builder" :name "ken")))
      (agent-workspace-sleep ken))
    (agent-workspace-select (agent-workspace-agent "sam" project))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-quit))
    (should-not (agent-workspace-agents project))
    (setq started nil)
    (let ((app (agent-workspace-open t)))
      (should (equal (mapcar (lambda (agent)
                               (list (agent-workspace-agent-name agent) (agent-workspace-agent-role agent)
                                     (agent-workspace-agent-colour agent) (agent-workspace-agent-model agent)
                                     (agent-workspace-agent-state agent)))
                             (agent-workspace--ordered project))
                     '(("ada" "builder" "yellow" nil desk) ("ken" "builder" "blue" nil asleep)
                       ("sam" "investigator" "magenta" "haiku" desk))))
      (should (equal (sort (copy-sequence started) #'string<) '("ada" "sam")))
      (should (equal (agent-workspace-agent-name (agent-workspace--app-selected app)) "sam")))))

(ert-deftest agent-workspace-saved/read-again ()
  "gR: an agent added to crew.json started, one taken out forgotten, each
asked first; a colour changed applied."
  (+test-aws2 "reload"
    (agent-workspace-open t)
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"red\"},
  {\"name\": \"sam\", \"role\": \"scribe\", \"colour\": \"cyan\"}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ada\", \"open\": true}}
")
    (let ((asked nil))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) t)))
        (with-current-buffer (agent-workspace--issues-buffer project)
          (agent-workspace-crew-reload)))
      (should (equal (reverse asked) '("Start sam (scribe), new in crew.json? "
                                       "Forget ken, gone from crew.json (its worktree kept)? "))))
    (should (equal (mapcar #'agent-workspace-agent-name (agent-workspace--ordered project)) '("ada" "sam")))
    (should (equal (agent-workspace-agent-colour (agent-workspace-agent "ada" project)) "red"))
    (should (eq (agent-workspace-agent-state (agent-workspace-agent "sam" project)) 'desk))))

(ert-deftest agent-workspace-saved/its-loops-read-again ()
  "gR: a loop crew.json turns on asked first (it starts work); one it turns
off, applied."
  (skip-unless (executable-find "bd"))
  (+test-aws2 "reload-loops"
    (make-directory (expand-file-name ".beads" project))
    ;; Its looks and its watch on .beads not here: file-notify's events, read
    ;; by a later test's `read-event', made a question there (a panel's
    ;; trust) ask forever.
    (cl-letf (((symbol-function 'agent-workspace--loop-soon) #'ignore)
              ((symbol-function 'agent-workspace--loop-watch-update) #'ignore))
      (agent-workspace-open t)
      (let ((ada (agent-workspace-create :role "builder" :name "ada"))
            (ken (agent-workspace-create :role "builder" :name "ken")))
        (agent-workspace-loop-set ken t)
        (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"loop\": true},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\"}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ada\", \"open\": true}}
")
        (let ((asked nil))
          (cl-letf (((symbol-function 'y-or-n-p) (lambda (prompt) (push prompt asked) t)))
            (with-current-buffer (agent-workspace--issues-buffer project)
              (agent-workspace-crew-reload)))
          (should (equal asked '("Turn ada's loop on, as crew.json says? "))))
        (should (agent-workspace-agent-loop ada))
        (should-not (agent-workspace-agent-loop ken))))))

;; ====== AN AGENT'S PANELS ======

(defconst +test-aws2--panel
  ";;; panel.el --- Agent UI panel -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type \"text\" :id \"t\" :text \"\")
 :every 60
 :fetch (lambda (panel) (agent-ui-panel-update panel \"t\" :text default-directory)))
"
  "A panel showing where it runs.")

(defmacro +test-aws2-panels (name &rest body)
  "BODY as `+test-aws2' runs it, its project with two panels committed, logs
and tests, and trusted (the trust file the test's own); the panels open
closed after."
  (declare (indent 1))
  `(let ((agent-ui-panel-trust-file (+test-tmp-file (format "aws2-trust-%s.eld" ,name))))
     (unwind-protect
         (+test-aws2 ,name
           (let ((default-directory project))
             (make-directory ".agent-ui/panels" t)
             (dolist (panel '("logs" "tests"))
               (write-region +test-aws2--panel nil (format ".agent-ui/panels/%s.el" panel)))
             (call-process "git" nil nil nil "add" ".agent-ui")
             (call-process "git" nil nil nil "-c" "user.name=T" "-c" "user.email=t@t" "commit" "-q" "-m" "panels"))
           (agent-ui-panel-trust-project project)
           ,@body)
       (dolist (buffer (buffer-list))
         (when (buffer-local-value 'agent-ui-panels--state buffer)
           (let ((kill-buffer-query-functions nil))
             (kill-buffer buffer)))))))

(defun +test-aws2--open-panel (agent name)
  "Panel NAME opened as AGENT's session opens one (agent-ui open NAME)."
  (agent-ui-open-panel name (agent-workspace-agent-worktree agent) t))

(defun +test-aws2--open-panels ()
  "The panels open: their canvases' names."
  (sort (mapcar #'buffer-name
                (seq-filter (lambda (buffer) (buffer-local-value 'agent-ui-panels--state buffer))
                            (buffer-list)))
        #'string<))

(defun +test-aws2--draft (agent)
  "A panel's file elsewhere in AGENT's worktree: drafts/try.el."
  (let ((draft (expand-file-name "drafts/try.el" (agent-workspace-agent-worktree agent))))
    (make-directory (file-name-directory draft) t)
    (write-region +test-aws2--panel nil draft)))

(ert-deftest agent-workspace-saved/panels-kept-across-a-rename ()
  "An agent renamed (its worktree moved): its panels open again in its new
worktree, named after it, one from a file there too; crew.json keeps them
(doom-ukm.6)."
  (+test-aws2-panels "panels-renamed"
    (let ((ada (agent-workspace-create :role "builder" :name "ada")))
      (+test-aws2--draft ada)
      (+test-aws2--open-panel ada "tests")
      (+test-aws2--open-panel ada "drafts/try.el")
      (agent-workspace-rename ada "grace")
      (+test-sleep 0.1)
      (should (equal (+test-aws2--open-panels) '("Agent UI: tests · grace" "Agent UI: try · grace")))
      (dolist (canvas (agent-workspace-agent-panels ada))
        (should (equal (file-name-as-directory
                        (file-truename (agent-ui-panels--root (buffer-local-value 'agent-ui-panels--state canvas))))
                       (file-name-as-directory (file-truename (agent-workspace-agent-worktree ada))))))
      (should (string-search "{\"name\": \"grace\", \"role\": \"builder\", \"colour\": \"blue\", \"panels\": [\"drafts/try.el\", \"tests\"]}"
                             (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/an-agents-panels-written ()
  "An agent's open panels in its entry, by name, sorted: written as one opens
or closes; none, no panels (put to sleep, they close: gone from it). One
opened from a file of its worktree: that file. Yours, from the main
checkout: in no agent's."
  (+test-aws2-panels "panels-written"
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken")))
      (+test-aws2--open-panel ada "tests")
      (should (string-search "{\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"panels\": [\"tests\"]}"
                             (+test-aws2--file project)))
      (let ((logs (+test-aws2--open-panel ada "logs")))
        (+test-aws2--open-panel ken "tests")
        (agent-ui-open-panel "tests" project)
        (should (string-search "\"colour\": \"blue\", \"panels\": [\"logs\", \"tests\"]}" (+test-aws2--file project)))
        (should (string-search "{\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"magenta\", \"panels\": [\"tests\"]}"
                               (+test-aws2--file project)))
        (kill-buffer logs)
        (+test-sleep 0.1)
        (should (string-search "\"colour\": \"blue\", \"panels\": [\"tests\"]}" (+test-aws2--file project))))
      (+test-aws2--draft ada)
      (+test-aws2--open-panel ada "drafts/try.el")
      (should (equal (agent-workspace-agent-panel-names ada) '("drafts/try.el" "tests")))
      (should (string-search "\"panels\": [\"drafts/try.el\", \"tests\"]}" (+test-aws2--file project)))
      (agent-workspace-sleep ken)
      (+test-sleep 0.1)
      (should (string-search "{\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"magenta\", \"asleep\": true}"
                             (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/closing-keeps-the-panels ()
  "The crew closed: its agents' panels close with them, crew.json keeps them
\(Q; agent-workspace-close with its app open); a write still to come, with
them, done first."
  (+test-aws2-panels "panels-closing"
    (agent-workspace-open t)
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (tests (+test-aws2--open-panel ada "tests"))
           (text (+test-aws2--file project)))
      (should (string-search "\"panels\": [\"tests\"]" text))
      (with-current-buffer (agent-workspace--issues-buffer project)
        (agent-workspace-quit))
      (should-not (buffer-live-p tests))
      (+test-sleep 0.2)
      (should (equal (+test-aws2--file project) text))))
  (+test-aws2-panels "panels-closing-app-open"
    (agent-workspace-open t)
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (tests (+test-aws2--open-panel ada "tests"))
           (text (+test-aws2--file project)))
      (agent-workspace-close project)
      (should-not (buffer-live-p tests))
      (+test-sleep 0.2)
      (should (equal (+test-aws2--file project) text))))
  ;; One closed as the crew closes (its change said after): nothing written
  ;; after, its crew gone.
  (+test-aws2-panels "panels-closing-at-once"
    (agent-workspace-open t)
    (let* ((ada (agent-workspace-create :role "builder" :name "ada"))
           (logs (+test-aws2--open-panel ada "logs"))
           (text (progn (+test-aws2--open-panel ada "tests") (+test-aws2--file project))))
      (kill-buffer logs)
      (agent-workspace-close project)
      (+test-sleep 0.2)
      (should (equal (+test-aws2--file project) text))))
  ;; Debounced for real: the write closing does has them.
  (+test-aws2-panels "panels-flushed"
    (cl-letf* ((run-at-time (symbol-function 'run-at-time))
               ((symbol-function 'run-at-time)
                (lambda (time repeat fn &rest args)
                  (if (eq fn #'agent-workspace-crew-save)
                      (funcall run-at-time 3600 nil #'ignore)
                    (apply run-at-time time repeat fn args)))))
      (let ((ada (agent-workspace-create :role "builder" :name "ada")))
        (+test-aws2--open-panel ada "tests")
        (should-not (+test-aws2--file project))
        (agent-workspace-close project)
        (+test-sleep 0.2)
        (should (string-search "{\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"panels\": [\"tests\"]}"
                               (+test-aws2--file project)))))))

(ert-deftest agent-workspace-saved/wrong-panels-left-out ()
  "An entry whose panels aren't a list of names is left out, said by its
place and name."
  (+test-aws2 "wrong-panels"
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"panels\": [\"tests\"]},
  {\"name\": \"ken\", \"role\": \"builder\", \"panels\": \"tests\"},
  {\"name\": \"sam\", \"role\": \"builder\", \"panels\": [\"tests\", 3]},
  {\"name\": \"tim\", \"role\": \"builder\", \"panels\": {\"tests\": \"logs\"}},
  {\"name\": \"una\", \"role\": \"builder\", \"panels\": [\"\"]}
 ],
 \"layout\": null}
")
    (pcase-let ((`(,crew . ,problems) (agent-workspace-crew-read project)))
      (should (equal (plist-get crew :agents) '((:name "ada" :role "builder" :panels ("tests")))))
      (should (equal problems
                     '("crew.json: agent 2 (ken): its panels \"tests\" aren't a list of names: left out"
                       "crew.json: agent 3 (sam): its panels [\"tests\", 3] aren't a list of names: left out"
                       "crew.json: agent 4 (tim): its panels {\"tests\": \"logs\"} aren't a list of names: left out"
                       "crew.json: agent 5 (una): its panels [\"\"] aren't a list of names: left out"))))))

(ert-deftest agent-workspace-saved/panels-opened-again ()
  "Started again from crew.json: each agent that starts opens its panels again,
in its worktree (its own, shown only as its pane's tabs: one at a time); an
asleep one, none; one whose file is gone skipped, said, the others open.
Nothing written meanwhile."
  (+test-aws2-panels "panels-again"
    (agent-workspace-create :role "builder" :name "ada")
    (agent-workspace-create :role "builder" :name "ken")
    (agent-workspace-close project)
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"panels\": [\"gone\", \"logs\", \"tests\"]},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"asleep\": true, \"panels\": [\"tests\"]}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ada\", \"open\": true}}
")
    (let ((warned nil))
      (cl-letf (((symbol-function 'display-warning) (lambda (_type message &rest _) (push message warned))))
        (agent-workspace-open t))
      (let ((ada (agent-workspace-agent "ada" project)))
        (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ada" "Agent UI: tests · ada")))
        (dolist (canvas (agent-workspace-agent-panels ada))
          (should (equal (file-truename (agent-ui-panels--root (buffer-local-value 'agent-ui-panels--state canvas)))
                         (file-truename (agent-workspace-agent-worktree ada))))
          (dolist (window (get-buffer-window-list canvas nil t))
            (should (eq (window-parameter window 'agent-workspace-side) ada))))
        (should (<= (seq-count (lambda (canvas) (get-buffer-window canvas t)) (agent-workspace-agent-panels ada))
                    1)))
      (should (equal warned '("ada's panel gone: not one of this project's: logs, tests: skipped"))))
    (should (string-search "\"panels\": [\"gone\", \"logs\", \"tests\"]" (+test-aws2--file project)))))

(ert-deftest agent-workspace-saved/an-asleep-agents-panels-when-it-wakes ()
  "Started again asleep: its panels kept in crew.json (written meanwhile), none
open; woken, they open (doom-ukm.7)."
  (+test-aws2-panels "asleep-panels"
    (agent-workspace-create :role "builder" :name "ken")
    (agent-workspace-close project)
    (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"green\", \"asleep\": true, \"panels\": [\"logs\", \"tests\"]}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ken\", \"open\": true}}
")
    (agent-workspace-open t)
    (let ((ken (agent-workspace-agent "ken" project)))
      (should (eq (agent-workspace-agent-state ken) 'asleep))
      (should-not (+test-aws2--open-panels))
      (agent-workspace-recolour ken "blue")
      (should (string-search "{\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"blue\", \"asleep\": true, \"panels\": [\"logs\", \"tests\"]}"
                             (+test-aws2--file project)))
      (agent-workspace-wake ken)
      (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ken" "Agent UI: tests · ken")))
      (+test-sleep 0.1)
      (should (string-search "{\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"blue\", \"panels\": [\"logs\", \"tests\"]}"
                             (+test-aws2--file project))))))

(ert-deftest agent-workspace-saved/read-again-applies-panels ()
  "gR after crew.json's panels edited: a running agent's opened and closed as
listed; an asleep one's kept for when it wakes (doom-ukm.7)."
  (+test-aws2-panels "reload-panels"
    (agent-workspace-open t)
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken")))
      (+test-aws2--open-panel ada "tests")
      (agent-workspace-sleep ken)
      (+test-sleep 0.1)
      (+test-aws2--write project "{\"version\": 2,
 \"agents\": [
  {\"name\": \"ada\", \"role\": \"builder\", \"colour\": \"blue\", \"panels\": [\"logs\"]},
  {\"name\": \"ken\", \"role\": \"builder\", \"colour\": \"magenta\", \"asleep\": true, \"panels\": [\"tests\"]}
 ],
 \"layout\": {\"view\": \"stage\", \"room\": \"right\", \"selected\": \"ada\", \"open\": true}}
")
      (with-current-buffer (agent-workspace--issues-buffer project)
        (agent-workspace-crew-reload))
      (+test-sleep 0.1)
      (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ada")))
      (agent-workspace-wake ken)
      (should (equal (+test-aws2--open-panels) '("Agent UI: logs · ada" "Agent UI: tests · ken"))))))

(ert-deftest agent-workspace-saved/panels-closed-and-opened-again ()
  "Q, then SPC o w: each agent's panels open again with it, in its worktree
\(one from a file there too); the one put to sleep closed its own: none."
  (+test-aws2-panels "panels-cycle"
    (agent-workspace-open t)
    (let ((ada (agent-workspace-create :role "builder" :name "ada"))
          (ken (agent-workspace-create :role "builder" :name "ken"))
          (sam (agent-workspace-create :role "builder" :name "sam")))
      (+test-aws2--draft ada)
      (+test-aws2--open-panel ada "tests")
      (+test-aws2--open-panel ada "logs")
      (+test-aws2--open-panel ada "drafts/try.el")
      (+test-aws2--open-panel ken "tests")
      (+test-aws2--open-panel sam "logs")
      (agent-workspace-sleep sam)
      (+test-sleep 0.1))
    (with-current-buffer (agent-workspace--issues-buffer project)
      (agent-workspace-quit))
    (should-not (+test-aws2--open-panels))
    (agent-workspace-open t)
    (should (equal (+test-aws2--open-panels)
                   '("Agent UI: logs · ada" "Agent UI: tests · ada" "Agent UI: tests · ken" "Agent UI: try · ada")))
    (should (equal (agent-workspace-agent-panel-names (agent-workspace-agent "ada" project))
                   '("drafts/try.el" "logs" "tests")))
    (should (eq (agent-workspace-agent-state (agent-workspace-agent "sam" project)) 'asleep))))

;; ====== A ROUND TRIP ======

(ert-deftest agent-workspace-saved/a-crew-round-trips ()
  "Written, read back, started again: the same crew (a model, a mode, a
kind, asleep, a loop, panels) and layout (talk, sources_off, selected, open,
minimap); written again after, the same text."
  (+test-aws2-panels "round-trip"
    (let ((agent-workspace-kinds (append agent-workspace-kinds '((robot :config ignore))))
          (agent-workspace--talk (make-hash-table :test #'equal))
          (agent-workspace--sources-off (make-hash-table :test #'equal))
          (agent-workspace--minimap-shown (make-hash-table :test #'equal)))
      ;; Its looks and its watch on .beads not here (see its-loops-read-again).
      (cl-letf (((symbol-function 'agent-workspace--loop-soon) #'ignore)
                ((symbol-function 'agent-workspace--loop-watch-update) #'ignore))
        (agent-workspace-open t)
        (let ((ada (agent-workspace-create :role "builder" :name "ada" :model "opus" :mode "plan"))
              (ken (agent-workspace-create :role "builder" :name "ken" :colour "green"))
              (sam (agent-workspace-create :role "investigator" :name "sam" :kind 'robot)))
          (+test-aws2--open-panel ada "logs")
          (+test-aws2--open-panel ada "tests")
          (setf (agent-workspace-agent-loop ken) t)
          (agent-workspace-sleep ken)
          (agent-workspace-select sam))
        (agent-workspace--talk-set project 'off)
        (agent-workspace--inbox-set-sources-off project '(("ci" . "#all") ("cal" . "ada")))
        (agent-workspace--minimap-set project nil)
        (agent-workspace-crew-save project)
        (let ((text (+test-aws2--file project)))
          (should (equal (agent-workspace-crew-read project)
                         '((:agents ((:name "ada" :role "builder" :colour "blue" :model "opus" :mode "plan"
                                      :panels ("logs" "tests"))
                                     (:name "ken" :role "builder" :colour "green" :asleep t :loop t)
                                     (:name "sam" :role "investigator" :colour "magenta" :kind robot))
                            :layout (:view stage :room right :selected "sam" :open t :minimap nil :talk off
                                     :sources-off (("ci" . "#all") ("cal" . "ada")))))))
          (with-current-buffer (agent-workspace--issues-buffer project)
            (agent-workspace-quit))
          (should-not (agent-workspace-agents project))
          (clrhash agent-workspace--talk)
          (clrhash agent-workspace--sources-off)
          (clrhash agent-workspace--minimap-shown)
          (let ((app (agent-workspace-open t))
                (ada (agent-workspace-agent "ada" project))
                (ken (agent-workspace-agent "ken" project))
                (sam (agent-workspace-agent "sam" project)))
            (should (equal (list (agent-workspace-agent-model ada) (agent-workspace-agent-mode ada)
                                 (agent-workspace-agent-panel-names ada))
                           '("opus" "plan" ("logs" "tests"))))
            (should (equal (list (agent-workspace-agent-colour ken) (agent-workspace-agent-state ken)
                                 (agent-workspace-agent-loop ken))
                           '("green" asleep t)))
            (should (eq (agent-workspace-agent-kind sam) 'robot))
            (should (eq (agent-workspace--talk-switch project) 'off))
            (should (equal (agent-workspace-inbox-sources-off project) '(("ci" . "#all") ("cal" . "ada"))))
            (should-not (agent-workspace-minimap-shown-p project))
            (should (eq (agent-workspace--app-selected app) sam))
            (should (eq (agent-workspace--app-open app) sam)))
          (agent-workspace-crew-save project)
          (should (equal (+test-aws2--file project) text)))))))

(ert-deftest agent-workspace-saved/an-old-crew-file-left-alone ()
  "The crew's file before crew.json, .agent-workspace/crew.el, neither read
nor touched: no crew started from it, nothing written beside it."
  (+test-aws2 "old"
    (let ((old (expand-file-name ".agent-workspace/crew.el" project))
          (text "(agent-workspace-crew
 :version 1
 :agents ((:name \"ada\" :role \"builder\" :colour \"blue\"))
 :layout (:selected \"ada\" :open t))
"))
      (make-directory (file-name-directory old) t)
      (write-region text nil old nil 'silent)
      (agent-workspace-open t)
      (should-not (agent-workspace-agents project))
      (agent-workspace-create :role "builder" :name "ken")
      (should (string-search "{\"name\": \"ken\"" (+test-aws2--file project)))
      (should-not (string-search "ada" (+test-aws2--file project)))
      (should (equal (directory-files (file-name-directory old) nil directory-files-no-dot-files-regexp)
                     '("crew.el")))
      (should (equal (with-temp-buffer (insert-file-contents old) (buffer-string)) text)))))
