;;; tests/unit/test-agent-ui-staging.el -*- lexical-binding: t; -*-
;; config/agent-ui/staging.el and review.el: types the agent makes. Staged
;; (checked, compiled, loaded, its example drawn), refused when wrong (nothing
;; left of it), used at once; reviewed: listed, previewed, kept (loaded from
;; its new folder at the next start, an issue filed), discarded (its elements
;; removed). Staging and kept folders of the tests' own.

(+test-load "config/agent-ui")

;; ====== HELPERS ======

(defconst +test-aus-dial
  "(defun agent-ui-dial--text (props _ctx)
  (format \"[%s%s] %d%%\"
          (make-string (/ (plist-get props :value) 10) ?#)
          (make-string (- 10 (/ (plist-get props :value) 10)) ?.)
          (plist-get props :value)))

(agent-ui-define dial
  \"A dial: VALUE percent.\"
  :props ((value integer \"Percent\" :default 0))
  :example (:value 42)
  :text #'agent-ui-dial--text)
"
  "A right type's code.")

(defvar +test-aus-kept nil "What `agent-ui-kept-functions' was called with.")

(defmacro +test-aus (&rest body)
  "BODY with staging and kept folders of its own, the types as they were
after (the tests' forgotten), no window shown, a canvas of its own."
  (declare (indent 0))
  `(let* ((agent-ui-staging-directory (file-name-as-directory (make-temp-file (+test-tmp-file "staged-") t)))
          (agent-ui-kept-directory (file-name-as-directory (make-temp-file (+test-tmp-file "kept-") t)))
          (agent-ui--types (copy-hash-table agent-ui--types))
          (agent-ui-default-canvas (make-temp-name "staging-"))
          (agent-ui-display-function #'ignore)
          (agent-ui-kept-functions (list (lambda (&rest args) (push args +test-aus-kept))))
          (+test-aus-kept nil)
          (before (buffer-list)))
     (unwind-protect (progn ,@body)
       (dolist (b (buffer-list))
         (unless (memq b before) (kill-buffer b))))))

(defun +test-aus-refused (code)
  "Why CODE is refused; nothing of it left."
  (let ((types (agent-ui-types)))
    (prog1 (agent-ui-error-message (should-error (agent-ui-stage code) :type 'agent-ui-error))
      (should (equal (agent-ui-types) types))
      (should-not (agent-ui-staged-files)))))

;; ====== STAGING ======

(ert-deftest agent-ui-staging/a-type-staged ()
  (+test-aus
    (let ((reply (agent-ui-stage +test-aus-dial)))
      (should (equal (plist-get reply :type) "dial"))
      (should (equal (plist-get reply :file) (expand-file-name "dial.el" agent-ui-staging-directory)))
      ;; Its example drawn, for the agent to see.
      (should (equal (plist-get reply :preview) "[####......] 42%"))
      (should (equal (plist-get reply :warnings) [])))
    ;; In the folder, with lexical binding; usable at once, as any type.
    (should (equal (agent-ui-staged-files) (list (expand-file-name "dial.el" agent-ui-staging-directory))))
    (should (string-prefix-p ";;; dial.el --- Agent UI type dial, made by the agent -*- lexical-binding: t; -*-"
                             (with-temp-buffer (insert-file-contents (car (agent-ui-staged-files)))
                                               (buffer-string))))
    (should (agent-ui-staged-p 'dial))
    (should-not (agent-ui-staged-p 'progress))
    (agent-ui-show '(:id "g" :type "dial" :value 70))
    (with-current-buffer (agent-ui-canvas)
      (should (string-prefix-p "[#######...] 70%" (buffer-string))))
    ;; Again, changed: replaces it, its elements redrawn.
    (agent-ui-stage (replace-regexp-in-string "%d%%" "%d percent" +test-aus-dial))
    (with-current-buffer (agent-ui-canvas)
      (agent-ui--flush)
      (should (string-prefix-p "[#######...] 70 percent" (buffer-string))))))

(ert-deftest agent-ui-staging/its-warnings-said ()
  (+test-aus
    (let ((reply (agent-ui-stage "(defun agent-ui-odd--text (props ctx) (format \"%s\" (plist-get props :v)))
(agent-ui-define odd \"Odd.\" :props ((v integer \"V\" :default 1)) :example (:v 2)
  :text #'agent-ui-odd--text)")))
      (should (equal (plist-get reply :preview) "2"))
      (should (seq-some (lambda (w) (string-match-p "\\`line 1: Unused lexical argument .ctx." w))
                        (plist-get reply :warnings))))))

