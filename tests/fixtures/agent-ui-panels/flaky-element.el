;;; flaky-element.el --- a test panel whose query fails until a file is there -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :title "Deploy" :text "")
 :every 0.2
 :fetch (lambda (panel)
          (agent-ui-panel-run panel '("sh" "-c" "test -f ok || { echo 'no ok yet' >&2; exit 1; }")
                              (lambda (_) (agent-ui-panel-update panel "t" :text "ok"))
                              :element "t")))
