;;; waiting.el --- a test panel whose fetch's command runs a while -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :text "")
 :every 0.1
 :fetch (lambda (panel)
          (push 'fetch +test-aup-calls)
          (agent-ui-panel-run panel '("sleep" "0.6") (lambda (_) (push 'done +test-aup-calls)))))