(ert-deftest agent-ui-staging/wrong-code-refused ()
  (+test-aus
    (should (string-match-p "ends inside a form" (+test-aus-refused "(agent-ui-define x \"X.\"")))
    (should (string-match-p "one type (one agent-ui-define), not 0"
                            (+test-aus-refused "(defun agent-ui-x--a () 1)")))
    (should (string-match-p "one type (one agent-ui-define), not 2"
                            (+test-aus-refused "(agent-ui-define a \"A.\" :text #'ignore) (agent-ui-define b \"B.\" :text #'ignore)")))
    (should (string-match-p "only definitions belong in a type's code, not (setq foo 1)"
                            (+test-aus-refused "(setq foo 1) (agent-ui-define x \"X.\" :text #'ignore)")))
    (should (string-match-p "defun is named my-helper: a type's definitions are named agent-ui-x-"
                            (+test-aus-refused "(defun my-helper () 1) (agent-ui-define x \"X.\" :text #'ignore)")))
    (should (string-match-p "require only cl-lib.*, not url"
                            (+test-aus-refused "(require 'url) (agent-ui-define x \"X.\" :text #'ignore)")))
    (should (string-match-p "a type's name is a symbol"
                            (+test-aus-refused "(agent-ui-define \"x\" \"X.\" :text #'ignore)")))
    ;; One there already, not the agent's.
    (should (string-match-p "progress is a type already"
                            (+test-aus-refused "(agent-ui-define progress \"P.\" :text #'ignore :example ())")))
    ;; It must compile, load, have an example that draws.
    (should (string-match-p "doesn't compile"
                            (+test-aus-refused "(agent-ui-define x \"X.\" :text (lambda (p c) (let ((a)) . 1)) :example ())")))
    (should (string-match-p "has no :example"
                            (+test-aus-refused "(agent-ui-define x \"X.\" :text (lambda (_p _c) \"\"))")))
    (should (string-match-p "its example doesn't draw: ⚠ Boom"
                            (+test-aus-refused "(agent-ui-define x \"X.\" :text (lambda (_p _c) (error \"Boom\")) :example (:title nil))")))
    (should (string-match-p "kind numbr"
                            (+test-aus-refused "(agent-ui-define x \"X.\" :props ((a numbr \"A\")) :text (lambda (_p _c) \"\") :example ())")))))

