;;; tests/unit/test-spell.el -*- lexical-binding: t; -*-
;; config/editor/spell.el, config/editor.el's spelling settings: camelCase
;; identifiers checked word by word, the tech-words dictionary (dict/tech.txt)
;; in every spell-checked buffer, read-only so words added still go to the
;; personal dictionary, which is created if missing. aspell never runs: the
;; tests give spell-fu its dictionaries (files in the temp folder), and the
;; user's own dictionaries are never touched.

(defvar doom-disabled-packages nil)     ; `use-package!' reads it (Doom's)

;; Mocking a primitive (`call-process'...) mustn't natively compile a
;; trampoline for it: that runs another Emacs.
(setq native-comp-enable-subr-trampolines nil)

;; The personal dictionary, in a folder that doesn't exist yet (as Doom's under
;; .local/etc/ispell/ on a fresh install); spell-fu's files in the temp folder.
;; Both set before ispell / spell-fu load (their defcustoms keep them).
(defvar +test-spell--personal (expand-file-name "spell/fresh/ispell/en.pws" +test-tmp))
(setq ispell-personal-dictionary +test-spell--personal)
(setq spell-fu-directory (+test-tmp-file "spell/spell-fu/"))

(defvar +test-spell--before-ispell
  (list :ispell (featurep 'ispell)
        :exists (file-exists-p +test-spell--personal)))

(+test-load "config/editor")

(defvar +test-spell--after-config
  (list :ispell (featurep 'ispell)
        :exists (file-exists-p +test-spell--personal)))

(require 'ispell)                       ; runs the config's `after! ispell'

(defvar +test-spell--after-ispell
  (list :exists (file-exists-p +test-spell--personal)
        :contents (and (file-exists-p +test-spell--personal)
                       (with-temp-buffer
                         (insert-file-contents-literally +test-spell--personal)
                         (buffer-string)))))

(require 'spell-fu)

(defconst +test-spell--tech-file +my/spell-tech-words-file
  "The config's word list (dict/tech.txt).")

;; ====== HELPERS ======

(defun +test-spell--after-ispell-form ()
  "config/editor/spell.el's `after! ispell' form, read from the file (to run it again
under other conditions: ispell is loaded once)."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config/editor/spell.el" +test-root))
    (let (form found)
      (condition-case nil
          (while (not found)
            (setq form (read (current-buffer)))
            (when (and (eq (car-safe form) 'after!) (eq (cadr form) 'ispell))
              (setq found form)))
        (end-of-file))
      found)))

(defun +test-spell--run-after-ispell (dictionary)
  "Run the config's `after! ispell' with `ispell-personal-dictionary' DICTIONARY."
  (let ((ispell-personal-dictionary dictionary))
    (eval (+test-spell--after-ispell-form) t)))

(defun +test-spell--read (file)
  (with-temp-buffer
    (insert-file-contents-literally file)
    (buffer-string)))

