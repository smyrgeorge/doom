;;; tests/unit/test-agent-workflow-skill.el -*- lexical-binding: t; -*-
;; skills/agent-workflow: its SKILL.md (its front matter, under 12 KB), every
;; workflow and agent in it and its references checked as the check does
;; (none with an error), and the line every agent-shell session is told.

(+test-load "config/agent-workflow")

(defconst +test-awk-skill (expand-file-name "skills/agent-workflow/" +test-root))

(defun +test-awk--blocks (language)
  "Every LANGUAGE code block of the skill's files: ((FILE . TEXT)...)."
  (let (blocks)
    (dolist (file (cons (expand-file-name "SKILL.md" +test-awk-skill)
                        (directory-files (expand-file-name "references" +test-awk-skill) t "\\.md\\'")))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward (concat "^```" language "\n") nil t)
          (let ((start (point)))
            (re-search-forward "^```$")
            (push (cons (file-name-nondirectory file) (buffer-substring start (match-beginning 0))) blocks)))))
    (nreverse blocks)))

(ert-deftest agent-workflow-skill/its-skill-md ()
  "Its front matter (name, description), under 12 KB, every reference it
points to there."
  (let ((text (with-temp-buffer (insert-file-contents (expand-file-name "SKILL.md" +test-awk-skill)) (buffer-string))))
    (should (string-prefix-p "---\nname: agent-workflow\ndescription: >-\n" text))
    (should (< (string-bytes text) 12000))
    (let ((start 0))
      (while (string-match "(\\(references/[a-z-]+\\.md\\))" text start)
        (should (file-exists-p (expand-file-name (match-string 1 text) +test-awk-skill)))
        (setq start (match-end 0))))))

(ert-deftest agent-workflow-skill/its-workflows-check ()
  "Every workflow in it checks with no error, against the starters'
agents."
  (let ((definitions (let ((agent-workflow--definitions-cache (make-hash-table :test #'equal)))
                    (mapcar #'car (agent-workflow-agent-definitions nil))))
        (dir (make-temp-file (+test-tmp-file "awk-") t))
        (checked 0))
    (should (member "build" definitions))
    (pcase-dolist (`(,file . ,text) (+test-awk--blocks "yaml"))
      (when (string-match-p "^jobs:" text)
        (let ((name (if (string-match "^name: \\([a-z0-9-]+\\)" text) (match-string 1 text) "example")))
          (pcase-let ((`(,workflow . ,problems)
                       (agent-workflow-workflow-read (+test-file (format "awk/%s.yml" name) text) definitions)))
            (ert-info ((format "%s: %s" file name))
              (should workflow)
              (should-not (assq 'error problems))
              (should-not (assq 'warning problems)))
            (cl-incf checked)))))
    (ignore dir)
    (should (>= checked 4))))

(ert-deftest agent-workflow-skill/its-definitions-check ()
  "Every agent in it checks with no error."
  (let ((checked 0))
    (pcase-dolist (`(,file . ,text) (+test-awk--blocks "markdown"))
      (when (string-prefix-p "---\n" text)
        (pcase-let ((`(,definition . ,problems) (agent-workflow-definition-read (+test-file "awk/agents/build.md" text))))
          (ert-info (file)
            (should definition)
            (should-not (assq 'error problems))))
        (cl-incf checked)))
    (should (>= checked 1))))

(ert-deftest agent-workflow-skill/every-session-told ()
  "Every agent-shell session is told where the skill is, while Emacs runs a
server."
  (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) t)))
    (let ((told (agent-workflow-skill-context)))
      (should (string-match-p "skills/agent-workflow/SKILL\\.md first\\.\\'" told))
      (should (string-match-p "cmd/agent-workflow" told))))
  (cl-letf (((symbol-function 'server-running-p) (lambda (&rest _) nil)))
    (should-not (agent-workflow-skill-context)))
  (should (file-exists-p agent-workflow-skill)))

;; ====== THE STEP'S ======

(ert-deftest agent-workflow-skill/the-step-s ()
  "skills/agent-workflow-step: its front matter, under 12 KB, its
reference there; a job's agent told where it is."
  (let* ((dir (expand-file-name "skills/agent-workflow-step/" +test-root))
         (text (with-temp-buffer (insert-file-contents (expand-file-name "SKILL.md" dir)) (buffer-string))))
    (should (string-prefix-p "---\nname: agent-workflow-step\ndescription: >-\n" text))
    (should (< (string-bytes text) 12000))
    (should (file-exists-p (expand-file-name "references/outcomes.md" dir)))
    (should (string-match-p "cmd/agent-workflow done changes" text)))
  (let* ((agent (agent-workflow-agent--make :project +test-root :issue "demo-1" :job "review" :definition "review"
                                            :worktree +test-root :branch "feat/demo-1" :outcomes '("approved" "changes")))
         (agent-workflow--starting agent)
         (agent-workflow--definitions-cache (make-hash-table :test #'equal))
         (told (agent-workflow-agent-context)))
    (should (string-match-p "skills/agent-workflow-step/SKILL\\.md first\\." told))
    (should (string-match-p "one of done, approved, changes" told))))

(ert-deftest agent-workflow-skill/its-commands-are-commands ()
  "Every M-x agent-workflow-... the docs, the skill and the code name is a
command (seven of them were functions, their commands NAME-command)."
  (let ((named nil))
    (dolist (file (append (list (expand-file-name "docs/agent-workflow.md" +test-root)
                                (expand-file-name "config/agent-workflow.el" +test-root))
                          (directory-files-recursively (expand-file-name "skills/agent-workflow" +test-root) "\\.md\\'")
                          (directory-files (expand-file-name "config/agent-workflow" +test-root) t "\\.el\\'")))
      (with-temp-buffer
        (insert-file-contents file)
        (while (re-search-forward "M-x \\(agent-workflow-[a-z-]*[a-z]\\)" nil t)
          (cl-pushnew (match-string 1) named :test #'equal))))
    (should (> (length named) 10))
    (should-not (seq-remove (lambda (name) (commandp (intern name))) named))))
