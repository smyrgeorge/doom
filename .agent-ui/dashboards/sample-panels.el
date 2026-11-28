;;; sample-panels.el --- Agent UI dashboard: Sample panels -*- lexical-binding: t; -*-
;; Five sample panels (a release, a service's health, a test suite, a review
;; queue, operations), saved from a session's canvas as they were shown. Static:
;; no code, nothing fetched.
(agent-ui-dashboard
 :version 1
 :ui (:type "panel" :id "sample-panels" :title "Sample panels" :layout "column" :children
            ((:id "p-release" :type "panel" :title "Release v2.4" :layout "row" :children
                  ((:id "p-release-build" :type "progress" :title "Build" :value 8 :max 12 :unit "targets" :label "linking")
                   (:id "p-release-plan" :type "steps" :title "Plan" :steps
                        ((:name "Run the tests" :status "done" :detail "412 passed" :seconds 38)
                         (:name "Build" :status "running") "Sign the binaries" "Publish to the registry" "Announce"))))
             (:id "p-health" :type "panel" :title "Service health" :children
                  ((:id "p-health-row" :type "panel" :layout "row" :border :false :children
                        ((:id "p-health-stats" :type "stats" :figures
                              ((:label "Requests" :value 18.4 :unit "k/min" :change 6.2)
                               (:label "Errors" :value 0.31 :unit "%" :change -0.12 :good "down")
                               (:label "p95" :value 142 :unit "ms" :change -18 :good "down")))
                         (:id "p-health-uptime" :type "gauge" :title "Uptime" :value 99.93 :unit "%" :target 99.9 :label
                              "last 30 days" :thresholds
                              ((:at 0 :face "error") (:at 99.5 :face "warning") (:at 99.9 :face "success")))))
                   (:id "p-health-latency" :type "chart" :title "p95 latency" :kind "bar" :unit "ms" :labels
                        ("mon" "tue" "wed" "thu" "fri" "sat" "sun") :values (160 148 190 152 142 98 104))))
             (:id "p-tests" :type "panel" :title "Test matrix" :layout "row" :weights (3 2) :children
                  ((:id "p-tests-table" :type "table" :title "Suites" :columns ("Suite" "Result" "Time") :key "Suite" :rows
                        (("lexer" "passed" "0.4s") ("parser" "passed" "1.2s") ("checker" "failed" "2.8s")
                         ("codegen" "passed" "3.1s") ("runtime" "running" nil)))
                   (:id "p-tests-os" :type "heatmap" :title "By OS" :rows ("lexer" "parser" "checker" "codegen") :columns
                        ("linux" "macos" "windows") :values
                        (("passed" "passed" "passed") ("passed" "flaky" "passed") ("failed" "passed" "skipped")
                         ("passed" "passed" "passed")))))
             (:id "p-review" :type "panel" :title "Code review" :children
                  ((:id "p-review-files" :type "files" :title "Changed files" :tree t :files
                        ((:path "src/parser.c" :status "changed" :added 12 :removed 3)
                         (:path "src/lexer.h" :status "added" :added 40)
                         (:path "tests/parser_test.c" :status "failing" :errors 2 :line 88)))
                   (:id "p-review-code" :type "code" :title "Where it fails" :language "c" :from 40 :code
                        "int parse_expr(Parser *p) {\n  Node *lhs = parse_term(p);\n  if (!lhs)\n    return NULL;\n  return parse_binary(p, lhs, 0);\n}"
                        :marks
                        ((:line 43 :kind "warning" :note "error not reported")
                         (:line 44 :kind "change" :note "new: precedence climbing")))))
             (:id "p-ops" :type "panel" :title "Pipeline" :children
                  ((:id "p-ops-ci" :type "timeline" :title "CI run #1842" :tasks
                        ((:name "build" :start 0 :duration 8) (:name "test-linux" :start 8 :duration 14)
                         (:name "test-macos" :start 8 :duration 11 :status "failed")
                         (:name "deploy" :start 22 :duration 4 :status "queued")))
                   (:id "p-ops-row" :type "panel" :layout "row" :border :false :weights (3 2) :children
                        ((:id "p-ops-log" :type "log" :title "server.log" :lines
                              "12:01:03 INFO  listening on :8080\n12:01:05 INFO  connected to db (pool 16)\n12:01:07 WARN  slow query: 1.2s\n12:01:09 ERROR db: connection refused\n12:01:10 INFO  retrying in 2s")
                         (:id "p-ops-tags" :type "tags" :title "Issues" :tags
                              ((:label "bug" :face "error" :count 12) (:label "feature" :face "success" :count 4)
                               (:label "P1" :face "warning" :count 2) (:label "docs" :face "muted" :count 7))))))))))
