;;; read.el --- a test panel read by an agent: a short query each fetch -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :text "")
 :every 1
 :fetch (lambda (panel)
          (push 'fetch +test-aup-calls)
          (agent-ui-panel-run panel '("sh" "-c" "sleep 0.3; echo 42")
                              (lambda (out)
                                (push 'done +test-aup-calls)
                                (agent-ui-panel-update panel "t" :text (string-trim out)))
                              :element "t")))
