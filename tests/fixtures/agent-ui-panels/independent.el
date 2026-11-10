;;; independent.el --- a test panel: a slow query and a fast one -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "panel" :id "p"
      :children ((:type "text" :id "slow" :title "Slow" :text "")
                 (:type "text" :id "fast" :title "Fast" :text "")))
 :every 0.1
 :fetch (lambda (panel)
          (agent-ui-panel-run panel '("sh" "-c" "sleep 1.5; echo slow done")
                              (lambda (out) (push 'slow +test-aup-calls)
                                (agent-ui-panel-update panel "slow" :text (string-trim out)))
                              :element "slow")
          (agent-ui-panel-run panel '("printf" "fast")
                              (lambda (out) (push 'fast +test-aup-calls)
                                (agent-ui-panel-update panel "fast" :text out))
                              :element "fast")))