(ert-deftest agent-ui-staging/a-wrong-change-keeps-the-one-there ()
  (+test-aus
    (agent-ui-stage +test-aus-dial)
    (should (string-match-p "doesn't draw"
                            (agent-ui-error-message
                             (should-error (agent-ui-stage "(agent-ui-define dial \"G.\" :text (lambda (_p _c) (error \"no\")) :example (:title \"t\"))")
                                           :type 'agent-ui-error))))
    ;; The one staged before, still.
    (should (equal (agent-ui-render '(:type "dial" :value 10) (agent-ui-context)) "[#.........] 10%"))
    (should (agent-ui-staged-p 'dial))))

;; ====== KEEPING, DISCARDING ======

(ert-deftest agent-ui-staging/kept ()
  (+test-aus
    (agent-ui-stage +test-aus-dial)
    (let ((kept (agent-ui-keep 'dial)))
      (should (equal kept (expand-file-name "dial.el" agent-ui-kept-directory)))
      (should (file-exists-p kept))
      (should-not (agent-ui-staged-files))
      (should-not (agent-ui-staged-p 'dial))
      (should (equal (agent-ui-type-file (agent-ui-type 'dial)) kept))
      (should (equal +test-aus-kept (list (list 'dial kept))))
      ;; At the next start: loaded from there.
      (agent-ui-undefine 'dial)
      (agent-ui-load-kept)
      (should (equal (agent-ui-render '(:type "dial" :value 50) (agent-ui-context)) "[#####.....] 50%"))
      ;; Now it's a kept type: the agent can't stage another so named.
      (should (string-match-p "dial is a type already" (+test-aus-refused +test-aus-dial))))))

(ert-deftest agent-ui-staging/a-kept-type-failing-to-load-said ()
  (+test-aus
    (with-temp-file (expand-file-name "broken.el" agent-ui-kept-directory)
      (insert "(error \"Broken\")"))
    (let (said)
      (cl-letf (((symbol-function 'message) (lambda (&rest args) (push (apply #'format args) said))))
        (agent-ui-load-kept))
      (should (string-match-p "the kept type broken doesn't load: Broken" (car said))))))

(ert-deftest agent-ui-staging/discarded ()
  (+test-aus
    (agent-ui-stage +test-aus-dial)
    (agent-ui-show '(:id "g" :type "dial"))
    (agent-ui-show '(:id "t" :type "text" :text "stays"))
    (should (eq (agent-ui-discard 'dial) 'dial))
    (should-not (agent-ui-staged-files))
    (should-not (memq 'dial (agent-ui-types)))
    ;; Its elements gone; the others stay.
    (should (equal (mapcar (lambda (e) (plist-get e :id)) (agent-ui-elements)) '("t")))
    (should (string-match-p "no staged type dial"
                            (agent-ui-error-message (should-error (agent-ui-discard 'dial)
                                                                  :type 'agent-ui-error))))))

(ert-deftest agent-ui-staging/after-a-restart ()
  (+test-aus
    (agent-ui-stage +test-aus-dial)
    ;; A restart: the file waits, the type isn't loaded.
    (agent-ui-undefine 'dial)
    (should (agent-ui-staged-files))
    (should-not (agent-ui-staged-p 'dial))
    ;; Kept: loaded first.
    (agent-ui-keep 'dial)
    (should (agent-ui-type 'dial))))

;; ====== THE REVIEW ======

(ert-deftest agent-ui-staging/the-review-list ()
  (+test-aus
    (agent-ui-stage +test-aus-dial)
    (let ((buffer (save-window-excursion (agent-ui-review))))
      (with-current-buffer buffer
        (should (derived-mode-p 'agent-ui-review-mode))
        (should (equal (mapcar #'car tabulated-list-entries) '(dial)))
        (let ((columns (cadr (car tabulated-list-entries))))
          (should (equal (aref columns 0) "dial"))
          (should (equal (aref columns 2) "yes"))
          (should (equal (aref columns 3) "A dial: VALUE percent.")))
        (should (string-match-p "keep" (format "%s" header-line-format)))
        ;; Keys, with Evil and without.
        (should (eq (lookup-key agent-ui-review-mode-map "a") #'agent-ui-review-keep))
        (should (eq (lookup-key (evil-get-auxiliary-keymap agent-ui-review-mode-map 'normal) "x")
                    #'agent-ui-review-discard))))))

(ert-deftest agent-ui-staging/a-preview ()
  (+test-aus
    (agent-ui-stage +test-aus-dial)
    (let ((buffer (save-window-excursion (agent-ui-review-preview 'dial))))
      (with-current-buffer buffer
        (let ((text (buffer-substring-no-properties (point-min) (point-max))))
          (should (string-prefix-p "dial, made by the agent\nA dial: VALUE percent.\n" text))
          (should (string-match-p "  value +integer +Percent (default 0)" text))
          (should (string-match-p "Its example\n\\[####......\\] 42%" text))
          (should (string-match-p "(agent-ui-define dial" text)))
        (should (eq agent-ui-review--type 'dial))))))

(ert-deftest agent-ui-staging/kept-and-discarded-from-the-review ()
  (+test-aus
    (agent-ui-stage +test-aus-dial)
    (agent-ui-stage (replace-regexp-in-string "dial" "meter" +test-aus-dial))
    (save-window-excursion
      (agent-ui-review)
      (agent-ui-review-keep 'dial)
      (agent-ui-review-discard 'meter)
      (with-current-buffer agent-ui-review-buffer
        (should-not tabulated-list-entries)))
    (should (file-exists-p (expand-file-name "dial.el" agent-ui-kept-directory)))
    (should-not (memq 'meter (agent-ui-types)))))

(ert-deftest agent-ui-staging/the-canvas-says-so ()
  (+test-aus
    (agent-ui-show '(:id "t" :type "text" :text "x"))
    (with-current-buffer (agent-ui-canvas)
      ;; None waiting: no header line (not an empty one).
      (should-not header-line-format)
      (agent-ui-stage +test-aus-dial)
      (should (string-match-p "1 type made by the agent to review: dial" header-line-format))
      (should (eq (lookup-key agent-ui-canvas-mode-map "R") #'agent-ui-review))
      (agent-ui-discard 'dial)
      (agent-ui-review--refresh)
      (should-not header-line-format))))

;; The skill's example of a type: staged as the agent would.
(ert-deftest agent-ui-staging/the-skills-type-right ()
  (+test-aus
    (let* ((skill (+test-agent-ui-skill "references/custom-types.md"))
           (code (and (string-match "```elisp\n\\(\\(?:.\\|\n\\)*?\\)```" skill)
                      (match-string 1 skill)))
           (reply (agent-ui-stage code)))
      (should (equal (plist-get reply :type) "dial"))
      (should (equal (plist-get reply :warnings) []))
      (should (string-match-p "\\`\\[#+\\.+\\] 42%  disk\\'" (plist-get reply :preview)))
      (should (string-match-p "value must be from 0 to 100"
                              (agent-ui-error-message
                               (should-error (agent-ui-check "dial" '(:value 140)) :type 'agent-ui-error)))))))

;; ====== THE CONFIG ======

(ert-deftest agent-ui-staging/where ()
  (should (equal agent-ui-staging-directory (expand-file-name "agent-ui/staged/" doom-cache-dir)))
  (should (equal agent-ui-kept-directory (expand-file-name "config/agent-ui/kept/" doom-user-dir)))
  (should (memq #'+my/agent-ui-kept-issue agent-ui-kept-functions)))
