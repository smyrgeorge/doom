;;; counted.el --- a test panel counting its fetches -*- lexical-binding: t; -*-
(agent-ui-panel
 :ui (:type "text" :id "t" :text "")
 :every 0.1
 :start (lambda (_panel) (push 'start +test-aup-calls))
 :stop (lambda (_panel) (push 'stop +test-aup-calls))
 :fetch (lambda (_panel) (push 'fetch +test-aup-calls)))
