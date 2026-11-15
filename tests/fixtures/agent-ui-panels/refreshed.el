;;; refreshed.el --- a test panel whose query is quick, slow once a file is there -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :title "Orders" :text "")
 :fetch (lambda (panel)
          (agent-ui-panel-run panel '("sh" "-c" "if test -f slow; then sleep 2; fi; echo orders")
                              (lambda (out) (push 'done +test-aup-calls)
                                (agent-ui-panel-update panel "t" :text (string-trim out)))
                              :element "t")))
