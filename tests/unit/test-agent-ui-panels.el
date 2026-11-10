;;; tests/unit/test-agent-ui-panels.el -*- lexical-binding: t; -*-
;; config/agent-ui/panels.el: project panels, kept in a project's repository
;; (.agent-ui/panels/NAME.el): read without evaluating, checked.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defmacro +test-aup (panels &rest body)
  "BODY in a project of its own (`root', `default-directory' there) whose
panels are PANELS, ((NAME . TEXT) ...), their files written; removed after."
  (declare (indent 1))
  `(let* ((root (file-name-as-directory (make-temp-file "panels-" t)))
          (default-directory root))
     (unwind-protect
         (progn
           (make-directory (expand-file-name agent-ui-panel-directory root) t)
           (pcase-dolist (`(,name . ,text) ,panels)
             (with-temp-file (expand-file-name (concat name ".el") (expand-file-name agent-ui-panel-directory root))
               (insert text)))
           ,@body)
       (delete-directory root t))))

(defconst +test-aup-service
  ";;; service.el --- Agent UI panel -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type \"panel\" :id \"service\" :title \"Service\" :layout \"row\"
      :children ((:type \"table\" :id \"ci\" :title \"CI\" :columns (\"Run\" \"Status\"))
                 (:type \"gauge\" :id \"dirty\" :title \"Unsaved buffers\" :value 0 :max 20)))
 :every 30
 :fetch (lambda (panel) (ignore panel)))
"
  "A right panel.")

(defun +test-aup-panel (body)
  "A panel's file text: BODY in (agent-ui-panel ...), its :ui a text."
  (format ";;; -*- lexical-binding: t; -*-\n(agent-ui-panel\n :ui (:type \"text\" :id \"t\" :text \"x\")\n %s)\n" body))

(defun +test-aup-error (text)
  "The error reading a panel whose file is TEXT."
  (+test-aup `(("bad" . ,text))
    (agent-ui-error-message
     (should-error (agent-ui-panel-read (agent-ui-panel-file "bad")) :type 'agent-ui-error))))

;; ====== A PROJECT'S PANELS ======

(ert-deftest agent-ui-panels/a-project-s-panels ()
  "A project's panels by name, from anywhere in it; one not there: its
panels said (doom-3q5.1)."
  (+test-aup `(("service" . ,+test-aup-service) ("board" . ,+test-aup-service))
    (should (equal (agent-ui-panels) '("board" "service")))
    (let ((sub (expand-file-name "src/deep/" root)))
      (make-directory sub t)
      (should (equal (agent-ui-panel-root sub) root))
      (should (equal (agent-ui-panels sub) '("board" "service")))
      (should (equal (agent-ui-panel-file "service" sub)
                     (expand-file-name ".agent-ui/panels/service.el" root))))
    ;; A file, taken as it is.
    (should (equal (agent-ui-panel-file ".agent-ui/panels/board.el")
                   (expand-file-name ".agent-ui/panels/board.el" root)))
    (should (string-match-p "panel nope: not one of this project's: board, service"
                            (agent-ui-error-message
                             (should-error (agent-ui-panel-file "nope") :type 'agent-ui-error)))))
  ;; A folder with none.
  (let ((empty (file-name-as-directory (make-temp-file "no-panels-" t))))
    (unwind-protect
        (cl-letf (((symbol-function 'project-current) #'ignore))
          (should-not (agent-ui-panels empty))
          (should (string-match-p "no project here"
                                  (agent-ui-error-message
                                   (should-error (agent-ui-panel-file "x" empty) :type 'agent-ui-error)))))
      (delete-directory empty t))))

;; ====== READING ONE ======

(ert-deftest agent-ui-panels/read-not-evaluated ()
  "Its :ui is data, read as it is (evaluated, (:type ...) would fail), right
as show has it; its form evaluated later gives its script, :ui quoted."
  (+test-aup `(("service" . ,+test-aup-service))
    (let ((panel (agent-ui-panel-read (agent-ui-panel-file "service"))))
      (should (equal (plist-get panel :name) "service"))
      (should (equal (plist-get (plist-get panel :ui) :id) "service"))
      (should (equal (mapcar (lambda (c) (plist-get c :id)) (plist-get (plist-get panel :ui) :children))
                     '("ci" "dirty")))
      (should (equal (plist-get panel :every) 30))
      (should (eq (car (plist-get panel :form)) 'agent-ui-panel))
      ;; The macro: :ui quoted, the rest evaluated.
      (let ((script (eval (plist-get panel :form) t)))
        (should (equal (plist-get script :ui) (plist-get panel :ui)))
        (should (functionp (plist-get script :fetch)))
        (should (equal (plist-get script :version) 1)))))
  (should-error (macroexpand '(agent-ui-panel :ui (:type "text") :fetchh nil))))

(ert-deftest agent-ui-panels/wrong-files ()
  "Each wrong file said, where it's wrong."
  (should (string-match-p "holds one form, (agent-ui-panel :ui \\.\\.\\. :fetch \\.\\.\\.), not 2 forms"
                          (+test-aup-error "(agent-ui-panel :ui (:type \"text\" :text \"x\"))\n(setq x 1)\n")))
  (should (string-match-p "holds one form.*not (setq x 1)" (+test-aup-error "(setq x 1)\n")))
  (should (string-match-p "panel bad has \":fetchh\"?: a panel has version, ui, every, fetch, start, stop"
                          (+test-aup-error (+test-aup-panel ":fetchh nil"))))
  (should (string-match-p "panel bad is version 2: this Agent UI reads version 1"
                          (+test-aup-error (+test-aup-panel ":version 2"))))
  (should (string-match-p "every is how many seconds between fetches, a number above 0, not \"x\""
                          (+test-aup-error (+test-aup-panel ":every \"x\""))))
  (should (string-match-p "every is how many seconds" (+test-aup-error (+test-aup-panel ":every (* 5 60)"))))
  (should (string-match-p "its :ui: table: unknown property \"colums\""
                          (+test-aup-error "(agent-ui-panel :ui (:type \"table\" :id \"t\" :colums (\"a\")))\n")))
  (should (string-match-p "its :ui is what it shows, an element"
                          (+test-aup-error "(agent-ui-panel :every 5)\n")))
  (should (string-match-p "ends inside a form" (+test-aup-error "(agent-ui-panel :ui (:type \"text\"\n"))))

;; ====== CHECKING ONE ======

(ert-deftest agent-ui-panels/checked ()
  "Checked as the agent writes one, nothing run: read, compiled (its
warnings), its calls that wait found (not in comments or strings, nor
accept-process-output with a timeout)."
  (+test-aup `(("service" . ,+test-aup-service)
               ("slow" . ,(+test-aup-panel ":fetch (lambda (_panel)
   (shell-command-to-string \"ls\")
   ;; (call-process \"x\") in a comment
   (message \"(sleep-for 1) in a string\")
   (accept-process-output nil 0.1)
   (mapc #'call-process '(\"a\"))
   (accept-process-output nil))"))
               ("warned" . ,(+test-aup-panel ":fetch (lambda (_panel) (agent-ui-panel--no-such-function))"))
               ("broken" . ,(+test-aup-panel ":fetch (lambda (_panel) (cond 1))"))
               ("plain" . "(agent-ui-panel :ui (:type \"text\" :id \"t\" :text \"x\"))\n"))
    (let ((reply (agent-ui-panel-check (agent-ui-panel-file "service"))))
      (should (equal (plist-get reply :panel) "service"))
      (should (equal (plist-get reply :type) "panel"))
      (should (equal (plist-get reply :every) 30))
      (should (equal (plist-get reply :warnings) []))
      (should (equal (plist-get reply :blocking) [])))
    (should (equal (plist-get (agent-ui-panel-check (agent-ui-panel-file "slow")) :blocking)
                   ["line 5: shell-command-to-string waits, Emacs frozen meanwhile: use agent-ui-panel-run"
                    "line 9: call-process waits, Emacs frozen meanwhile: use agent-ui-panel-run"
                    "line 10: accept-process-output waits, Emacs frozen meanwhile: use agent-ui-panel-run"]))
    (should (seq-some (lambda (w) (string-match-p "agent-ui-panel--no-such-function.*not known to be defined" w))
                      (plist-get (agent-ui-panel-check (agent-ui-panel-file "warned")) :warnings)))
    (should (string-match-p "panel broken: it doesn't compile"
                            (agent-ui-error-message
                             (should-error (agent-ui-panel-check (agent-ui-panel-file "broken"))
                                           :type 'agent-ui-error))))
    (should (string-match-p "no -\\*- lexical-binding"
                            (aref (plist-get (agent-ui-panel-check (agent-ui-panel-file "plain")) :warnings) 0)))))

(ert-deftest agent-ui-panels/checked-as-asked ()
  "agent-ui check NAME, in the agent's directory: the reply; no name, the
project's panels said."
  (+test-aup `(("service" . ,+test-aup-service))
    (should (member "check" agent-ui-operations))
    (let ((agent-ui--request-cwd root))
      (should (equal (plist-get (agent-ui-do "check" "service" nil nil) :panel) "service"))
      (should (string-match-p "check: which panel\\? agent-ui check NAME (this project's: service)"
                              (agent-ui-error-message
                               (should-error (agent-ui-do "check" nil nil nil) :type 'agent-ui-error)))))))

;; ====== OPENING ONE ======

(ert-deftest agent-ui-panels/opened-on-demand ()
  "Opened: its :ui drawn as it is in a canvas of its own (named after it
and its project, no session's, its directory the project's), in its pane,
selected; opened again: the same; closed, opened again anew (doom-3q5.2)."
  (+test-aup `(("service" . ,+test-aup-service))
    (save-window-excursion
      (delete-other-windows)
      (let* ((canvas (agent-ui-open-panel "service"))
             (project (file-name-nondirectory (directory-file-name root))))
        (unwind-protect
            (progn
              (should (equal (buffer-name canvas) (format "Agent UI: service (%s)" project)))
              (should (eq (window-buffer (selected-window)) canvas))
              (with-current-buffer canvas
                (should (equal default-directory root))
                (should-not agent-ui--session-buffer)
                (should (equal (agent-ui-panel--name agent-ui-panel--state) "service"))
                (should (equal (agent-ui-panel--root agent-ui-panel--state) root)))
              (should (equal (buffer-local-value 'agent-ui--order canvas) '("service")))
              (should (equal (plist-get (agent-ui-get "ci" :canvas canvas) :columns) '("Run" "Status")))
              ;; Open already: its pane, the same canvas.
              (select-window (split-window))
              (switch-to-buffer "*scratch*")
              (should (eq (agent-ui-open-panel "service" root) canvas))
              (should (eq (window-buffer (selected-window)) canvas))
              (should (equal (buffer-local-value 'agent-ui--order canvas) '("service")))
              ;; Closed, opened again: anew.
              (agent-ui-update "ci" '(:rows (("#1" "passed"))) :canvas canvas)
              (kill-buffer canvas)
              (setq canvas (agent-ui-open-panel "service" root))
              (should-not (plist-get (agent-ui-get "ci" :canvas canvas) :rows)))
          (when (buffer-live-p canvas) (kill-buffer canvas)))))))

(ert-deftest agent-ui-panels/a-wrong-one-opens-nothing ()
  "A wrong panel: said, no canvas left behind; none picked from a project
with none."
  (+test-aup '(("bad" . "(agent-ui-panel :ui (:type \"table\" :id \"t\" :colums (\"a\")))\n"))
    (let ((before (agent-ui-canvases)))
      (should-error (agent-ui-open-panel "bad") :type 'agent-ui-error)
      (should (equal (agent-ui-canvases) before))))
  (let ((empty (file-name-as-directory (make-temp-file "no-panels-" t))))
    (unwind-protect
        (cl-letf (((symbol-function 'project-current) #'ignore))
          (let ((default-directory empty))
            (should (string-match-p "No project here"
                                    (cadr (should-error (agent-ui-panel--read-name) :type 'user-error))))))
      (delete-directory empty t))))

(ert-deftest agent-ui-panels/its-key ()
  "SPC o u: one of the project's panels, opened."
  (should (eq (lookup-key doom-leader-map "ou") #'agent-ui-open-panel)))
