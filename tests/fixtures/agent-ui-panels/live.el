;;; live.el --- a test panel, filled by its script -*- lexical-binding: t; -*-
(agent-ui-panel
 :version 1
 :ui (:type "panel" :id "live"
      :children ((:type "table" :id "runs" :columns ("Run" "Status") :key "Run")
                 (:type "chart" :id "errors" :values ())
                 (:type "text" :id "where" :text "")))
 :every 0.2
 :start (lambda (_panel) (push 'start +test-aup-calls))
 :stop (lambda (_panel) (push 'stop +test-aup-calls))
 :fetch (lambda (panel)
          (push 'fetch +test-aup-calls)
          (agent-ui-panel-update panel "where" :text default-directory)
          (agent-ui-panel-append panel "errors" :values (list 3))
          (agent-ui-panel-run
           panel '("printf" "[{\"run\":\"#812\",\"ok\":true},{\"run\":\"#811\",\"ok\":false}]")
           (lambda (runs)
             (agent-ui-panel-update
              panel "runs"
              :rows (mapcar (lambda (r) (list (alist-get 'run r) (if (alist-get 'ok r) "passed" "failed")))
                            runs))))))
