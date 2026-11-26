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
          (default-directory root)
          ;; Its code let run (asking: see the tests that ask).
          (agent-ui-panel-allow-function (lambda (_panel) t)))
     (unwind-protect
         (progn
           (make-directory (expand-file-name agent-ui-panel-directory root) t)
           (pcase-dolist (`(,name . ,text) ,panels)
             (with-temp-file (expand-file-name (concat name ".el") (expand-file-name agent-ui-panel-directory root))
               (insert text)))
           ,@body)
       (delete-directory root t))))

(defun +test-aup-fixture (name)
  "The text of test panel NAME, tests/fixtures/agent-ui-panels/NAME.el."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format "fixtures/agent-ui-panels/%s.el" name) +test-dir))
    (buffer-string)))

(defvar +test-aup-calls nil "What a test panel's script did, the latest first.")

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
  (should (string-match-p "ends inside a form" (+test-aup-error "(agent-ui-panel :ui (:type \"text\"\n")))
  ;; A comment after its form: a comment.
  (+test-aup '(("commented" . "(agent-ui-panel :ui (:type \"text\" :text \"x\"))\n;; the end\n"))
    (should (agent-ui-panel-read (agent-ui-panel-file "commented")))))

;; ====== CHECKING ONE ======

(ert-deftest agent-ui-panels/checked ()
  "Checked as the agent writes one, nothing run: read, compiled (its code
trusted; its warnings), its calls that wait found (not in comments or strings, nor
accept-process-output with a timeout)."
  (+test-aup `(("service" . ,+test-aup-service)
               ("slow" . ,(+test-aup-panel ":fetch (lambda (_panel)
   (shell-command-to-string \"ls\")
   ;; (call-process \"x\") in a comment
   (message \"(sleep-for 1) in a string\")
   (accept-process-output nil 0.1)
   (mapc #'call-process '(\"a\"))
   (accept-process-output nil))"))
               ("warned" . ,(+test-aup-panel ":fetch (lambda (_panel) (agent-ui-panels--no-such-function))"))
               ("broken" . ,(+test-aup-panel ":fetch (lambda (_panel) (cond 1))"))
               ("plain" . "(agent-ui-panel :ui (:type \"text\" :id \"t\" :text \"x\"))\n"))
    (cl-letf (((symbol-function 'agent-ui-panel-trusted-p) (lambda (_file) t)))
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
      (should (seq-some (lambda (w) (string-match-p "agent-ui-panels--no-such-function.*not known to be defined" w))
                        (plist-get (agent-ui-panel-check (agent-ui-panel-file "warned")) :warnings)))
      (should (string-match-p "panel broken: it doesn't compile"
                              (agent-ui-error-message
                               (should-error (agent-ui-panel-check (agent-ui-panel-file "broken"))
                                             :type 'agent-ui-error))))
      (should (string-match-p "no -\\*- lexical-binding"
                              (aref (plist-get (agent-ui-panel-check (agent-ui-panel-file "plain")) :warnings) 0))))))

(ert-deftest agent-ui-panels/not-compiled-untrusted ()
  "A panel whose code isn't trusted: not compiled (its macros and
eval-when-compile would run), said; read and its waiting calls found all
the same (doom-ht6.42)."
  (let ((marker (+test-tmp-file (format "ran-at-check-%d" (random 100000)))))
    (+test-aup `(("evil" . ,(+test-aup-panel
                             (format ":fetch (lambda (_panel) (eval-when-compile (write-region \"ran\" nil %S)) (sleep-for 1))"
                                     marker))))
      (let ((reply (agent-ui-panel-check (agent-ui-panel-file "evil"))))
        (should-not (file-exists-p marker))
        (should (equal (plist-get reply :panel) "evil"))
        (should (string-match-p "isn't trusted yet" (plist-get reply :not-compiled)))
        (should (equal (plist-get reply :warnings) []))
        (should (= (length (plist-get reply :blocking)) 1))))))

(ert-deftest agent-ui-panels/saved-with-a-title-of-two-lines ()
  "A panel saved from an element whose title has a new line: its file read
as one form, the title on its header's line (doom-ht6.73)."
  (+test-aup nil
    (let ((file (expand-file-name "ci.el" (expand-file-name agent-ui-panel-directory root))))
      (with-temp-file file
        (insert (agent-ui-panels--file-text "ci" '(:type "text" :id "t" :title "CI\n(status of main)" :text "x"))))
      (should (equal (plist-get (plist-get (agent-ui-panel-read file) :ui) :title) "CI\n(status of main)"))
      (should (string-prefix-p ";;; ci.el --- Agent UI panel: CI (status of main) -*-"
                               (with-temp-buffer (insert-file-contents file) (buffer-string)))))))

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
                (should (equal (agent-ui-panels--name agent-ui-panels--state) "service"))
                (should (equal (agent-ui-panels--root agent-ui-panels--state) root)))
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

(ert-deftest agent-ui-panels/its-name-on-its-tab-its-title-in-its-border ()
  "A project panel's canvas goes by the panel's name: its tab says Agent UI:
NAME (its title a sentence long made its tab as long), its lone panel's
title drawn in the panel's top border, not over it; its view's bar (under a
session) its name too. A second element: its title over it again, the tab
still its name. A lone panel without a border: its title over it."
  (+test-aup `(("service" . ,+test-aup-service))
    (save-window-excursion
      (delete-other-windows)
      (let* ((canvas (agent-ui-open-panel "service"))
             (text (lambda ()
                     (with-current-buffer canvas
                       (agent-ui--flush)
                       (buffer-substring-no-properties (point-min) (point-max))))))
        (unwind-protect
            (progn
              (should (equal (buffer-local-value 'agent-ui-canvas-name canvas) "service"))
              (should (equal (agent-ui-canvas-label canvas) "Agent UI: service"))
              (should-not (agent-ui-canvas-title canvas))
              (should (string-match-p "^╭─ Service ─+╮$" (funcall text)))
              (should-not (string-match-p "^Service$" (funcall text)))
              (should (equal (agent-ui-pane-view-name canvas) "service"))
              ;; A second element: its title over it, a plain border.
              (agent-ui-show '(:id "note" :type "text" :text "a note") :canvas canvas)
              (should (string-match-p "^Service\n╭─+╮$" (funcall text)))
              (should (equal (agent-ui-canvas-label canvas) "Agent UI: service"))
              (agent-ui-remove "note" :canvas canvas)
              (should (string-match-p "^╭─ Service ─+╮$" (funcall text)))
              ;; Without a border: its title over it.
              (agent-ui-update "service" '(:border :false) :canvas canvas)
              (should (string-match-p "^Service$" (funcall text)))
              (should-not (string-search "╭─ Service" (funcall text))))
          (when (buffer-live-p canvas) (kill-buffer canvas)))))))

(ert-deftest agent-ui-panels/picked-from-rows ()
  "SPC o u's list, as the agent workspace's role picker: a row per panel,
in columns lined up (its icon, its name, its title, how often it's
fetched, open), under the project and its panels' folder, by name; fitted
to the width (its title cut with …, none without room). One whose file
can't be read: its error, dimmed."
  (+test-aup `(("service" . ,+test-aup-service)
               ("bad" . "(agent-ui-panel :ui 1)")
               ("cpu-and-memory" . ";;; -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type \"panel\" :id \"p\" :title \"A title long enough to be cut somewhere\"
      :children ((:type \"text\" :id \"t\" :text \"x\")))
 :every 120)
"))
    (save-window-excursion
      (let ((canvas (agent-ui-open-panel "service"))
            seen)
        (unwind-protect
            (progn
              (cl-letf (((symbol-function 'completing-read)
                         (lambda (prompt collection &rest _)
                           (setq seen (list prompt collection completion-extra-properties))
                           "service")))
                (should (equal (agent-ui-panels--read-name) "service")))
              (pcase-let* ((`(,prompt ,names ,props) seen)
                           (rows (funcall (plist-get props :affixation-function) names))
                           (line (lambda (name)
                                   (pcase-let ((`(,candidate ,_ ,suffix) (nth (seq-position names name) rows)))
                                     (substring-no-properties (concat candidate suffix))))))
                (should (equal prompt "Panel: "))
                (should (equal names '("bad" "cpu-and-memory" "service")))
                (should (equal (funcall (plist-get props :group-function) "service" nil)
                               (concat (file-name-nondirectory (directory-file-name root)) " · .agent-ui/panels")))
                (should (equal (funcall (plist-get props :group-function) "service" t) "service"))
                (should (eq (plist-get props :display-sort-function) #'identity))
                ;; Its icon, two columns.
                (should (= (string-width (nth 1 (car rows))) 2))
                ;; Lined up: each column where the others' is.
                (should (string-match-p "\\`service +Service +every 30 s +open\\'" (funcall line "service")))
                (should (string-match-p "\\`cpu-and-memory +A title long enough to be cut somewhere +every 2 min\\'"
                                        (funcall line "cpu-and-memory")))
                (should (= (string-search "every" (funcall line "service"))
                           (string-search "every" (funcall line "cpu-and-memory"))))
                (should (= (string-search "Service" (funcall line "service"))
                           (string-search "A title" (funcall line "cpu-and-memory"))))
                (should (eq (get-text-property 0 'face (nth 2 (nth 2 rows))) nil))
                ;; Can't be read: its error, dimmed, the name too.
                (pcase-let ((`(,candidate ,_ ,suffix) (car rows)))
                  (should (string-search "its :ui is what it shows" suffix))
                  (should (memq 'agent-ui-muted (ensure-list (get-text-property 0 'face candidate))))
                  (should (memq 'agent-ui-muted (ensure-list (get-text-property (1- (length suffix)) 'face suffix)))))))
          (when (buffer-live-p canvas) (kill-buffer canvas)))))
    ;; Narrower: the title cut with …; no room: none.
    (let* ((facts (agent-ui-panels--picker-facts root '("cpu-and-memory" "service")))
           (suffix (lambda (width) (substring-no-properties (nth 3 (car (agent-ui-panels--picker-rows facts width)))))))
      (should (string-search "A title long enoug…" (funcall suffix 50)))
      (should (string-search "every 2 min" (funcall suffix 50)))
      (should-not (string-search "A title" (funcall suffix 30)))
      (should (string-search "every 2 min" (funcall suffix 30))))))

(ert-deftest agent-ui-panels/how-often-said ()
  (should (equal (agent-ui-panels--every-text nil) ""))
  (should (equal (agent-ui-panels--every-text 1) "every 1 s"))
  (should (equal (agent-ui-panels--every-text 0.5) "every 0.5 s"))
  (should (equal (agent-ui-panels--every-text 120) "every 2 min"))
  (should (equal (agent-ui-panels--every-text 90) "every 1.5 min"))
  (should (equal (agent-ui-panels--every-text 7200) "every 2 h")))

(ert-deftest agent-ui-panels/a-hook-as-one-opens ()
  "`agent-ui-panel-open-hook' runs in a panel's canvas once it has opened,
not when it's only shown again."
  (+test-aup `(("service" . ,+test-aup-service))
    (save-window-excursion
      (let* ((ran nil)
             (agent-ui-panel-open-hook (list (lambda () (push (current-buffer) ran))))
             (canvas (agent-ui-open-panel "service")))
        (unwind-protect
            (progn
              (should (equal ran (list canvas)))
              (agent-ui-open-panel "service" root)
              (should (equal ran (list canvas))))
          (kill-buffer canvas))))))

(ert-deftest agent-ui-panels/its-notice-offers-a-pdf ()
  "Each panel opened shows a notice offering its PDF (config/banner.el),
Export PDF its button; SPC m e in it does the same."
  (should (memq '+my/agent-ui-panel-pdf-notice agent-ui-panel-open-hook))
  (let ((shown nil))
    (cl-letf (((symbol-function '+my/banner-show) (lambda (&rest args) (setq shown args))))
      (+my/agent-ui-panel-pdf-notice))
    (should (eq (car shown) 'agent-ui-panel-pdf))
    (should (string-match-p "Export this panel as a PDF" (cadr shown)))
    (should (equal (plist-get (cddr shown) :actions) '(("Export PDF" . agent-ui-export-pdf)))))
  (should (eq (lookup-key (evil-get-auxiliary-keymap agent-ui-canvas-mode-map 'normal) (kbd "SPC m e"))
              #'agent-ui-export-pdf)))

(ert-deftest agent-ui-panels/exported-as-a-pdf ()
  "A panel as it shows now: an SVG of its elements (no buttons) made a PDF by
rsvg-convert, beside its file, NAME-DATE-TIME.pdf (another in the same
second: -2); the SVG gone after; said where."
  (+test-aup `(("service" . ,+test-aup-service))
    (save-window-excursion
      (let ((canvas (agent-ui-open-panel "service"))
            (calls nil) (svg-text nil))
        (unwind-protect
            (cl-letf (((symbol-function 'call-process)
                       (lambda (program _in _out _display &rest args)
                         (push (cons program args) calls)
                         (setq svg-text (with-temp-buffer (insert-file-contents (car (last args))) (buffer-string)))
                         (with-temp-file (nth 3 args) (insert "%PDF-1.5"))
                         0))
                      ((symbol-function 'executable-find) (lambda (name &rest _) (concat "/bin/" name))))
              (agent-ui-update "ci" '(:rows (("#1" "passed"))) :canvas canvas)
              (+test-clear-messages)
              (let ((pdf (with-current-buffer canvas (agent-ui-export-pdf))))
                (should (string-match-p (concat "\\`" (regexp-quote (expand-file-name agent-ui-panel-directory root))
                                                "service-[0-9]\\{8\\}-[0-9]\\{6\\}\\.pdf\\'")
                                        pdf))
                (should (file-exists-p pdf))
                (should (equal (butlast (car calls)) (list "rsvg-convert" "-f" "pdf" "-o" pdf)))
                (should-not (file-exists-p (car (last (car calls)))))
                ;; Its elements as they show now.
                (should (string-prefix-p "<svg " svg-text))
                (dolist (text '("Service" "CI" "#1" "passed"))
                  (should (string-search (format ">%s<" text) svg-text)))
                (should (= (+test-messages "Panel service exported: .*service-.*\\.pdf") 1))
                ;; Another in the same second: beside it.
                (cl-letf (((symbol-function 'format-time-string) (lambda (&rest _) (substring (file-name-base pdf) 8))))
                  (should (equal (agent-ui-panel-pdf-file (buffer-local-value 'agent-ui-panels--state canvas))
                                 (concat (file-name-sans-extension pdf) "-2.pdf"))))))
          (kill-buffer canvas))))))

(ert-deftest agent-ui-panels/a-real-pdf ()
  "rsvg-convert makes a real PDF of it (skipped without it)."
  (skip-unless (executable-find "rsvg-convert"))
  (+test-aup `(("service" . ,+test-aup-service))
    (save-window-excursion
      (let ((canvas (agent-ui-open-panel "service")))
        (unwind-protect
            (let ((pdf (with-current-buffer canvas (agent-ui-export-pdf))))
              (should (equal (with-temp-buffer
                               (set-buffer-multibyte nil)
                               (insert-file-contents-literally pdf nil 0 5)
                               (buffer-string))
                             "%PDF-")))
          (kill-buffer canvas))))))

(ert-deftest agent-ui-panels/a-pdf-only-of-a-canvas ()
  "Not a canvas, or rsvg-convert missing: said, nothing made."
  (with-temp-buffer
    (should (string-match-p "Not an Agent UI canvas"
                            (cadr (should-error (agent-ui-export-pdf) :type 'user-error)))))
  (+test-aup `(("service" . ,+test-aup-service))
    (save-window-excursion
      (let ((canvas (agent-ui-open-panel "service"))
            (agent-ui-pdf-program "no-such-rsvg-convert"))
        (unwind-protect
            (with-current-buffer canvas
              (should (string-match-p "needs no-such-rsvg-convert"
                                      (cadr (should-error (agent-ui-export-pdf) :type 'user-error))))
              (should-not (directory-files (expand-file-name agent-ui-panel-directory root) nil "\\.pdf\\'")))
          (kill-buffer canvas))))))

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
                                    (cadr (should-error (agent-ui-panels--read-name) :type 'user-error))))))
      (delete-directory empty t))))

(ert-deftest agent-ui-panels/its-key ()
  "SPC o u: one of the project's panels, opened in a pane of its own; SPC o
U: in the window you're in."
  (should (eq (lookup-key doom-leader-map "ou") #'agent-ui-open-panel))
  (should (eq (lookup-key doom-leader-map "oU") #'agent-ui-open-panel-here)))

(ert-deftest agent-ui-panels/opened-here ()
  "Opened here: in the selected window, no other; open already, shown here
too."
  (+test-aup `(("service" . ,+test-aup-service))
    (save-window-excursion
      (delete-other-windows)
      (switch-to-buffer "*scratch*")
      (let* ((window (selected-window))
             (canvas (agent-ui-open-panel-here "service" root)))
        (unwind-protect
            (progn
              (should (eq (window-buffer window) canvas))
              (should (eq (selected-window) window))
              (should (= (length (window-list)) 1))
              ;; Open already, in another window: shown here too.
              (select-window (split-window))
              (switch-to-buffer "*scratch*")
              (should (eq (agent-ui-open-panel-here "service" root) canvas))
              (should (eq (window-buffer (selected-window)) canvas)))
          (kill-buffer canvas))))))

;; ====== ITS SCRIPT ======

(ert-deftest agent-ui-panels/filled-by-its-script ()
  "Its code let run: :start, :fetch at once and every :every seconds (in its
root), filling it (agent-ui-panel-update, -append, -run: a command's JSON
parsed); closed, :stop, nothing more fetched (doom-3q5.3)."
  (+test-aup `(("live" . ,(+test-aup-fixture "live")))
    (setq +test-aup-calls nil)
    (save-window-excursion
     (let* ((asked 0)
           (agent-ui-panel-allow-function (lambda (_panel) (cl-incf asked) t))
           (canvas (agent-ui-open-panel "live")))
      (unwind-protect
          (progn
            (should (= asked 1))
            (should (+test-wait-for (lambda () (plist-get (agent-ui-get "runs" :canvas canvas) :rows)) 5))
            (should (equal (plist-get (agent-ui-get "runs" :canvas canvas) :rows)
                           '(("#812" "passed") ("#811" "failed"))))
            (should (equal (plist-get (agent-ui-get "where" :canvas canvas) :text) root))
            (should (plist-get (agent-ui-get "errors" :canvas canvas) :values))
            (should (equal (car (last +test-aup-calls)) 'start))
            ;; Again, every :every seconds.
            (should (+test-wait-for (lambda () (>= (cl-count 'fetch +test-aup-calls) 3)) 5))
            (should-not (agent-ui-panels--error (buffer-local-value 'agent-ui-panels--state canvas))))
        (kill-buffer canvas))
      (should (eq (car +test-aup-calls) 'stop))
      (let ((fetches (cl-count 'fetch +test-aup-calls)))
        (+test-sleep 0.5)
        (should (= (cl-count 'fetch +test-aup-calls) fetches)))))))

(ert-deftest agent-ui-panels/its-failures-said ()
  "A command failing (its exit and what it said), a change of an element it
hasn't: the panel's error, said; the callback not called."
  (+test-aup `(("failing-run" . ,(+test-aup-fixture "failing-run"))
               ("failing-update" . ,(+test-aup-fixture "failing-update")))
    (setq +test-aup-calls nil)
    (let ((canvas (save-window-excursion (agent-ui-open-panel "failing-run"))))
      (unwind-protect
          (let ((panel (buffer-local-value 'agent-ui-panels--state canvas)))
            (should (+test-wait-for (lambda () (agent-ui-panels--error panel)) 5))
            (should (equal (agent-ui-panels--error panel) "sh: exit 3: boom"))
            (should-not +test-aup-calls)
            (should (+test-messages "Agent UI: panel failing-run: sh: exit 3: boom")))
        (kill-buffer canvas)))
    (let ((canvas (save-window-excursion (agent-ui-open-panel "failing-update"))))
      (unwind-protect
          (should (string-match-p "\\`fetch: .*nope"
                                  (agent-ui-panels--error (buffer-local-value 'agent-ui-panels--state canvas))))
        (kill-buffer canvas)))))

(ert-deftest agent-ui-panels/its-commands-killed-on-close ()
  (+test-aup `(("slow" . ,(+test-aup-fixture "slow")))
    (let* ((canvas (save-window-excursion (agent-ui-open-panel "slow")))
           (process (car (agent-ui-panels--processes (buffer-local-value 'agent-ui-panels--state canvas)))))
      (should (process-live-p process))
      (kill-buffer canvas)
      (should-not (process-live-p process)))))

(ert-deftest agent-ui-panels/its-code-run-only-if-let ()
  "Its code (its script, its elements' sources) runs only if let: refused,
its :ui drawn without its sources, its script not evaluated, said; a panel
with no code: not asked."
  (+test-aup `(("sourced" . ,(+test-aup-fixture "sourced")) ("plain" . "(agent-ui-panel :ui (:type \"text\" :id \"t\" :text \"x\"))\n"))
    (setq +test-aup-calls nil)
    (let* ((asked nil)
           (agent-ui-panel-allow-function (lambda (panel) (push (agent-ui-panels--name panel) asked) nil))
           (canvas (save-window-excursion (agent-ui-open-panel "sourced"))))
      (unwind-protect
          (progn
            (should (equal asked '("sourced")))
            (should-not (agent-ui-source-status "log" :canvas canvas))
            (should-not (plist-get (agent-ui-get "log" :canvas canvas) :source))
            (should-not (agent-ui-panels--script (buffer-local-value 'agent-ui-panels--state canvas)))
            (should-not +test-aup-calls)
            (should (equal (agent-ui-panels--error (buffer-local-value 'agent-ui-panels--state canvas))
                           "its code: not run, not let: gR asks again")))
        (kill-buffer canvas))
      (let ((canvas (save-window-excursion (agent-ui-open-panel "plain"))))
        (should (equal asked '("sourced")))
        (kill-buffer canvas)))
    ;; Let: its sources run too.
    (let ((canvas (save-window-excursion (agent-ui-open-panel "sourced"))))
      (unwind-protect
          (progn
            (should (agent-ui-source-status "log" :canvas canvas))
            (should (memq 'fetch +test-aup-calls)))
        (kill-buffer canvas)))))

(ert-deftest agent-ui-panels/closed-before-its-code-starts ()
  "Opened without being selected (its code started a moment later, as an
agent opens one) and closed before: its code neither asked about nor run.
It was asked about, closed (in batch, from stdin: the agent workspace's
tests hit it, doom-b5u). Open then, it starts as ever."
  (+test-aup `(("sourced" . ,(+test-aup-fixture "sourced")))
    (setq +test-aup-calls nil)
    (let* ((asked nil)
           (agent-ui-panel-allow-function (lambda (panel) (push (agent-ui-panels--name panel) asked) t))
           (canvas (save-window-excursion (agent-ui-open-panel "sourced" nil t))))
      (should-not asked)
      (kill-buffer canvas)
      (+test-sleep 0.05)
      (should-not asked)
      (should-not +test-aup-calls)
      (setq canvas (save-window-excursion (agent-ui-open-panel "sourced" nil t)))
      (unwind-protect
          (progn
            (+test-sleep 0.05)
            (should (equal asked '("sourced")))
            ;; Its script evaluated (fetched once shown: hidden here).
            (should (agent-ui-panels--script (buffer-local-value 'agent-ui-panels--state canvas))))
        (kill-buffer canvas)))))

(ert-deftest agent-ui-panels/the-panel-type-s-functions-its-own ()
  "No function of the panel element's (elements/panel.el) redefined by
another file loaded after it (the project panels' code once took
agent-ui-panel--draw)."
  (let ((file (seq-find (lambda (entry) (and (stringp (car entry))
                                             (string-match-p "agent-ui/elements/panel\\.elc?\\'" (car entry))))
                        load-history)))
    (should file)
    (dolist (item (cdr file))
      (when (eq (car-safe item) 'defun)
        (should (string-match-p "agent-ui/elements/panel\\.elc?\\'" (or (symbol-file (cdr item) 'defun) "")))))))

;; ====== ITS LIFE ======

(defmacro +test-aup-open (name &rest body)
  "BODY with test panel NAME (its fixture) open and shown (`canvas', `panel'),
in a project of its own; closed after."
  (declare (indent 1))
  `(+test-aup (list (cons ,name (+test-aup-fixture ,name)))
     (setq +test-aup-calls nil)
     (save-window-excursion
       (delete-other-windows)
       (let* ((canvas (agent-ui-open-panel ,name))
              (panel (buffer-local-value 'agent-ui-panels--state canvas)))
         (unwind-protect (progn ,@body)
           (when (buffer-live-p canvas) (kill-buffer canvas)))))))

(defun +test-aup-status (canvas)
  "The line under CANVAS's panel saying what went wrong, or nil."
  (and (member agent-ui-panels--status-id (buffer-local-value 'agent-ui--order canvas))
       (plist-get (agent-ui-get agent-ui-panels--status-id :canvas canvas) :text)))

(ert-deftest agent-ui-panels/paused-while-hidden ()
  "Hidden, no fetch (one missed, noted); shown again, one at once
\(doom-3q5.4)."
  (+test-aup-open "counted"
    (should (+test-wait-for (lambda () (>= (cl-count 'fetch +test-aup-calls) 2)) 3))
    (switch-to-buffer "*scratch*")
    (+test-sleep 0.15)
    (let ((fetches (cl-count 'fetch +test-aup-calls)))
      (+test-sleep 0.5)
      (should (= (cl-count 'fetch +test-aup-calls) fetches))
      (should (agent-ui-panels--stale panel))
      ;; Shown again (its window-buffer-change-functions, which batch Emacs's
      ;; missing redisplay doesn't run): fetched at once.
      (switch-to-buffer canvas)
      (agent-ui-panels--shown (selected-window))
      (should (+test-wait-for (lambda () (> (cl-count 'fetch +test-aup-calls) fetches)) 1))
      (should-not (agent-ui-panels--stale panel)))
    (should (memq #'agent-ui-panels--shown (buffer-local-value 'window-buffer-change-functions canvas)))))

(ert-deftest agent-ui-panels/read-by-an-agent-while-hidden ()
  "Hidden, read by an agent (agent-ui get): fetched then if its data is
older than its :every, its reply saying it's fetching until its query ends;
not fetched twice meanwhile, nor again while its data is fresh."
  (+test-aup-open "read"
    (should (+test-wait-for (lambda () (memq 'done +test-aup-calls)) 3))
    (switch-to-buffer "*scratch*")
    (setq +test-aup-calls nil)
    ;; Fresh (fetched under a second ago): read as it is.
    (should-not (agent-ui-panel-read-fetch panel))
    (should-not +test-aup-calls)
    (+test-sleep 1.1)
    ;; Old: fetched now, its query running.
    (let ((reply (agent-ui-do "get" nil nil canvas)))
      (should (eq (plist-get reply :fetching) t))
      (should (equal (plist-get reply :panel) "read"))
      (should (< (plist-get reply :fetched) 1)))
    (should (equal +test-aup-calls '(fetch)))
    (agent-ui-panel-read-fetch panel)
    (should (equal +test-aup-calls '(fetch)))
    (should (+test-wait-for (lambda () (not (agent-ui-panel-read-fetch panel))) 3))
    (let ((reply (agent-ui-do "get" "t" nil canvas)))
      (should (eq (plist-get reply :fetching) :false))
      (should (equal (plist-get (aref (plist-get reply :elements) 0) :text) "42")))))

(ert-deftest agent-ui-panels/read-fresh-from-when-its-queries-end ()
  "Hidden, read by an agent: its data's age counts from when its queries
ended. A query longer than its :every (1 s) had its data old as it came,
each read fetching again: the agent never answered (doom-ht6.95: its query
slow under a full test run's load)."
  (+test-aup-open "read"
    (should (+test-wait-for (lambda () (memq 'done +test-aup-calls)) 3))
    (switch-to-buffer "*scratch*")
    (should (>= (agent-ui-panels--settled panel) (agent-ui-panels--fetched panel)))
    (setq +test-aup-calls nil)
    ;; Fetched 10 s ago, its query ended just now: fresh.
    (setf (agent-ui-panels--fetched panel) (- (float-time) 10)
          (agent-ui-panels--settled panel) (- (float-time) 0.1))
    (should-not (agent-ui-panel-read-fetch panel))
    (should-not +test-aup-calls)
    ;; Ended 2 s ago: old, fetched.
    (setf (agent-ui-panels--settled panel) (- (float-time) 2))
    (should (agent-ui-panel-read-fetch panel))
    (should (equal +test-aup-calls '(fetch)))))

(ert-deftest agent-ui-panels/a-query-not-started-twice ()
  "Every 0.1 s, its command 0.6 s: not started again while it runs; the
fetch goes on."
  (+test-aup-open "waiting"
    (+test-sleep 0.45)
    (should (>= (cl-count 'fetch +test-aup-calls) 3))
    (should (= (length (agent-ui-panels--processes panel)) 1))
    (should (+test-wait-for (lambda () (memq 'done +test-aup-calls)) 3))))

(defun +test-aup-title (canvas id)
  (plist-get (agent-ui-get id :canvas canvas) :title))

(ert-deftest agent-ui-panels/its-queries-each-their-own ()
  "A slow query (1.5 s) doesn't hold a fast one's refreshes (every 0.1 s):
the fast one refreshed meanwhile, Emacs's timers running; the slow
element's title says it's loading and for how long, its data kept while it
loads again, its title as it was once it's done (doom-hgl)."
  (+test-aup-open "independent"
    (should (+test-wait-for (lambda () (>= (cl-count 'fast +test-aup-calls) 5)) 1.2))
    (should-not (memq 'slow +test-aup-calls))
    (should (string-match-p "\\`Slow  ⟳ loading, [0-9]" (+test-aup-title canvas "slow")))
    (should (equal (+test-aup-title canvas "fast") "Fast"))
    ;; How long, said as it goes.
    (let ((first (+test-aup-title canvas "slow")))
      (should (+test-wait-for (lambda () (not (equal (+test-aup-title canvas "slow") first))) 2)))
    (should (+test-wait-for (lambda () (memq 'slow +test-aup-calls)) 3))
    (should (equal (plist-get (agent-ui-get "slow" :canvas canvas) :text) "slow done"))
    ;; Loading again (said once it's taken a moment): its data kept meanwhile.
    (should (+test-wait-for (lambda () (string-match-p "⟳" (or (+test-aup-title canvas "slow") ""))) 2))
    (should (equal (plist-get (agent-ui-get "slow" :canvas canvas) :text) "slow done"))
    (should-not (+test-aup-status canvas))))

(ert-deftest agent-ui-panels/a-quick-refresh-says-no-loading ()
  "A query's first run, its element empty: its title says it's loading at
once. Refreshing it (its data shown): only once it's taken
`agent-ui-panel-loading-delay', its data kept meanwhile; a quick refresh,
never: its title didn't flicker \"⟳ loading, 0s\" at each one (doom-ht6.32)."
  (should (= (default-value 'agent-ui-panel-loading-delay) 0.5))
  (+test-aup-open "refreshed"
    (should (string-match-p "\\`Orders  ⟳ loading, 0s\\'" (+test-aup-title canvas "t")))
    (should (+test-wait-for (lambda () (memq 'done +test-aup-calls)) 3))
    (should (+test-wait-for (lambda () (equal (+test-aup-title canvas "t") "Orders")) 1))
    ;; Quicker than the delay (a long one here: a busy machine runs even a
    ;; quick query slowly): its title as it was, all along.
    (let ((agent-ui-panel-loading-delay 4)
          (titles nil))
      (agent-ui-panels--fetch panel)
      (should (gethash "t" (agent-ui-panels--running panel)))
      (should (+test-wait-for (lambda ()
                                (push (+test-aup-title canvas "t") titles)
                                (= (cl-count 'done +test-aup-calls) 2))
                              3))
      (push (+test-aup-title canvas "t") titles)
      (should (equal (delete-dups titles) '("Orders"))))
    ;; Slow (2 s): said once it's taken a moment, its data kept.
    (with-temp-file (expand-file-name "slow" root))
    (let ((start (float-time)))
      (agent-ui-panels--fetch panel)
      (should (equal (+test-aup-title canvas "t") "Orders"))
      (should (+test-wait-for (lambda () (string-match-p "⟳ loading" (+test-aup-title canvas "t"))) 3))
      (should (>= (- (float-time) start) agent-ui-panel-loading-delay))
      (should (equal (plist-get (agent-ui-get "t" :canvas canvas) :text) "orders")))
    (should (+test-wait-for (lambda () (equal (+test-aup-title canvas "t") "Orders")) 5))
    (should (= (cl-count 'done +test-aup-calls) 3))))

(ert-deftest agent-ui-panels/a-query-timed-out ()
  "TIMEOUT: killed after it, said on its element."
  (+test-aup-open "timeout"
    (should (+test-wait-for (lambda () (string-match-p "⚠" (or (+test-aup-title canvas "t") ""))) 2))
    (should (equal (+test-aup-title canvas "t") "Orders  ⚠ sleep: timed out after 0.3 s"))
    (should-not (agent-ui-panels--processes panel))
    (should-not (+test-aup-status canvas))))

(ert-deftest agent-ui-panels/a-query-s-error-on-its-element ()
  "A query of an element failing: said on its title (not the panel's line),
until it goes well."
  (+test-aup-open "flaky-element"
    (should (+test-wait-for (lambda () (string-match-p "⚠" (or (+test-aup-title canvas "t") ""))) 3))
    (should (equal (+test-aup-title canvas "t") "Deploy  ⚠ sh: exit 1: no ok yet"))
    (should-not (+test-aup-status canvas))
    (with-temp-file (expand-file-name "ok" root))
    (should (+test-wait-for (lambda () (equal (plist-get (agent-ui-get "t" :canvas canvas) :text) "ok")) 3))
    (should (+test-wait-for (lambda () (equal (+test-aup-title canvas "t") "Deploy")) 3))))

(ert-deftest agent-ui-panels/its-errors-on-it ()
  "A failure: a line under it saying so, in the error face, until a fetch
goes well."
  (+test-aup-open "flaky"
    (should (+test-wait-for (lambda () (+test-aup-status canvas)) 3))
    (should (equal (+test-aup-status canvas) "⚠ sh: exit 1: no ok yet"))
    (should (equal (plist-get (agent-ui-get agent-ui-panels--status-id :canvas canvas) :face) "error"))
    (with-temp-file (expand-file-name "ok" root))
    (should (+test-wait-for (lambda () (not (+test-aup-status canvas))) 3))
    (should (equal (plist-get (agent-ui-get "t" :canvas canvas) :text) "ok"))
    (should-not (agent-ui-panels--error panel))))

(ert-deftest agent-ui-panels/a-slow-fetch-said ()
  (+test-aup-open "frozen"
    (should (string-match-p "\\`⚠ fetch: took 0\\.[0-9]+ s itself, Emacs frozen meanwhile"
                            (+test-aup-status canvas)))))

(ert-deftest agent-ui-panels/read-again ()
  "gR: its file read again (edited), drawn anew, its code run again (stopped
first); wrong now, said on it, going on as it was."
  (+test-aup-open "counted"
    (let ((file (agent-ui-panel-file "counted")))
      (with-temp-file file
        (insert (replace-regexp-in-string ":type \"text\" :id \"t\" :text \"\""
                                          ":type \"text\" :id \"t\" :text \"edited\""
                                          (+test-aup-fixture "counted"))))
      (with-current-buffer canvas (agent-ui-panel-reload))
      (should (equal (plist-get (agent-ui-get "t" :canvas canvas) :text) "edited"))
      (should (equal (seq-filter (lambda (c) (memq c '(start stop))) (reverse +test-aup-calls))
                     '(start stop start)))
      ;; Wrong: said, the panel as it was.
      (with-temp-file file (insert "(agent-ui-panel :ui (:type \"text\"\n"))
      (with-current-buffer canvas (agent-ui-panel-reload))
      (should (string-match-p "\\`⚠ its file: panel counted: its file ends inside a form" (+test-aup-status canvas)))
      (should (equal (plist-get (agent-ui-get "t" :canvas canvas) :text) "edited"))
      (should (agent-ui-panels--timer panel))))
  (with-temp-buffer
    (agent-ui-canvas-mode)
    (should-error (agent-ui-panel-reload) :type 'user-error))
  (require 'evil)
  (should (eq (keymap-lookup (evil-get-auxiliary-keymap agent-ui-canvas-mode-map 'normal) "g R")
              #'agent-ui-panel-reload)))

;; ====== TRUSTING ONE ======

(ert-deftest agent-ui-panels/trusted-by-its-content ()
  "Its code runs once let (y), remembered by its file's content: not asked
again, after a restart too; changed, asked again. Not now (n): nothing run,
not remembered, said, gR asking again; view (v): its file shown, then asked
again (doom-3q5.5)."
  (+test-aup `(("counted" . ,(+test-aup-fixture "counted")))
    (let* ((agent-ui-panel-trust-file (expand-file-name "trusted.eld" (make-temp-file "trust-" t)))
           (agent-ui-panel-allow-function #'agent-ui-panels--allowed-p)
           (file (agent-ui-panel-file "counted"))
           (answers nil) (asked 0) (viewed nil))
      (cl-letf (((symbol-function 'read-multiple-choice) (lambda (&rest _) (cl-incf asked) (list (pop answers))))
                ((symbol-function 'view-file-other-window) (lambda (file) (push file viewed))))
        (save-window-excursion
          (setq answers (list ?n))
          (let ((canvas (agent-ui-open-panel "counted")))
            (should (= asked 1))
            (should-not (agent-ui-panels--script (buffer-local-value 'agent-ui-panels--state canvas)))
            (should (equal (+test-aup-status canvas) "⚠ its code: not run, not let: gR asks again"))
            (should-not (agent-ui-panel-trusted-p file))
            ;; gR: asked again; its file viewed first, then let.
            (setq answers (list ?v ?y))
            (with-current-buffer canvas (agent-ui-panel-reload))
            (should (= asked 3))
            (should (equal viewed (list file)))
            (should (agent-ui-panels--script (buffer-local-value 'agent-ui-panels--state canvas)))
            (should-not (+test-aup-status canvas))
            (kill-buffer canvas))
          ;; Remembered, in its file: not asked.
          (should (agent-ui-panel-trusted-p file))
          (should (string-match-p (regexp-quote (agent-ui-panels--hash file))
                                  (with-temp-buffer (insert-file-contents agent-ui-panel-trust-file) (buffer-string))))
          (kill-buffer (agent-ui-open-panel "counted" root))
          (should (= asked 3))
          ;; The same file in another repository: not trusted there, its
          ;; scripts not the ones let run (doom-ht6.48).
          (let* ((clone (file-name-as-directory (make-temp-file "clone-" t)))
                 (other (expand-file-name (concat agent-ui-panel-directory "/counted.el") clone)))
            (make-directory (file-name-directory other) t)
            (copy-file file other)
            (should (equal (agent-ui-panels--hash other) (agent-ui-panels--hash file)))
            (should-not (agent-ui-panel-trusted-p other))
            (delete-directory clone t))
          ;; Changed: asked again.
          (with-temp-file file (insert (+test-aup-fixture "counted") ";; changed\n"))
          (should-not (agent-ui-panel-trusted-p file))
          (setq answers (list ?n))
          (kill-buffer (agent-ui-open-panel "counted" root))
          (should (= asked 4))))))
  ;; Kept out of the repository, where Doom keeps its data.
  (should (equal agent-ui-panel-trust-file (expand-file-name "agent-ui/trusted-panels.eld" doom-data-dir))))

(ert-deftest agent-ui-panels/a-trusted-project-s-panels-unasked ()
  "Its project trusted (p): its panels run unasked, after a change too, a new
one too; another project's still asked about; the projects trusted listed,
one forgotten: its panels asked about again (doom-a3g)."
  (+test-aup `(("counted" . ,(+test-aup-fixture "counted"))
               ("other" . ,(concat (+test-aup-fixture "counted") ";; another\n")))
    (let* ((agent-ui-panel-trust-file (expand-file-name "trusted.eld" (make-temp-file "trust-" t)))
           (agent-ui-panel-allow-function #'agent-ui-panels--allowed-p)
           (file (agent-ui-panel-file "counted"))
           (answers nil) (asked 0) (choices nil))
      ;; A file let run by its content before: kept beside the project.
      (agent-ui-panel-trust (agent-ui-panel-file "other" root))
      (cl-letf (((symbol-function 'read-multiple-choice)
                 (lambda (_prompt options &rest _)
                   (cl-incf asked)
                   (setq choices (mapcar #'car options))
                   (list (pop answers)))))
        (save-window-excursion
          (setq answers (list ?p))
          (let ((canvas (agent-ui-open-panel "counted")))
            (should (= asked 1))
            (should (equal choices '(?y ?p ?v ?n)))
            (should (agent-ui-panels--script (buffer-local-value 'agent-ui-panels--state canvas)))
            (kill-buffer canvas))
          (should (agent-ui-panel-project-trusted-p root))
          (should (equal (mapcar #'car (agent-ui-panel-trusted-projects)) (list (file-truename root))))
          (should (agent-ui-panel-trusted-p (agent-ui-panel-file "other" root)))
          ;; Changed, a new one: not asked; the agent told they're let run.
          (with-temp-file file (insert (+test-aup-fixture "counted") ";; changed\n"))
          (with-temp-file (expand-file-name "new.el" (expand-file-name agent-ui-panel-directory root))
            (insert (+test-aup-fixture "counted")))
          (should (agent-ui-panel-trusted-p file))
          (kill-buffer (agent-ui-open-panel "counted" root))
          (kill-buffer (agent-ui-open-panel "new" root))
          (should (= asked 1))
          ;; Another project: asked.
          (let ((elsewhere (file-name-as-directory (make-temp-file "panels-elsewhere-" t))))
            (unwind-protect
                (progn
                  (make-directory (expand-file-name agent-ui-panel-directory elsewhere) t)
                  (with-temp-file (expand-file-name "counted.el" (expand-file-name agent-ui-panel-directory elsewhere))
                    (insert (+test-aup-fixture "counted")))
                  (should-not (agent-ui-panel-project-trusted-p elsewhere))
                  (setq answers (list ?n))
                  (kill-buffer (agent-ui-open-panel "counted" elsewhere))
                  (should (= asked 2)))
              (delete-directory elsewhere t)))
          ;; Forgotten (M-x, the trusted ones to pick from): asked again; the
          ;; file let run by its content still runs.
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt collection &rest _)
                       (should (equal collection (list (abbreviate-file-name (file-truename root)))))
                       (car collection))))
            (call-interactively #'agent-ui-panel-forget-project))
          (should-not (agent-ui-panel-project-trusted-p root))
          (should-not (agent-ui-panel-trusted-projects))
          (should-not (agent-ui-panel-trusted-p file))
          (should (agent-ui-panel-trusted-p (agent-ui-panel-file "other" root)))
          (setq answers (list ?n))
          (kill-buffer (agent-ui-open-panel "counted" root))
          (should (= asked 3))
          ;; None left: said so.
          (should-error (call-interactively #'agent-ui-panel-forget-project) :type 'user-error))))))

;; ====== THE AGENT AND PANELS ======

(defun +test-aup-request (lines &optional payload)
  "cmd/agent-ui's request: LINES (op id session cwd options canvas panel)
and PAYLOAD (JSON), answered; its reply, parsed."
  (let ((folder (make-temp-file "agent-ui-request-" t)))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name "request" folder) (insert (string-join lines "\n") "\n"))
          (when payload
            (with-temp-file (expand-file-name "payload" folder) (insert payload)))
          (agent-ui-request folder)
          (json-parse-string (with-temp-buffer (insert-file-contents (expand-file-name "reply" folder))
                                               (buffer-string))
                             :object-type 'plist :false-object :false))
      (delete-directory folder t))))

(ert-deftest agent-ui-panels/the-agent-opens-and-works-on-one ()
  "agent-ui panels, open NAME (shown, not selected; its code started once
the request is answered), --panel NAME on any operation (doom-3q5.6)."
  (+test-aup `(("live" . ,(+test-aup-fixture "live")) ("service" . ,+test-aup-service))
    (setq +test-aup-calls nil)
    (save-window-excursion
      (delete-other-windows)
      (let ((agent-ui--request-cwd root)
            (selected (selected-window)))
        (should (equal (plist-get (agent-ui-do "panels" nil nil nil) :panels)
                       [(:name "live" :open :false) (:name "service" :open :false)]))
        (let* ((reply (agent-ui-do "open" "live" nil nil))
               (canvas (get-buffer (plist-get reply :canvas))))
          (unwind-protect
              (progn
                (should (eq (plist-get reply :ok) t))
                ;; Its code not let yet (the test's let-everything aside).
                (should (eq (plist-get reply :trusted) :false))
                (should (eq (selected-window) selected))
                (should (get-buffer-window canvas))
                ;; Its code: a moment later, after the reply.
                (should-not +test-aup-calls)
                (should (+test-wait-for (lambda () (memq 'fetch +test-aup-calls)) 2))
                (should (equal (plist-get (agent-ui-do "panels" nil nil nil) :panels)
                               [(:name "live" :open t) (:name "service" :open :false)]))
                ;; --panel NAME: the request's canvas, the panel's.
                (let ((reply (+test-aup-request (list "update" "where" "" root "" "" "live") "{\"text\":\"from the agent\"}")))
                  (should (eq (plist-get reply :ok) t))
                  (should (equal (plist-get (agent-ui-get "where" :canvas canvas) :text) "from the agent")))
                (should (string-match-p "panel service isn't open: agent-ui open service"
                                        (plist-get (+test-aup-request (list "list" "" "" root "" "" "service")) :error))))
            (kill-buffer canvas)))))))

(ert-deftest agent-ui-panels/its-buttons-to-the-project-s-session ()
  "A panel's button: its prompt into the latest session working in its
project; none: said."
  (+test-aup '(("act" . "(agent-ui-panel :ui (:type \"text\" :id \"t\" :text \"2 failed\" :actions ((:label \"Fix them\" :prompt \"Fix the 2 failing tests\" :submit t))))\n"))
    (let* ((session (generate-new-buffer "Claude Agent @ act"))
           (sessions (list session))
           (inserted nil))
      (with-current-buffer session (setq default-directory root))
      (cl-letf (((symbol-function 'agent-ui--sessions) (lambda () sessions))
                ((symbol-function 'agent-shell-cwd) (lambda () default-directory))
                ((symbol-function 'agent-shell-insert) (lambda (&rest args) (push args inserted))))
        (save-window-excursion
          (let ((canvas (agent-ui-open-panel "act")))
            (unwind-protect
                (with-current-buffer canvas
                  (agent-ui--flush)
                  (goto-char (point-min))
                  (search-forward "⏵ Fix them")
                  (goto-char (match-beginning 0))
                  (agent-ui-button-press)
                  (should (equal (car inserted) (list :text "Fix the 2 failing tests" :submit t :shell-buffer session)))
                  (setq sessions nil)
                  (should (string-match-p "No agent-shell session in this panel's project"
                                          (cadr (should-error (agent-ui-button-press) :type 'user-error)))))
              (kill-buffer canvas)
              (kill-buffer session))))))))

(ert-deftest agent-ui-panels/an-element-saved-as-one ()
  "S: the element at point saved as the project's panel, as it was shown
(its updates, its data, left out), its code to write; trusted (the user
made it); one there already, asked before replacing it."
  (+test-aup '()
    (let* ((agent-ui-panel-trust-file (expand-file-name "trusted.eld" (make-temp-file "trust-" t)))
           (agent-ui-default-canvas (make-temp-name "save-"))
           (agent-ui-display-function #'ignore))
      (agent-ui-show '(:id "ci" :type "table" :title "CI" :columns ("Run" "Status") :key "Run"))
      (agent-ui-update "ci" '(:rows (("#812" "passed"))))
      (agent-ui-show '(:id "board" :type "panel" :title "Board"
                       :children ((:id "count" :type "stats" :figures ((:label "Open" :value 0))))))
      (agent-ui-update "count" '(:figures ((:label "Open" :value 9))))
      (let ((canvas (agent-ui-canvas)))
        (unwind-protect
            (with-current-buffer canvas
              (setq default-directory root)
              (agent-ui--flush)
              (goto-char (point-min))
              (search-forward "CI")
              (let ((file (agent-ui-save-panel "ci")))
                (should (equal file (expand-file-name ".agent-ui/panels/ci.el" root)))
                (let ((panel (agent-ui-panel-read file)))
                  (should (equal (plist-get (plist-get panel :ui) :columns) '("Run" "Status")))
                  (should-not (plist-get (plist-get panel :ui) :rows)))
                (should (agent-ui-panel-trusted-p file))
                (should (equal (plist-get (agent-ui-panel-check file) :blocking) [])))
              ;; A panel's child at point: its panel, as shown.
              (goto-char (point-min))
              (search-forward "Open")
              (agent-ui-save-panel "board")
              (should (equal (plist-get (car (plist-get (car (plist-get (plist-get (agent-ui-panel-read (agent-ui-panel-file "board")) :ui) :children)) :figures)) :value)
                             0))
              ;; There already: asked.
              (goto-char (point-min))
              (search-forward "CI")
              (cl-letf (((symbol-function 'y-or-n-p) #'ignore))
                (should-error (agent-ui-save-panel "ci") :type 'user-error)))
          (kill-buffer canvas)))))
  (should (eq (keymap-lookup (evil-get-auxiliary-keymap agent-ui-canvas-mode-map 'normal) "S")
              #'agent-ui-save-panel)))

;; ====== THIS CONFIG'S OWN ======

(defun +test-aup-own (name)
  "The text of this config's own panel NAME, .agent-ui/panels/NAME.el."
  (with-temp-buffer
    (insert-file-contents (expand-file-name (format ".agent-ui/panels/%s.el" name) doom-user-dir))
    (buffer-string)))

(ert-deftest agent-ui-panels/this-config-s-demo-panels ()
  "The cpu and memory demo panels, filled on this system (macOS or Linux),
no error: their figures numbers, their processes listed; the memory one's
pressure said, its breakdown by this system's names, its compressor's rate
from its second fetch."
  (+test-aup `(("cpu" . ,(+test-aup-own "cpu")) ("memory" . ,(+test-aup-own "memory")))
    ;; Shown while they're checked: one hidden isn't fetched.
    (save-window-excursion
     (let ((canvas (agent-ui-open-panel "cpu")))
      (unwind-protect
          (progn
            (should (+test-wait-for (lambda () (plist-get (agent-ui-get "processes" :canvas canvas) :rows)) 10))
            (should (numberp (plist-get (agent-ui-get "cpu" :canvas canvas) :value)))
            (should (<= 0 (plist-get (agent-ui-get "cpu" :canvas canvas) :value) 100))
            (should (cl-every (lambda (figure) (numberp (plist-get figure :value)))
                              (plist-get (agent-ui-get "load" :canvas canvas) :figures)))
            (should (> (plist-get (nth 3 (plist-get (agent-ui-get "load" :canvas canvas) :figures)) :value) 0))
            (should-not (agent-ui-panels--error (buffer-local-value 'agent-ui-panels--state canvas))))
        (kill-buffer canvas))))
    (save-window-excursion
     (let ((canvas (agent-ui-open-panel "memory")))
      (unwind-protect
          (cl-flet ((get (id prop) (plist-get (agent-ui-get id :canvas canvas) prop)))
            (should (+test-wait-for (lambda () (cdr (get "used-history" :values))) 10))
            (should (get "processes" :rows))
            (should (< 0 (get "used" :value) 100))
            (should (> (plist-get (car (get "figures" :figures)) :value) 0))
            (should (member (plist-get (car (get "pressure" :tags)) :label)
                            '("normal" "warning" "critical" "not known")))
            (should (equal (get "breakdown" :labels)
                           (if (eq system-type 'darwin)
                               '("App memory" "Wired" "Compressed" "Cached files" "Free")
                             '("App memory" "Kernel" "Compressed" "Cached files" "Free"))))
            (should (cl-every #'numberp (get "breakdown" :values)))
            (should (> (car (get "breakdown" :values)) 0))
            (should (cl-every (lambda (series) (plist-get series :values)) (get "compressor" :series)))
            (should-not (agent-ui-panels--error (buffer-local-value 'agent-ui-panels--state canvas))))
        (kill-buffer canvas))))))
