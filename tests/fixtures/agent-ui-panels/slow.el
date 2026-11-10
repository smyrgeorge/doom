;;; slow.el --- a test panel whose command runs long -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :text "")
 :fetch (lambda (panel) (agent-ui-panel-run panel '("sleep" "30") #'ignore)))
