;;; frozen.el --- a test panel whose fetch waits itself -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :text "")
 :fetch (lambda (_panel) (sleep-for 0.25)))
