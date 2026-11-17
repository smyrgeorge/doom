;;; tests/helper-agent-workspace.el -*- lexical-binding: t; -*-
;; What the agent workspace's tests share: the four first starters alone
;; (builder, investigator, reviewer, scribe, as they were: copies in
;; tests/fixtures/agent-workspace/starters/), for the tests of how roles are
;; listed, picked and checked, so a starter added doesn't change what they
;; expect. The starters themselves are tested as they ship
;; (test-agent-workspace-roles.el). Loaded by each test file using it, after
;; tests/helper.el and config/agent-workspace.el.

(defconst +test-aw-four-starters
  (expand-file-name "fixtures/agent-workspace/starters/" (file-name-directory (or load-file-name buffer-file-name)))
  "The four first starters, as they were.")

(defmacro +test-aw-with-four-starters (&rest body)
  "BODY with only the four first starters, the roles read anew."
  (declare (indent 0))
  `(let ((agent-workspace-starter-roles-directory +test-aw-four-starters)
         (agent-workspace--roles-cache (make-hash-table :test #'equal)))
     ,@body))
