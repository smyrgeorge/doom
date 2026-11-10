;;; failing-update.el --- a test panel changing an element it hasn't -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :text "")
 :fetch (lambda (panel) (agent-ui-panel-update panel "nope" :text "x")))
