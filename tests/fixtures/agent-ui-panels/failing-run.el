;;; failing-run.el --- a test panel whose command fails -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :text "")
 :fetch (lambda (panel)
          (agent-ui-panel-run panel '("sh" "-c" "echo boom >&2; exit 3")
                              (lambda (_out) (push 'called +test-aup-calls)))))