(defun +test-spell--words (words)
  "A spell-fu words table with WORDS."
  (let ((table (make-hash-table :test #'equal)))
    (dolist (word words)
      (puthash (spell-fu--canonicalize-word word) t table))
    table))

(defun +test-spell--marked ()
  "The text spell-fu marked as misspelled in the current buffer, in order."
  (mapcar (lambda (ov) (buffer-substring-no-properties (overlay-start ov) (overlay-end ov)))
          (sort (seq-filter (lambda (ov) (overlay-get ov 'spell-fu-mode))
                            (overlays-in (point-min) (point-max)))
                (lambda (a b) (< (overlay-start a) (overlay-start b))))))

(defun +test-spell--check (text words)
  "Check TEXT (in a temp buffer) against WORDS; what's marked."
  (with-temp-buffer
    (insert text)
    (setq-local spell-fu--cache-table-list (list (+test-spell--words words)))
    (spell-fu--check-range-without-faces (point-min) (point-max))
    (+test-spell--marked)))

(defmacro +test-spell--no-programs (&rest body)
  "BODY, failing if anything starts a program (aspell...)."
  (declare (indent 0))
  `(cl-letf (((symbol-function 'call-process)
              (lambda (program &rest _) (error "Ran %s" program)))
             ((symbol-function 'process-file)
              (lambda (program &rest _) (error "Ran %s" program)))
             ((symbol-function 'make-process)
              (lambda (&rest args) (error "Started %S" (plist-get args :command))))
             ((symbol-function 'start-process)
              (lambda (_name _buffer program &rest _) (error "Started %s" program))))
     ,@body))

(defmacro +test-spell--with-tech (words &rest body)
  "BODY with the tech-words file a temp file of WORDS (a list; nil: a file
that doesn't exist), no tech dictionary made yet, spell-fu's files in a folder
of their own (its word list is named after the dictionary)."
  (declare (indent 1))
  `(let* ((dir (file-name-as-directory (make-temp-file (+test-tmp-file "spell/case-") t)))
          (+my/spell-tech-words-file (expand-file-name "tech.txt" dir))
          (+my/spell-tech-dictionary nil)
          (spell-fu-directory (expand-file-name "spell-fu/" dir)))
     (make-directory spell-fu-directory t)
     (when ,words
       (with-temp-file +my/spell-tech-words-file
         (insert (string-join ,words "\n") "\n")))
     ,@body))

(defun +test-spell--turned-on ()
  "spell-fu-mode-hook as spell-fu-mode turns on in this buffer."
  (setq-local spell-fu-mode t)
  (+my/spell-add-tech-words-h))

(defun +test-spell--personal-dictionary (dir &rest words)
  "A personal dictionary (aspell's format) in DIR with WORDS, as spell-fu
makes it; return the dictionary."
  (let ((file (expand-file-name "personal.pws" dir)))
    (with-temp-file file
      (insert "personal_ws-1.1 en 0\n")
      (dolist (word words) (insert word "\n")))
    (spell-fu-get-personal-dictionary (format "test-%s" (file-name-nondirectory
                                                         (directory-file-name dir)))
                                      file)))

(defun +test-spell--tech-p (dict)
  (equal (spell-fu--dict-get dict 'name) "spell-fu-tech-words"))

;; ====== CAMELCASE ======

(ert-deftest spell/camel-case-on ()
  (should (eq spell-fu-word-delimit-camel-case t))
  ;; spell-fu's default is off: the config turns it on (before spell-fu loads).
  (should (eq (eval (car (get 'spell-fu-word-delimit-camel-case 'standard-value)) t) nil)))

(ert-deftest spell/camel-case-identifiers-checked-word-by-word ()
  (should-not (+test-spell--check "AgreementController" '("agreement" "controller")))
  (should-not (+test-spell--check "agreementController" '("agreement" "controller")))
  (should-not (+test-spell--check "parseHttpRequest" '("parse" "http" "request"))))

(ert-deftest spell/camel-case-marks-only-the-misspelled-part ()
  (should (equal (+test-spell--check "AgreementControler" '("agreement" "controller"))
                 '("Controler")))
  (should (equal (+test-spell--check "AgrementController" '("agreement" "controller"))
                 '("Agrement"))))

(ert-deftest spell/camel-case-only-for-words-otherwise-misspelled ()
  "A word the dictionary knows whole isn't split (and so isn't marked)."
  (should-not (+test-spell--check "JavaScript" '("javascript"))))

(ert-deftest spell/camel-case-off-flags-the-whole-word ()
  "What the setting changes: without it, the identifier is one wrong word."
  (let ((spell-fu-word-delimit-camel-case nil))
    (should (equal (+test-spell--check "AgreementController" '("agreement" "controller"))
                   '("AgreementController")))))

(ert-deftest spell/camel-case-plain-words-still-checked ()
  "No case change to split on: checked whole, as before."
  (should (equal (+test-spell--check "Agreementcontroller" '("agreement" "controller"))
                 '("Agreementcontroller")))
  (should (equal (+test-spell--check "the speling" '("the" "spelling"))
                 '("speling"))))

(ert-deftest spell/camel-case-acronyms-left-alone ()
  "spell-fu ignores all-caps parts (HTTP), split or not."
  (should-not (+test-spell--check "HTTPServer" '("server")))
  (should-not (+test-spell--check "XYZZY" nil)))

;; ====== TECH WORDS ======

(ert-deftest spell/tech-words-file-is-dict-tech-txt ()
  (should (equal (default-value '+my/spell-tech-words-file)
                 (expand-file-name "dict/tech.txt" doom-user-dir)))
  (should (equal doom-user-dir +test-root))
  (should (file-readable-p +my/spell-tech-words-file)))

(ert-deftest spell/tech-words-file-one-word-per-line ()
  "~40k words, one per line, no header, among them the ones the docs name."
  (let ((text (+test-spell--read +my/spell-tech-words-file)))
    (let ((lines (split-string text "\n" t)))
      (should (> (length lines) 30000))
      (should-not (string-prefix-p "personal_ws-" (car lines)))
      (should-not (seq-find (lambda (line) (string-match-p "[ \t\r]" line)) lines))
      (dolist (word '("rect" "rgba" "async" "kotlin" "stdout" "postgres"))
        (should (member word lines))))))

(ert-deftest spell/tech-words-hook ()
  (should (memq #'+my/spell-add-tech-words-h (default-value 'spell-fu-mode-hook)))
  (should-not +my/spell-tech-dictionary))  ; made on first use only

(ert-deftest spell/tech-words-missing-file-does-nothing ()
  (+test-spell--with-tech nil
    (with-temp-buffer
      (setq-local spell-fu-dictionaries nil)
      (+test-spell--turned-on)
      (should-not spell-fu-dictionaries)
      (should-not +my/spell-tech-dictionary))))

(ert-deftest spell/tech-words-not-when-turned-off ()
  "The hook also runs as spell-fu-mode turns off: nothing added then. In a
buffer where it never was on, the tech words were its only dictionary, and
spell-fu, turned on, added English only to an empty list."
  (+test-spell--with-tech '("rgba")
    (with-temp-buffer
      (setq-local spell-fu-dictionaries nil)
      (setq-local spell-fu-mode nil)
      (+my/spell-add-tech-words-h)
      (should-not spell-fu-dictionaries)
      (should-not +my/spell-tech-dictionary))))

(ert-deftest spell/tech-words-dictionary ()
  "Read-only, from the word list (a one-word-per-line file, read as spell-fu
reads a personal dictionary)."
  (+test-spell--with-tech '("rgba" "kotlin")
    (with-temp-buffer
      (+test-spell--turned-on)
      (let ((dict +my/spell-tech-dictionary))
        (should dict)
        (should (equal (spell-fu--dict-get dict 'name) "spell-fu-tech-words"))
        (should (equal (spell-fu--dict-get dict 'description)
                       (format "Programming words from %s" +my/spell-tech-words-file)))
        (should (eq (spell-fu--dict-get dict 'update) #'spell-fu--personal-update))
        (should-not (spell-fu--dict-get dict 'add-word))
        (should-not (spell-fu--dict-get dict 'remove-word))
        (should-not (spell-fu--dict-get dict 'aspell-name))
        (should (equal (spell-fu--dict-get dict 'file) +my/spell-tech-words-file))
        (should (memq dict spell-fu-dictionaries))))))

(ert-deftest spell/tech-words-made-once-shared-by-buffers ()
  (+test-spell--with-tech '("rgba")
    (let ((made 0)
          (create (symbol-function 'spell-fu--dictionary-create)))
      (cl-letf (((symbol-function 'spell-fu--dictionary-create)
                 (lambda (&rest args) (cl-incf made) (apply create args))))
        (let ((a (+test-buffer "a.txt")) (b (+test-buffer "b.txt")))
          (unwind-protect
              (progn
                (with-current-buffer a (+test-spell--turned-on))
                (with-current-buffer b (+test-spell--turned-on))
                (should (= made 1))
                (should (eq (car (buffer-local-value 'spell-fu-dictionaries a))
                            (car (buffer-local-value 'spell-fu-dictionaries b))))
                (should (eq (car (buffer-local-value 'spell-fu-dictionaries a))
                            +my/spell-tech-dictionary)))
            (kill-buffer a) (kill-buffer b)))))))

(ert-deftest spell/tech-words-added-once-per-buffer ()
  "spell-fu-mode turned on again (e.g. a mode change) doesn't add it twice."
  (+test-spell--with-tech '("rgba")
    (with-temp-buffer
      (+test-spell--turned-on)
      (+test-spell--turned-on)
      (should (= (length (seq-filter #'+test-spell--tech-p spell-fu-dictionaries)) 1)))))

(ert-deftest spell/tech-words-next-to-the-others ()
  "Added to the buffer's dictionaries (English, personal), not instead."
  (+test-spell--with-tech '("rgba")
    (with-temp-buffer
      (let ((english (spell-fu-get-ispell-dictionary "en_test"))
            (personal (+test-spell--personal-dictionary (file-name-directory +my/spell-tech-words-file))))
        (setq-local spell-fu-dictionaries (list english personal))
        (+test-spell--turned-on)
        (should (= (length spell-fu-dictionaries) 3))
        (should (memq english spell-fu-dictionaries))
        (should (memq personal spell-fu-dictionaries))
        (should (memq +my/spell-tech-dictionary spell-fu-dictionaries))))))

(ert-deftest spell/tech-words-only-in-spell-checked-buffers ()
  "Through spell-fu-mode's hook: a buffer without spell-fu doesn't get it."
  (+test-spell--with-tech '("rgba")
    (with-temp-buffer
      (should-not spell-fu-mode)
      (should-not spell-fu-dictionaries))))

;; ====== IN SPELL-FU ======

(defmacro +test-spell--in-spell-fu (words personal-words &rest body)
  "BODY in a text buffer with spell-fu on, its dictionaries: a personal one
with PERSONAL-WORDS, and (the hook) the tech words WORDS. No aspell."
  (declare (indent 2))
  `(+test-spell--with-tech ,words
     (let ((personal (apply #'+test-spell--personal-dictionary
                            (file-name-directory +my/spell-tech-words-file) ,personal-words))
           (buffer (+test-buffer "notes.txt" nil #'text-mode)))
       (unwind-protect
           (with-current-buffer buffer
             (setq-local spell-fu-dictionaries (list personal))
             (+test-spell--no-programs
               (let ((inhibit-message t))
                 (spell-fu-mode 1))
               ,@body))
         (with-current-buffer buffer (spell-fu-mode -1))
         (kill-buffer buffer)))))

(ert-deftest spell/tech-words-loaded-when-spell-fu-starts ()
  (+test-spell--in-spell-fu '("rgba" "kotlin" "stdout") '("frobnicate")
    (let ((tech (seq-find #'+test-spell--tech-p spell-fu-dictionaries)))
      (should tech)
      (should (eq tech +my/spell-tech-dictionary))
      (should (hash-table-p (spell-fu--dict-words tech)))
      (dolist (word '("rgba" "kotlin" "stdout"))
        (should (gethash (spell-fu--canonicalize-word word) (spell-fu--dict-words tech))))
      ;; Its words are what spell-fu checks against.
      (should (memq (spell-fu--dict-words tech) spell-fu--cache-table-list))
      (should (= (length spell-fu--cache-table-list) 2)))))

(ert-deftest spell/tech-words-not-marked ()
  (+test-spell--in-spell-fu '("rgba" "kotlin" "stdout") '("frobnicate")
    (insert "rgba kotlin stdout frobnicate zzqx kotlinStdout")
    (spell-fu--check-range-without-faces (point-min) (point-max))
    (should (equal (+test-spell--marked) '("zzqx")))))

(ert-deftest spell/words-added-go-to-the-personal-dictionary ()
  "zg / Option+Enter's \"Add to dictionary\": the personal dictionary, without
asking which (the tech words are read-only)."
  (+test-spell--in-spell-fu '("rgba") nil
    (let ((candidates (spell-fu--get-edit-candidate-dictionaries "frobnicate" 'add)))
      (should (= (length candidates) 1))
      (should-not (+test-spell--tech-p (car candidates))))
    (insert "frobnicate")
    (goto-char 3)
    (let ((completing-read-function (lambda (&rest _) (error "Asked which dictionary"))))
      (call-interactively #'spell-fu-word-add))
    (let ((file (spell-fu--dict-get (car (spell-fu--get-edit-candidate-dictionaries "other" 'add))
                                    'file)))
      (should (string-match-p "^frobnicate$" (+test-spell--read file))))
    ;; The word list itself is untouched.
    (should (equal (+test-spell--read +my/spell-tech-words-file) "rgba\n"))))

(ert-deftest spell/tech-words-cannot-be-removed ()
  (+test-spell--in-spell-fu '("kotlin") nil
    (should-not (spell-fu--get-edit-candidate-dictionaries "kotlin" 'remove))))

(ert-deftest spell/real-tech-words ()
  "dict/tech.txt itself, through spell-fu (read only; spell-fu's own files in
the temp folder)."
  (+test-spell--with-tech nil
    (let ((+my/spell-tech-words-file +test-spell--tech-file)
          (before (file-attribute-modification-time (file-attributes +test-spell--tech-file))))
      (with-temp-buffer
        (+test-spell--no-programs
          (let ((inhibit-message t))
            (+test-spell--turned-on)
            (spell-fu--dictionary-ensure-update +my/spell-tech-dictionary)))
        (let ((words (spell-fu--dict-words +my/spell-tech-dictionary)))
          (should (> (hash-table-count words) 30000))
          (dolist (word '("aa" "rect" "rgba" "async" "kotlin" "stdout" "postgres"))
            (should (gethash (spell-fu--canonicalize-word word) words)))))
      (should (equal (file-attribute-modification-time
                      (file-attributes +my/spell-tech-words-file))
                     before))
      ;; spell-fu wrote its word list and cache in its folder (the temp one).
      (should (file-exists-p (expand-file-name "words_spell-fu-tech-words.txt" spell-fu-directory))))))

;; ====== PERSONAL DICTIONARY ======

(ert-deftest spell/personal-dictionary-created-when-ispell-loads ()
  "Missing (and its folder too) when ispell loads: created, empty, in aspell's
format."
  (should-not (plist-get +test-spell--before-ispell :ispell))
  (should-not (plist-get +test-spell--before-ispell :exists))
  ;; Not by loading the config: only once ispell loads.
  (should-not (plist-get +test-spell--after-config :ispell))
  (should-not (plist-get +test-spell--after-config :exists))
  (should (plist-get +test-spell--after-ispell :exists))
  (should (equal (plist-get +test-spell--after-ispell :contents) "personal_ws-1.1 en 0\n")))

(ert-deftest spell/personal-dictionary-nested-folder-made ()
  (let ((file (expand-file-name (format "spell/new-%s/a/b/c/en.pws" (random 100000)) +test-tmp)))
    (should-not (file-exists-p (file-name-directory file)))
    (+test-spell--run-after-ispell file)
    (should (file-directory-p (file-name-directory file)))
    (should (equal (+test-spell--read file) "personal_ws-1.1 en 0\n"))))

(ert-deftest spell/personal-dictionary-folder-exists-file-missing ()
  (let* ((dir (make-temp-file (+test-tmp-file "spell/dir-") t))
         (file (expand-file-name "en.pws" dir)))
    (+test-spell--run-after-ispell file)
    (should (equal (+test-spell--read file) "personal_ws-1.1 en 0\n"))))

(ert-deftest spell/personal-dictionary-existing-untouched ()
  (let* ((file (+test-file "spell/existing/en.pws" "personal_ws-1.1 en 2\nfoo\nbar\n"))
         (time (file-attribute-modification-time (file-attributes file))))
    (+test-spell--run-after-ispell file)
    (should (equal (+test-spell--read file) "personal_ws-1.1 en 2\nfoo\nbar\n"))
    (should (equal (file-attribute-modification-time (file-attributes file)) time))))

(ert-deftest spell/personal-dictionary-existing-empty-untouched ()
  "An empty file is the user's: left as it is."
  (let ((file (+test-file "spell/empty/en.pws" "")))
    (+test-spell--run-after-ispell file)
    (should (equal (+test-spell--read file) ""))))

(ert-deftest spell/personal-dictionary-none-set ()
  "No personal dictionary set (no aspell): nothing to create, no error."
  (let ((files (directory-files-recursively +test-tmp "" t)))
    (+test-spell--run-after-ispell nil)
    (should (equal (directory-files-recursively +test-tmp "" t) files))))

(ert-deftest spell/personal-dictionary-runs-after-ispell-loads ()
  "The config waits for ispell (Doom's spell module sets the dictionary's path
when ispell loads, before the config's `after!' runs)."
  (let ((form (+test-spell--after-ispell-form)))
    (should form)
    (should (eq (cadr form) 'ispell))))

(ert-deftest spell/personal-dictionary-created-is-used-by-spell-fu ()
  "Why: spell-fu ignores a personal dictionary file that doesn't exist, so
adding a word failed (\"Cannot add ... to any active dictionary\")."
  (let* ((dir (make-temp-file (+test-tmp-file "spell/use-") t))
         (file (expand-file-name "ispell/en.pws" dir))
         (spell-fu-directory (expand-file-name "spell-fu/" dir))
         (ispell-local-dictionary "en_test"))
    (make-directory spell-fu-directory t)
    (with-temp-buffer
      (let ((ispell-personal-dictionary file))
        (should-not (seq-find (lambda (d) (equal (spell-fu--dict-get d 'file) file))
                              (spell-fu--default-dictionaries))))
      (+test-spell--run-after-ispell file)
      (let* ((ispell-personal-dictionary file)
             (personal (seq-find (lambda (d) (equal (spell-fu--dict-get d 'file) file))
                                 (spell-fu--default-dictionaries))))
        (should personal)
        (let ((inhibit-message t))
          (spell-fu--dictionary-ensure-update personal)
          (should (spell-fu-word-add personal "frobnicate")))
        (should (equal (+test-spell--read file) "personal_ws-1.1 en 1\nfrobnicate\n"))))))
