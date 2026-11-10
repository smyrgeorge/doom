;;; sourced.el --- a test panel with a source and a script -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "panel" :id "p"
      :children ((:type "text" :id "log" :text "" :source (:poll "echo hi" :every 60 :tail 1))))
 :fetch (lambda (_panel) (push 'fetch +test-aup-calls)))
