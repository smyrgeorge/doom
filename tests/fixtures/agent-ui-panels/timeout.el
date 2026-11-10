;;; timeout.el --- a test panel whose query never ends -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :title "Orders" :text "")
 :fetch (lambda (panel) (agent-ui-panel-run panel '("sleep" "30") #'ignore :element "t" :timeout 0.3)))
