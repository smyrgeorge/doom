;;; tests/e2e/test-excalidraw.el -*- lexical-binding: t; -*-
;; config/excalidraw.el in a GUI Emacs: real drawings in WebKit, drawn by
;; Excalidraw (a copy of Doom's, never downloaded here). New drawings, saving
;; (SVG and JSON, waiting for the last change), reopening, the mouse, Emacs's
;; keys, copy and paste, split panes, changes on disk, closing right after a
;; change, the dark canvas, inserting from Markdown, files that aren't
;; drawings, the pointer, a drawing's PNG, another drawing shown instead, and
;; drawings for Claude (config/agent-shell/excalidraw.el: agent-shell's
;; prompt stubbed, no agent).

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

(+test-load "config/childframe" "config/banner" "config/window" "config/editor" "config/webkit" "config/excalidraw"
            "config/agent-shell")
(require 'markdown-mode)

;; ====== SETUP ======

;; Excalidraw: Doom's, copied into the temp data folder (`+my/excalidraw-dir'
;; is there already: `doom-data-dir' is the temp one).
(defvar +test-exd--excalidraw (+test-excalidraw-dir))

(defun +test-exd--file (name)
  "A file NAME in a folder of its own (not there yet), by its true name."
  (expand-file-name name (file-truename (make-temp-file (+test-tmp-file "drawings/d") t))))

;; ====== HELPERS ======

(defun +test-exd--xw (&optional window)
  (let ((window (or window (selected-window))))
    (with-current-buffer (window-buffer window)
      (+my/webkit-xwidget window))))

(defun +test-exd--js (script &optional window)
  "SCRIPT's value in WINDOW's page (waited for)."
  (+test-js (+test-exd--xw window) script))

(defun +test-exd--state (&optional window)
  "WINDOW's page's state, asked of it (not its title: that may lag)."
  (json-parse-string (+test-exd--js "exd.state()" window) :object-type 'plist
                     :false-object nil :null-object nil))

(defun +test-exd--ready (&optional window)
  "WINDOW's view of its drawing, once Excalidraw shows it and counts changes."
  (let ((window (or window (selected-window))))
    (+test-wait-for
     (lambda ()
       (let ((xwidget (+test-exd--xw window)))
         (and xwidget
              (xwidget-view-lookup xwidget window)
              (plist-get (with-current-buffer (window-buffer window) (+my/excalidraw--state xwidget))
                         :ready)
              (equal (+test-exd--js "String(!!(window.exd && exd.settled()))" window) "true")
              xwidget)))
     20)))

(defun +test-exd--open (file &optional window)
  "FILE opened in WINDOW (default: the selected one), ready; its buffer."
  (when window (select-window window))
  (find-file file)
  (should (eq major-mode '+my/excalidraw-mode))
  (should (+test-exd--ready))
  (current-buffer))

(defun +test-exd--elements (&optional window)
  "The types of WINDOW's drawing's elements (\"rectangle\"...), with a text's
text after a colon."
  (json-parse-string
   (+test-exd--js "JSON.stringify(exd.api().getSceneElements().filter(e => !e.isDeleted).map(e => e.type + (e.type === 'text' ? ':' + e.text : '')))"
                  window)
   :array-type 'list))

(defun +test-exd--changed (thunk &optional window)
  "Call THUNK, which changes WINDOW's drawing; wait for the page to count it;
return its version."
  (let ((before (plist-get (+test-exd--state window) :version))
        version)
    (funcall thunk)
    (should (+test-wait-for
             (lambda () (> (setq version (plist-get (+test-exd--state window) :version)) before))
             5))
    version))

(defun +test-exd--add (skeletons &optional window)
  "Add elements made from SKELETONS (a JavaScript array of Excalidraw's
skeletons) to WINDOW's drawing; return its version."
  (+test-exd--changed
   (lambda ()
     (+test-exd--js (format "(() => { const api = exd.api(); api.updateScene({elements: api.getSceneElements().concat(ExcalidrawLib.convertToExcalidrawElements(%s))}); return 'ok' })()"
                            skeletons)
                    window))
   window))

(defun +test-exd--in-buffer (version &optional window)
  "Wait until WINDOW's drawing at VERSION is its buffer's text."
  (let* ((window (or window (selected-window)))
         (xwidget (+test-exd--xw window)))
    (should (+test-wait-for (lambda () (>= (or (xwidget-get xwidget 'fetched) 0) version)) 5))))

(defun +test-exd--pointer (type x y buttons &optional window)
  "A pointer event of TYPE at X, Y on WINDOW's canvas."
  (+test-exd--js
   (format "(() => { const c = document.querySelector('canvas.excalidraw__canvas.interactive'); c.dispatchEvent(new PointerEvent(%S, {bubbles: true, cancelable: true, composed: true, view: window, pointerId: 1, pointerType: 'mouse', isPrimary: true, button: %d, buttons: %d, clientX: %d, clientY: %d})); return 'ok' })()"
           type (if (equal type "pointermove") -1 0) buttons x y)
   window))

(defun +test-exd--drag (x1 y1 x2 y2 &optional window)
  "Drag the mouse on WINDOW's canvas from X1, Y1 to X2, Y2, as a hand would
(Excalidraw takes moves once per frame)."
  (+test-exd--pointer "pointerdown" x1 y1 1 window)
  (+test-sleep 0.05)
  (dolist (step '(0.25 0.5 1.0))
    (+test-exd--pointer "pointermove" (round (+ x1 (* step (- x2 x1)))) (round (+ y1 (* step (- y2 y1)))) 1
                        window)
    (+test-sleep 0.05))
  (+test-exd--pointer "pointerup" x2 y2 0 window))

(defun +test-exd--key (key)
  "Type KEY (`kbd' syntax) in Emacs."
  (execute-kbd-macro (kbd key))
  (+test-sleep 0.1))

(defun +test-exd--make (file skeletons)
  "Make drawing FILE with elements from SKELETONS, saved and closed."
  (let ((buffer (+test-exd--open file)))
    (+test-exd--in-buffer (+test-exd--add skeletons))
    (save-buffer)
    (kill-buffer buffer)
    file))

(defun +test-exd--file-text (file)
  (with-temp-buffer
    (insert-file-contents file)
    (buffer-string)))

(defmacro +test-exd (&rest body)
  "BODY with Excalidraw there, from one window, a light canvas, a kill ring of
its own; the drawings closed after."
  (declare (indent 0))
  `(progn
     (+test-needs-webkit)
     (unless +test-exd--excalidraw
       (ert-skip "No Excalidraw in Doom's data folder (open a drawing in Emacs once)"))
     (let ((+my/excalidraw-theme 'light)
           (kill-ring nil)
           (kill-ring-yank-pointer nil)
           (interprogram-cut-function nil)
           (interprogram-paste-function nil))
       (+test-with-reset
         (+test-clear-messages)
         ,@body
         (+test-sleep 0.2)))))

(defconst +test-exd--two-shapes
  "[{type: 'rectangle', x: 100, y: 100, width: 120, height: 80}, {type: 'ellipse', x: 300, y: 120, width: 90, height: 60}]")

;; ====== NEW DRAWINGS ======

(ert-deftest e2e-exd/a-new-drawing-is-a-blank-svg-to-save ()
  (+test-exd
    (let* ((file (+test-exd--file "new.excalidraw.svg"))
           (buffer (+test-exd--open file)))
      (should (equal (+test-exd--elements) nil))
      ;; Its blank drawing, made by the page: the buffer's text, to save.
      (should (+test-wait-for (lambda () (string-prefix-p "<svg" (buffer-string))) 5))
      (should (buffer-modified-p))
      (let ((text (buffer-string)))
        (should (string-search "<!-- payload-start -->" text))
        ;; Fonts at the CDN (Excalidraw's own default names version "undefined").
        (should (string-search "https://cdn.jsdelivr.net/npm/@excalidraw/excalidraw@0.17.6/dist/excalidraw-assets/Virgil.woff2" text))
        (should-not (string-search "file:" text))
        (should-not (string-search "undefined" text))
        ;; Nothing a project's .editorconfig would have Emacs change as it saves.
        (should (string-suffix-p "</svg>\n" text))
        (should-not (string-match-p "[ \t]$" text)))
      (save-buffer)
      (should-not (buffer-modified-p))
      (should (string-prefix-p "<svg" (+test-exd--file-text file)))
      ;; Still the drawing.
      (should (eq (window-buffer) buffer)))))

(ert-deftest e2e-exd/reopened-as-saved-unmodified ()
  (+test-exd
    (let ((file (+test-exd--make (+test-exd--file "two.excalidraw.svg") +test-exd--two-shapes)))
      (+test-exd--open file)
      (should (equal (+test-exd--elements) '("rectangle" "ellipse")))
      ;; Excalidraw's own changes as it starts don't count.
      (+test-sleep 1)
      (should-not (buffer-modified-p))
      (should (eql (plist-get (+test-exd--state) :version) 0))
      (should (equal (buffer-string) (+test-exd--file-text file))))))

;; ====== DRAWING ======

(ert-deftest e2e-exd/drawn-with-the-mouse ()
  (+test-exd
    (let* ((file (+test-exd--file "mouse.excalidraw.svg"))
           (buffer (+test-exd--open file)))
      (save-buffer)
      (+test-exd--key "r")
      (let ((version (+test-exd--changed (lambda () (+test-exd--drag 200 200 400 320)))))
        (should (equal (+test-exd--elements) '("rectangle")))
        (should (equal (+test-exd--js "JSON.stringify(exd.api().getSceneElements().map(e => [Math.round(e.width), Math.round(e.height)]))")
                       "[[200,120]]"))
        (should (buffer-modified-p))
        (+test-exd--in-buffer version))
      (save-buffer)
      (kill-buffer buffer)
      (+test-exd--open file)
      (should (equal (+test-exd--elements) '("rectangle"))))))

(ert-deftest e2e-exd/json-drawings ()
  "*.excalidraw: Excalidraw's JSON, read and saved."
  (+test-exd
    (let ((file (+test-exd--file "plan.excalidraw")))
      (with-temp-file file
        (insert "{\"type\":\"excalidraw\",\"version\":2,\"source\":\"https://excalidraw.com\",\"elements\":[{\"id\":\"r1\",\"type\":\"rectangle\",\"x\":10,\"y\":10,\"width\":100,\"height\":50,\"angle\":0,\"strokeColor\":\"#1e1e1e\",\"backgroundColor\":\"transparent\",\"fillStyle\":\"solid\",\"strokeWidth\":2,\"strokeStyle\":\"solid\",\"roughness\":1,\"opacity\":100,\"groupIds\":[],\"frameId\":null,\"roundness\":null,\"seed\":1,\"version\":1,\"versionNonce\":1,\"isDeleted\":false,\"boundElements\":null,\"updated\":1,\"link\":null,\"locked\":false}],\"appState\":{\"viewBackgroundColor\":\"#ffffff\"},\"files\":{}}"))
      (+test-exd--open file)
      (should (equal (+test-exd--elements) '("rectangle")))
      (+test-exd--in-buffer (+test-exd--add "[{type: 'text', x: 10, y: 100, text: 'Plan ✓'}]"))
      ;; With a project's .editorconfig asking to trim and end with a newline.
      (add-hook 'before-save-hook #'delete-trailing-whitespace nil t)
      (setq-local require-final-newline t)
      ;; Nothing a project's .editorconfig would have Emacs change as it saves.
      (should (string-suffix-p "}\n" (buffer-string)))
      (should-not (string-match-p "[ \t]$" (buffer-string)))
      (save-buffer)
      (let ((saved (json-parse-string (+test-exd--file-text file) :object-type 'alist :array-type 'list)))
        (should (equal (alist-get 'type saved) "excalidraw"))
        (should (equal (mapcar (lambda (element) (alist-get 'type element)) (alist-get 'elements saved))
                       '("rectangle" "text")))
        (should (equal (alist-get 'text (nth 1 (alist-get 'elements saved))) "Plan ✓"))))))

(ert-deftest e2e-exd/saving-waits-for-the-last-change ()
  "A change, saved at once (before the page exported it): in the file."
  (+test-exd
    (let* ((file (+test-exd--make (+test-exd--file "quick.excalidraw.svg") "[{type: 'rectangle', x: 0, y: 0, width: 50, height: 50}]"))
           (buffer (+test-exd--open file)))
      (+test-exd--js "(() => { const api = exd.api(); api.updateScene({elements: api.getSceneElements().concat(ExcalidrawLib.convertToExcalidrawElements([{type: 'diamond', x: 100, y: 0, width: 50, height: 50}]))}); return 'ok' })()")
      (set-buffer-modified-p t)              ; Emacs hasn't seen it yet
      (save-buffer)
      (kill-buffer buffer)
      (+test-exd--open file)
      (should (equal (+test-exd--elements) '("rectangle" "diamond"))))))

;; ====== KEYS ======

(ert-deftest e2e-exd/emacs-keys-to-excalidraw ()
  (+test-exd
    (+test-exd--open (+test-exd--make (+test-exd--file "keys.excalidraw.svg") +test-exd--two-shapes))
    (let ((tool (lambda () (+test-exd--js "exd.api().getAppState().activeTool.type")))
          (selected (lambda () (+test-exd--js "String(Object.keys(exd.api().getAppState().selectedElementIds).length)")))
          (zoom (lambda () (string-to-number (+test-exd--js "String(exd.api().getAppState().zoom.value)")))))
      ;; Tools, before Evil's keys (r replaces a character, o opens a line).
      (+test-exd--key "r")
      (should (equal (funcall tool) "rectangle"))
      (+test-exd--key "o")
      (should (equal (funcall tool) "ellipse"))
      (+test-exd--key "2")
      (should (equal (funcall tool) "rectangle"))
      (+test-exd--key "<escape>")
      (should (equal (funcall tool) "selection"))
      ;; Cmd+A, Delete, Cmd+Z, Cmd+Shift+Z.
      (+test-exd--key "s-a")
      (should (equal (funcall selected) "2"))
      (+test-exd--changed (lambda () (+test-exd--key "<delete>")))
      (should (equal (+test-exd--elements) nil))
      (+test-exd--changed (lambda () (+test-exd--key "s-z")))
      (should (equal (+test-exd--elements) '("rectangle" "ellipse")))
      (+test-exd--changed (lambda () (+test-exd--key "s-Z")))
      (should (equal (+test-exd--elements) nil))
      (+test-exd--key "s-z")
      ;; Zoom: Cmd+=, Cmd+0.
      (let ((before (funcall zoom)))
        (+test-exd--key "s-=")
        (should (> (funcall zoom) before))
        (+test-exd--key "s-0")
        (should (= (funcall zoom) 1)))
      ;; Emacs keeps its own.
      (should (eq (key-binding (kbd ":")) #'evil-ex))
      (should (buffer-modified-p)))))

;; ====== COPY AND PASTE ======

(ert-deftest e2e-exd/copy-and-paste-through-the-kill-ring ()
  (+test-exd
    (+test-exd--open (+test-exd--make (+test-exd--file "copy.excalidraw.svg") +test-exd--two-shapes))
    (+test-exd--key "s-a")
    (+test-exd--key "s-c")
    (should (+test-wait-for (lambda () kill-ring) 3))
    (let ((clipboard (json-parse-string (car kill-ring) :object-type 'alist :array-type 'list)))
      (should (equal (alist-get 'type clipboard) "excalidraw/clipboard"))
      (should (= (length (alist-get 'elements clipboard)) 2)))
    (+test-exd--changed (lambda () (+test-exd--key "s-v")))
    (should (equal (+test-exd--elements) '("rectangle" "ellipse" "rectangle" "ellipse")))
    ;; Text from elsewhere: a text element (characters, not UTF-8 bytes).
    (kill-new "Hello ✓ «drawing»")
    (+test-exd--changed (lambda () (+test-exd--key "s-v")))
    (should (member "text:Hello ✓ «drawing»" (+test-exd--elements)))
    ;; Cut.
    (+test-exd--key "s-a")
    (+test-exd--changed (lambda () (+test-exd--key "s-x")))
    (should (equal (+test-exd--elements) nil))
    (should (+test-wait-for (lambda () (string-search "excalidraw/clipboard" (car kill-ring))) 3))))

;; ====== SPLIT PANES ======

(ert-deftest e2e-exd/panes-show-each-others-changes ()
  (+test-exd
    (let* ((file (+test-exd--make (+test-exd--file "split.excalidraw.svg") "[{type: 'rectangle', x: 0, y: 0, width: 50, height: 50}]"))
           (buffer (+test-exd--open file))
           (left (selected-window))
           (right (split-window-right)))
      (should (+test-exd--ready right))
      (should-not (eq (+test-exd--xw left) (+test-exd--xw right)))
      (+test-exd--in-buffer (+test-exd--add "[{type: 'ellipse', x: 100, y: 0, width: 50, height: 50}]" left) left)
      (should (+test-wait-for (lambda () (equal (+test-exd--elements right) '("rectangle" "ellipse"))) 5))
      (select-window right)
      (+test-exd--in-buffer (+test-exd--add "[{type: 'diamond', x: 200, y: 0, width: 50, height: 50}]" right) right)
      (should (+test-wait-for (lambda () (equal (+test-exd--elements left) '("rectangle" "ellipse" "diamond"))) 5))
      ;; Text too (measured as it's shown).
      (+test-exd--in-buffer (+test-exd--add "[{type: 'text', x: 0, y: 100, text: 'Both ✓'}]" right) right)
      (should (+test-wait-for (lambda () (member "text:Both ✓" (+test-exd--elements left))) 5))
      ;; Shown, not changes of their own: nothing goes back and forth.
      (+test-sleep 1)
      (let ((versions (list (plist-get (+test-exd--state left) :version)
                            (plist-get (+test-exd--state right) :version)))
            (text (with-current-buffer buffer (buffer-string))))
        (+test-sleep 1.5)
        (should (equal (list (plist-get (+test-exd--state left) :version)
                             (plist-get (+test-exd--state right) :version))
                       versions))
        (should (equal (with-current-buffer buffer (buffer-string)) text)))
      (should (equal (+test-exd--elements right) '("rectangle" "ellipse" "diamond" "text:Both ✓")))
      (with-current-buffer buffer
        (save-buffer))
      (delete-window right)
      (kill-buffer buffer)
      (+test-exd--open file)
      (should (equal (+test-exd--elements) '("rectangle" "ellipse" "diamond" "text:Both ✓"))))))

;; ====== CHANGED ON DISK ======

(ert-deftest e2e-exd/changed-on-disk-shown-anew ()
  (+test-exd
    (let* ((other (+test-exd--make (+test-exd--file "other.excalidraw.svg") +test-exd--two-shapes))
           (file (+test-exd--make (+test-exd--file "mine.excalidraw.svg") "[{type: 'diamond', x: 0, y: 0, width: 50, height: 50}]"))
           (buffer (+test-exd--open file)))
      (copy-file other file t)
      (revert-buffer t t)
      (should (+test-wait-for (lambda () (equal (+test-exd--elements) '("rectangle" "ellipse"))) 5))
      (should-not (buffer-modified-p))
      (should (equal (buffer-string) (+test-exd--file-text other)))
      ;; Shown, not a change.
      (+test-sleep 1)
      (should-not (buffer-modified-p))
      (should (eq (window-buffer) buffer)))))

;; ====== CLOSING ======

(ert-deftest e2e-exd/closed-right-after-a-change ()
  "Closed while its page's export may be on its way to Emacs: no crash (a
view killed while an answer was pending crashed Emacs), the views go once
their answers have come."
  (+test-exd
    (let ((buffer (+test-exd--open (+test-exd--make (+test-exd--file "close.excalidraw.svg") +test-exd--two-shapes))))
      (dotimes (i 3)
        (+test-exd--add (format "[{type: 'rectangle', x: %d, y: 300, width: 20, height: 20}]" (* i 30))))
      ;; Its export asked for, maybe.
      (+test-sleep 0.35)
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (let ((kill-buffer-query-functions nil))
        (kill-buffer buffer))
      (+test-sleep 6)
      (should (eq (+test-exd--xw) nil))
      ;; Emacs is fine: another drawing opens.
      (+test-exd--open (+test-exd--file "after.excalidraw.svg"))
      (should (equal (+test-exd--elements) nil)))))

(defvar +test-exd--late nil "An answer that came too late, if it was taken.")

(defun +test-exd--late-answer (value)
  (setq +test-exd--late value))

(ert-deftest e2e-exd/closed-while-an-answer-is-on-its-way ()
  "An answer held back by the page, the buffer killed meanwhile: its view is
kept, in a buffer of its own, until the answer has come (no crash), which
goes nowhere; then killed."
  (+test-exd
    (let* ((buffer (+test-exd--open (+test-exd--file "pending.excalidraw.svg")))
           (xwidget (+test-exd--xw)))
      (setq +test-exd--late nil)
      (with-current-buffer buffer
        (should (+my/webkit-ask "(() => { const end = Date.now() + 400; while (Date.now() < end); return 'late' })()"
                                #'+test-exd--late-answer)))
      (with-current-buffer buffer (set-buffer-modified-p nil))
      (let ((kill-buffer-query-functions nil))
        (kill-buffer buffer))
      (should (xwidget-get xwidget '+my/webkit-closing))
      (should (equal (buffer-name (xwidget-buffer xwidget)) " *webkit-closing*"))
      (should-not (xwidget-get xwidget '+my/webkit-killed))
      ;; Killed: macOS's Emacs says so in its properties (`xwidget-live-p'
      ;; stays t); Linux's can't read a killed view's, it says it's not live.
      (should (+test-wait-for (lambda () (or (not (xwidget-live-p xwidget))
                                             (xwidget-get xwidget '+my/webkit-killed)))
                              3))
      (should-not +test-exd--late)
      (should (assq xwidget +my/webkit--killed))
      (+test-sleep 0.3)
      (+test-exd--open (+test-exd--file "next.excalidraw.svg")))))

;; ====== DARK CANVAS ======

(ert-deftest e2e-exd/dark-canvas ()
  (+test-exd
    (+test-exd--open (+test-exd--file "dark.excalidraw.svg"))
    (+my/excalidraw-toggle-dark)
    (should (+test-wait-for (lambda () (equal (+test-exd--js "exd.api().getAppState().theme") "dark")) 3))
    (should (eq (plist-get (+test-exd--state) :dark) t))
    ;; Not a change of the drawing.
    (+test-sleep 0.5)
    (should (eql (plist-get (+test-exd--state) :version) 1))
    (+my/excalidraw-toggle-dark)
    (should (+test-wait-for (lambda () (equal (+test-exd--js "exd.api().getAppState().theme") "light")) 3))
    (should (eq +my/excalidraw-theme 'light))))

;; ====== INSERTING ======

(ert-deftest e2e-exd/inserted-from-markdown ()
  (+test-exd
    (let* ((md (+test-exd--file "notes.md"))
           (dir (file-name-directory md)))
      (find-file md)
      (markdown-mode)
      (insert "# Notes\n\n")
      (let ((from (selected-window)))
        (+my/excalidraw-insert "fig")
        (should (equal (with-current-buffer (window-buffer from) (buffer-string))
                       "# Notes\n\n![](fig.excalidraw.svg)"))
        ;; Beside, taking focus.
        (should-not (eq (selected-window) from))
        (should (eq (window-in-direction 'right from) (selected-window)))
        (should (equal buffer-file-name (expand-file-name "fig.excalidraw.svg" dir)))
        (should (+test-exd--ready))
        ;; Saved blank at once: the link shows an image.
        (should (+test-wait-for (lambda () (and (file-exists-p buffer-file-name) (not (buffer-modified-p)))) 5))
        (should (string-prefix-p "<svg" (+test-exd--file-text buffer-file-name)))
        ;; Back on the link: Option+Enter edits it.
        (select-window from)
        (goto-char (point-max))
        (backward-char 3)
        (should (equal (+my/excalidraw--at-point) (expand-file-name "fig.excalidraw.svg" dir)))
        (should (member '("Drawing" "Edit the drawing") (mapcar #'butlast (+my/context-actions-excalidraw))))
        (set-buffer-modified-p nil)))))

;; ====== NOT A DRAWING ======

(ert-deftest e2e-exd/a-file-that-isnt-a-drawing ()
  (+test-exd
    (let ((file (+test-exd--file "plain.excalidraw.svg")))
      (with-temp-file file
        (insert "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><rect width=\"10\" height=\"10\"/></svg>\n"))
      (+test-exd--open file)
      (should (equal (+test-exd--elements) nil))
      (should (string-prefix-p "Not a drawing Excalidraw opens" (plist-get (+test-exd--state) :error)))
      ;; Said above it.
      (should (+test-wait-for (lambda () (assq 'excalidraw +my/banner--list)) 3))
      (should (string-match-p "saving replaces the file" (nth 1 (assq 'excalidraw +my/banner--list))))
      (should-not (buffer-modified-p)))))

;; ====== LIBRARIES ======

(defconst +test-exd--library
  "{\"type\":\"excalidrawlib\",\"version\":2,\"source\":\"test\",\"libraryItems\":[{\"id\":\"box\",\"status\":\"published\",\"created\":1,\"name\":\"Box\",\"elements\":[{\"id\":\"r1\",\"type\":\"rectangle\",\"x\":0,\"y\":0,\"width\":100,\"height\":50,\"angle\":0,\"strokeColor\":\"#1e1e1e\",\"backgroundColor\":\"transparent\",\"fillStyle\":\"solid\",\"strokeWidth\":2,\"strokeStyle\":\"solid\",\"roughness\":1,\"opacity\":100,\"groupIds\":[],\"frameId\":null,\"roundness\":null,\"seed\":1,\"version\":1,\"versionNonce\":1,\"isDeleted\":false,\"boundElements\":null,\"updated\":1,\"link\":null,\"locked\":false}]}]}"
  "A library of one item, a box.")

(defun +test-exd--library-file ()
  "A library file (see `+test-exd--library'); its name."
  (let ((file (+test-exd--file "box.excalidrawlib")))
    (with-temp-file file (insert +test-exd--library))
    file))

(defun +test-exd--library-items (&optional window)
  "The names of WINDOW's page's library's items."
  (let* ((answer (+test-exd--js "exd.library()" window))
         (json (json-parse-string (substring answer (1+ (string-search "\n" answer)))
                                  :object-type 'alist :array-type 'list)))
    (mapcar (lambda (item) (alist-get 'name item)) (alist-get 'libraryItems json))))

(defun +test-exd--kept-library ()
  "The names of the library file's items."
  (when (file-exists-p +my/excalidraw-library-file)
    (mapcar (lambda (item) (alist-get 'name item))
            (alist-get 'libraryItems (json-parse-string (+test-exd--file-text +my/excalidraw-library-file)
                                                        :object-type 'alist :array-type 'list)))))

(defmacro +test-exd--with-library-file (&rest body)
  "BODY with a library file of its own (none yet)."
  (declare (indent 0))
  `(let ((+my/excalidraw-library-file (expand-file-name "library.excalidrawlib" (+test-exd--file "library"))))
     ,@body))

(ert-deftest e2e-exd/a-library-from-a-link-kept-for-every-drawing ()
  "libraries.excalidraw.com's \"Add to Excalidraw\" link, as the browser got
it: the library added in the drawing (its panel open), kept in the file, shown
in the drawings open and in the ones opened next."
  (+test-exd
    (+test-exd--with-library-file
      (let* ((a (+test-exd--open (+test-exd--file "a.excalidraw.svg")))
             (left (selected-window))
             (right (split-window-right))
             (b (+test-exd--open (+test-exd--file "b.excalidraw.svg") right))
             (link (concat "file:///private/var/folders/x/excalidraw-1/index.html#addLibrary="
                           (url-hexify-string (+my/webkit-file-url (+test-exd--library-file)))
                           "&token=abc")))
        (should (equal (+test-exd--library-items left) nil))
        (select-window left)
        (+my/excalidraw-add-library link)
        (should (+test-wait-for (lambda () (equal (+test-exd--library-items left) '("Box"))) 5))
        (should (equal (+test-exd--js "String(exd.api().getAppState().openSidebar && exd.api().getAppState().openSidebar.tab)" left)
                       "library"))
        ;; Kept, and in the other drawing open.
        (should (+test-wait-for (lambda () (equal (+test-exd--kept-library) '("Box"))) 5))
        (should (+test-wait-for (lambda () (equal (+test-exd--library-items right) '("Box"))) 5))
        ;; Not changes of the drawings.
        (should (eql (plist-get (+test-exd--state right) :version) 1))
        ;; A drawing opened next starts with it.
        (with-current-buffer b (set-buffer-modified-p nil))
        (kill-buffer b)
        (delete-window right)
        (+test-exd--open (+test-exd--file "c.excalidraw.svg"))
        (should (equal (+test-exd--library-items) '("Box")))
        (ignore a)))))

(defun +test-exd--site (library)
  "A stand-in for libraries.excalidraw.com (no download): an \"Add to
Excalidraw\" link as the site's, to the address of no site with LIBRARY (a
file) in it, opening a new window. Its file:// URL."
  (let ((site (+test-exd--file "site.html")))
    (with-temp-file site
      (insert (format "<!doctype html><title>Libraries</title><body><div class=\"library\"><a class=\"btn primary install-library\" href=\"%s#addLibrary=%s&token=emacs\" target=\"_blank\">Add to Excalidraw</a></div></body>"
                      +my/excalidraw--library-return (url-hexify-string (+my/webkit-file-url library)))))
    (+my/webkit-file-url site)))

(defun +test-exd--site-xwidget ()
  (seq-find (lambda (xwidget) (eq (xwidget-get xwidget 'callback) #'+my/excalidraw--libraries-callback))
            xwidget-list))

(ert-deftest e2e-exd/browse-libraries-and-add-one ()
  "The libraries' site (here a stand-in, no download) in Emacs, in the
drawing's window, a notice above it: its \"Add to Excalidraw\" (followed in
its own window, on its way to the address of no site, with the library in it)
adds the library, closes the site, shows the drawing again."
  (+test-exd
    (+test-exd--with-library-file
      (let* ((drawing (+test-exd--open (+test-exd--file "browse.excalidraw.svg")))
             (window (selected-window))
             (site (+my/excalidraw-browse-libraries (+test-exd--site (+test-exd--library-file)) drawing)))
        (should-not (eq (window-buffer window) drawing))
        (should (assq 'excalidraw-libraries (buffer-local-value '+my/banner--list (window-buffer window))))
        ;; Told to say the link clicked in its title once loaded; the link clicked.
        (should (+test-wait-for (lambda () (equal (ignore-errors (+test-js site "String(window.exdLibraries === true)"))
                                                  "true"))
                                10))
        (xwidget-webkit-execute-script site "document.querySelector('.install-library').click()")
        (should (+test-wait-for (lambda () (eq (window-buffer window) drawing)) 10))
        (should (+test-exd--ready window))
        (should (+test-wait-for (lambda () (equal (+test-exd--library-items window) '("Box"))) 5))
        (should (+test-wait-for (lambda () (equal (+test-exd--kept-library) '("Box"))) 5))
        ;; The site's gone.
        (should-not (seq-some (lambda (buffer) (eq (buffer-local-value 'major-mode buffer) 'xwidget-webkit-mode))
                              (buffer-list)))))))

(ert-deftest e2e-exd/browse-libraries-and-go-back ()
  "The notice's Back to the drawing: the site closed, the drawing shown, no
library added."
  (+test-exd
    (+test-exd--with-library-file
      (let* ((drawing (+test-exd--open (+test-exd--file "back.excalidraw.svg")))
             (window (selected-window)))
        (+my/excalidraw-browse-libraries (+test-exd--site (+test-exd--library-file)) drawing)
        (should (+test-wait-for #'+test-exd--site-xwidget 5))
        (+test-sleep 0.5)
        (with-current-buffer (window-buffer window)
          (funcall (cdr (assoc "Back to the drawing" (nth 2 (assq 'excalidraw-libraries +my/banner--list))))))
        (should (eq (window-buffer window) drawing))
        (should-not (+test-exd--site-xwidget))
        (+test-sleep 0.5)
        (should (equal (+test-exd--library-items window) nil))
        (should-not (file-exists-p +my/excalidraw-library-file))))))

;; ====== POINTER ======

(ert-deftest e2e-exd/pointer-the-page-wants ()
  "The hand over the toolbar's buttons, the arrow over the canvas."
  (+test-exd
    (+test-exd--open (+test-exd--file "pointer.excalidraw.svg"))
    (let ((move (lambda (selector)
                  (+test-exd--js (format "(() => { const el = document.querySelector(%S); el.dispatchEvent(new PointerEvent('pointermove', {bubbles: true, clientX: 5, clientY: 5})); return getComputedStyle(el).cursor })()"
                                         selector)))))
      (should (equal (funcall move ".ToolIcon__icon") "pointer"))
      (should (+test-wait-for (lambda () (equal (plist-get (+test-exd--state) :cursor) "hand")) 3))
      (funcall move "canvas.excalidraw__canvas.interactive")
      (should (+test-wait-for (lambda () (equal (plist-get (+test-exd--state) :cursor) "arrow")) 3)))))

;; ====== A PNG ======

(defun +test-exd--png-size (file)
  "PNG FILE's width and height (its IHDR)."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (should (equal (buffer-substring 1 9) "\211PNG\r\n\032\n"))
    (cl-flet ((u32 (pos) (let ((n 0))
                           (dotimes (i 4) (setq n (+ (* n 256) (char-after (+ pos i)))))
                           n)))
      (cons (u32 17) (u32 21)))))

(ert-deftest e2e-exd/a-png-of-the-drawing ()
  "Nothing drawn: none. Drawn: a PNG, `+my/excalidraw-png-scale' times its
size."
  (+test-exd
    (let* ((file (+test-exd--file "fig.excalidraw.svg"))
           (png (expand-file-name "fig.png" (file-name-directory file))))
      (+test-exd--open file)
      (should (equal (cadr (should-error (+my/excalidraw-png png) :type 'user-error)) "Nothing is drawn"))
      (should-not (file-exists-p png))
      (+test-exd--add +test-exd--two-shapes)
      (let* ((one (let ((+my/excalidraw-png-scale 1))
                    (should (equal (+my/excalidraw-png png) png))
                    (+test-exd--png-size png)))
             (two (progn (should (equal (+my/excalidraw-png png) png))
                         (+test-exd--png-size png))))
        ;; The shapes span 290 x 80 px, with Excalidraw's padding around.
        (should (<= 290 (car one) 400))
        (should (<= 80 (cdr one) 200))
        (should (= +my/excalidraw-png-scale 2))
        (should (equal two (cons (* 2 (car one)) (* 2 (cdr one))))))
      (set-buffer-modified-p nil))))

(ert-deftest e2e-exd/another-drawing-shown-instead ()
  "`+my/excalidraw-replace': another drawing, shown and saved as this one's."
  (+test-exd
    (let ((other (+test-exd--make (+test-exd--file "other.excalidraw.svg")
                                  "[{type: 'ellipse', x: 0, y: 0, width: 50, height: 50}]"))
          (file (+test-exd--file "fig.excalidraw.svg")))
      (+test-exd--open file)
      (+test-exd--in-buffer (+test-exd--add "[{type: 'rectangle', x: 0, y: 0, width: 80, height: 40}]"))
      (save-buffer)
      (+my/excalidraw-replace (+test-exd--file-text other))
      (should (buffer-modified-p))
      (should (+test-wait-for (lambda () (equal (+test-exd--elements) '("ellipse"))) 5))
      (save-buffer)
      (kill-buffer)
      (+test-exd--open file)
      (should (equal (+test-exd--elements) '("ellipse")))
      (set-buffer-modified-p nil))))

;; ====== DRAWINGS FOR CLAUDE ======

(defmacro +test-exd--for-claude (&rest body)
  "BODY with an agent-shell stand-in, `shell' (its mode only, the selected
window's), drawings in `dir'/drawings/, and agent-shell's prompt stubbed:
`inserted' gets what's inserted, (SHELL TEXT)."
  (declare (indent 0))
  `(let* ((dir (file-truename (make-temp-file (+test-tmp-file "claude-") t)))
          (shell (generate-new-buffer "*test agent-shell*"))
          (inserted nil))
     (with-current-buffer shell
       (setq-local major-mode 'agent-shell-mode))
     (switch-to-buffer shell)
     (cl-letf (((symbol-function 'agent-shell--dot-subdir)
                (lambda (subdir) (let ((d (expand-file-name subdir dir))) (make-directory d t) d)))
               ((symbol-function 'agent-shell--get-files-context)
                (lambda (&rest args) (format "%S" (plist-get args :files))))
               ((symbol-function 'agent-shell-insert)
                (lambda (&rest args)
                  (push (list (plist-get args :shell-buffer) (plist-get args :text)) inserted))))
       (unwind-protect
           (progn ,@body)
         (kill-buffer shell)))))

(ert-deftest e2e-exd/drawn-for-claude-and-inserted ()
  "C-c C-d's drawing: on the shell's left, new; C-c C-c saves it, makes its
PNG, inserts it into the shell's prompt and closes it."
  (+test-exd
    (+test-exd--for-claude
      (let* ((from (selected-window))
             (drawing (+my/agent-shell-excalidraw))
             (file (buffer-file-name drawing))
             (png (concat (string-remove-suffix ".excalidraw.svg" file) ".png")))
        (should (eq (current-buffer) drawing))
        (should (eq (window-in-direction 'left from) (selected-window)))
        (should (equal (file-name-directory file) (file-name-as-directory (expand-file-name "drawings" dir))))
        (should +my/agent-shell-excalidraw-mode)
        (should (assq 'agent-shell-excalidraw +my/banner--list))
        (should (+test-exd--ready))
        (+test-exd--add +test-exd--two-shapes)
        ;; The key reaches it (not the page, not Evil).
        (execute-kbd-macro (kbd "C-c C-c"))
        (should-not (buffer-live-p drawing))
        (should-not (window-in-direction 'left from))
        (should (string-prefix-p "<svg" (+test-exd--file-text file)))
        (should (> (car (+test-exd--png-size png)) 290))
        (should (equal inserted (list (list shell (format "%S" (list png))))))))))

(ert-deftest e2e-exd/drawn-for-claude-in-the-left-window ()
  "With a file on the shell's left: the drawing in that window, the file
there again once it's inserted."
  (+test-exd
    (+test-exd--for-claude
      (let* ((code (find-file-noselect (+test-exd--file "code.py")))
             (left (selected-window))
             (right (split-window-right)))
        ;; The file on the left, the shell on the right (selected).
        (set-window-buffer right shell)
        (set-window-buffer left code)
        (select-window right)
        (let ((drawing (+my/agent-shell-excalidraw)))
          (should (eq (selected-window) left))
          (should (eq (window-buffer left) drawing))
          (should (= (length (window-list)) 2))
          (should (+test-exd--ready))
          (+test-exd--add +test-exd--two-shapes)
          (execute-kbd-macro (kbd "C-c C-c"))
          (should-not (buffer-live-p drawing))
          (should (window-live-p left))
          (should (eq (window-buffer left) code))
          (should (= (length inserted) 1)))))))

(ert-deftest e2e-exd/drawn-for-claude-and-discarded ()
  "C-c C-k: closed, its file deleted, nothing inserted."
  (+test-exd
    (+test-exd--for-claude
      (let* ((drawing (+my/agent-shell-excalidraw))
             (file (buffer-file-name drawing)))
        (should (+test-exd--ready))
        ;; Saved blank at once (a new drawing).
        (should (+test-wait-for (lambda () (file-exists-p file)) 5))
        (+test-exd--add +test-exd--two-shapes)
        (execute-kbd-macro (kbd "C-c C-k"))
        (should-not (buffer-live-p drawing))
        (should-not (file-exists-p file))
        (should-not inserted)))))

(ert-deftest e2e-exd/drawn-for-claude-from-an-earlier-one ()
  "M-p: an earlier drawing on the canvas; inserted, it's that one's PNG,
under this drawing's name."
  (+test-exd
    (+test-exd--for-claude
      (make-directory (expand-file-name "drawings" dir) t)
      (let ((earlier (+test-exd--make (expand-file-name "drawings/drawing-2000-01-01-00-00-00.excalidraw.svg" dir)
                                      "[{type: 'ellipse', x: 0, y: 0, width: 50, height: 50}]")))
        (switch-to-buffer shell)
        (let* ((drawing (+my/agent-shell-excalidraw))
               (file (buffer-file-name drawing)))
          (should (+test-exd--ready))
          (execute-kbd-macro (kbd "M-p"))
          (should (+test-wait-for (lambda () (equal (+test-exd--elements) '("ellipse"))) 5))
          (execute-kbd-macro (kbd "C-c C-c"))
          (should-not (buffer-live-p drawing))
          (should (equal (car (car inserted)) shell))
          ;; The earlier one untouched.
          (should (file-exists-p earlier))
          (find-file file)
          (should (+test-exd--ready))
          (should (equal (+test-exd--elements) '("ellipse")))
          (set-buffer-modified-p nil))))))
