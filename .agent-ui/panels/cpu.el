;;; cpu.el --- Agent UI panel: this Mac's CPU (a demo) -*- lexical-binding: t; -*-
;; CPU and memory, their last minute, the load, and the processes using the
;; most CPU, every second: from sysctl, vm_stat and ps (macOS), one command
;; run without waiting, its output read here. CPU: the processes' %cpu (a
;; recent average, as ps has it) over the cores; memory: active, wired and
;; compressed pages over the Mac's own.
(agent-ui-panel
 :version 1
 :ui (:type "panel" :id "cpu-panel" :title "CPU (demo): this Mac, every second"
      :children
      ((:type "panel" :id "meters" :layout "row" :border :false
        :children ((:type "gauge" :id "cpu" :title "CPU" :unit "%" :value 0
                    :thresholds ((:at 0 :face "success") (:at 60 :face "warning") (:at 85 :face "error")))
                   (:type "gauge" :id "memory" :title "Memory" :unit "%" :value 0
                    :thresholds ((:at 0 :face "success") (:at 75 :face "warning") (:at 90 :face "error")))
                   (:type "stats" :id "load"
                    :figures ((:label "Load 1m" :value 0 :good "none") (:label "5m" :value 0 :good "none")
                              (:label "Tasks" :value 0 :good "none")))))
       (:type "panel" :id "history" :layout "row" :border :false
        :children ((:type "chart" :id "cpu-history" :title "CPU, the last minute" :unit "%"
                    :values () :window 60 :min 0 :max 100 :height 5)
                   (:type "chart" :id "memory-history" :title "Memory, the last minute" :unit "%"
                    :values () :window 60 :min 0 :max 100 :height 5)))
       (:type "table" :id "processes" :title "Top processes by CPU"
        :columns ("PID" "Command" "CPU %" "MEM %" "Memory")
        :align ("right" "left" "right" "right" "right"))))
 :every 1
 :fetch
 (lambda (panel)
   (agent-ui-panel-run
    panel (concat "sysctl -n hw.ncpu hw.memsize vm.loadavg; echo ---; vm_stat; echo ---; "
                  "ps -A -r -o pid=,pcpu=,pmem=,rss=,comm=")
    (lambda (out)
      (cl-labels
          ((number (regexp text)
             (if (string-match regexp text) (string-to-number (match-string 1 text)) 0))
           (one-decimal (n) (/ (round (* n 10)) 10.0))
           (size (kb) (if (>= kb 1048576)
                          (format "%.1f G" (/ kb 1048576.0))
                        (format "%d M" (round (/ kb 1024.0)))))
           (process (line)
             (when (string-match (concat "\\`[ \t]*\\([0-9]+\\)[ \t]+\\([0-9.]+\\)[ \t]+\\([0-9.]+\\)"
                                         "[ \t]+\\([0-9]+\\)[ \t]+\\(.*\\)\\'")
                                 line)
               (list (match-string 1 line)
                     (string-to-number (match-string 2 line))
                     (string-to-number (match-string 3 line))
                     (string-to-number (match-string 4 line))
                     (file-name-nondirectory (match-string 5 line))))))
        (pcase-let* ((`(,system ,vm ,ps) (split-string out "\n---\n"))
                     (`(,cores ,total ,load) (split-string system "\n" t))
                     (loads (split-string load "[{} ]+" t))
                     (page (number "page size of \\([0-9]+\\)" vm))
                     (used (* page (+ (number "Pages active: +\\([0-9]+\\)" vm)
                                      (number "Pages wired down: +\\([0-9]+\\)" vm)
                                      (number "Pages occupied by compressor: +\\([0-9]+\\)" vm))))
                     (memory (one-decimal (/ (* 100.0 used) (max 1 (string-to-number total)))))
                     (processes (delq nil (mapcar #'process (split-string ps "\n" t))))
                     (cpu (one-decimal (min 100.0 (/ (apply #'+ (mapcar #'cadr processes))
                                                     (max 1 (string-to-number cores)))))))
          (agent-ui-panel-update panel "cpu" :value cpu)
          (agent-ui-panel-update panel "memory" :value memory)
          (agent-ui-panel-update
           panel "load"
           :figures (list (list :label "Load 1m" :value (string-to-number (or (nth 0 loads) "0")) :good "none")
                          (list :label "5m" :value (string-to-number (or (nth 1 loads) "0")) :good "none")
                          (list :label "Tasks" :value (length processes) :good "none")))
          (agent-ui-panel-append panel "cpu-history" :values (list cpu))
          (agent-ui-panel-append panel "memory-history" :values (list memory))
          (agent-ui-panel-update
           panel "processes"
           :rows (mapcar (pcase-lambda (`(,pid ,pcpu ,pmem ,rss ,command))
                           (list pid (truncate-string-to-width command 40 nil nil "…")
                                 (one-decimal pcpu) (one-decimal pmem) (size rss)))
                         (seq-take processes 12)))))))))
