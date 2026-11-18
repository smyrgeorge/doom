;;; tests/helper-agent-workspace.el -*- lexical-binding: t; -*-
;; What the agent workspace's tests share: the four first starters alone
;; (builder, investigator, reviewer, scribe, as they were: copies in
;; tests/fixtures/agent-workspace/starters/), for the tests of how roles are
;; listed, picked and checked, so a starter added doesn't change what they
;; expect; and two starter crews of them (pair: scribe, builder; review:
;; scribe, builder 2, reviewer; in tests/fixtures/agent-workspace/crews/), the
;; shipped ones naming roles they don't have. The starters themselves are
;; tested as they ship (test-agent-workspace-roles.el,
;; test-agent-workspace-crews.el). Loaded by each test file using it, after
;; tests/helper.el and config/agent-workspace.el.

(defconst +test-aw-four-starters
  (expand-file-name "fixtures/agent-workspace/starters/" (file-name-directory (or load-file-name buffer-file-name)))
  "The four first starters, as they were.")

(defconst +test-aw-two-crews
  (expand-file-name "fixtures/agent-workspace/crews/" (file-name-directory (or load-file-name buffer-file-name)))
  "Two starter crews of the four first starters: pair, review.")

(defmacro +test-aw-with-four-starters (&rest body)
  "BODY with only the four first starters and two crews of them, the roles
and crews read anew."
  (declare (indent 0))
  `(let ((agent-workspace-starter-roles-directory +test-aw-four-starters)
         (agent-workspace-starter-crews-directory +test-aw-two-crews)
         (agent-workspace--roles-cache (make-hash-table :test #'equal))
         (agent-workspace--crew-specs-cache (make-hash-table :test #'equal)))
     ,@body))
