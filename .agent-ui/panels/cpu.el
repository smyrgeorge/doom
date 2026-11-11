;;; cpu.el --- Agent UI panel: this machine's CPU (a demo) -*- lexical-binding: t; -*-
;; The CPU: how busy, its load, its last minute, and the processes using it
;; most, every second: one command run without waiting, its output read here.
;; macOS: sysctl and ps, busy the processes' %cpu (a recent average, as ps has
;; it) over the cores. Linux: nproc, /proc/loadavg and ps (its %cpu each
;; process's average over its life), busy from /proc/stat since the last
;; fetch (since boot, the first time). Memory: the memory panel's.
(agent-ui-panel
 :version 1
 :ui (:type "panel" :id "cpu-panel" :title "CPU (demo): this machine, every second"
      :children
      ((:type "panel" :id "meters" :layout "row" :border :false
        :children ((:type "gauge" :id "cpu" :title "Busy" :unit "%" :value 0
                    :thresholds ((:at 0 :face "success") (:at 60 :face "warning") (:at 85 :face "error")))
                   (:type "stats" :id "load"
                    :figures ((:label "Load 1m" :value 0 :good "none") (:label "5m" :value 0 :good "none")
                              (:label "15m" :value 0 :good "none") (:label "Cores" :value 0 :good "none")
                              (:label "Tasks" :value 0 :good "none")))))
       (:type "chart" :id "cpu-history" :title "Busy, the last minute" :unit "%"
        :values () :window 60 :min 0 :max 100 :height 6)
       (:type "table" :id "processes" :title "Top processes by CPU"
        :columns ("PID" "Command" "CPU %" "CPU time")
        :align ("right" "left" "right" "right"))))
 :every 1
 :fetch
 ;; Linux: /proc/stat's CPU time at the last fetch, (TOTAL . IDLE).
 (let ((last-stat nil))
   (lambda (panel)
     (agent-ui-panel-run
      panel (if (eq system-type 'darwin)
                "sysctl -n hw.ncpu vm.loadavg; echo ---; ps -A -r -o pid=,pcpu=,time=,comm="
              "nproc; cat /proc/loadavg; head -1 /proc/stat; echo ---; ps -A --sort=-pcpu -o pid=,pcpu=,time=,comm=")
      (lambda (out)
        (cl-labels
            ((one-decimal (n) (/ (round (* n 10)) 10.0))
             (process (line)
               (when (string-match (concat "\\`[ \t]*\\([0-9]+\\)[ \t]+\\([0-9.]+\\)[ \t]+\\([0-9:.-]+\\)"
                                           "[ \t]+\\(.*\\)\\'")
                                   line)
                 (list (match-string 1 line)
                       (string-to-number (match-string 2 line))
                       (match-string 3 line)
                       (file-name-nondirectory (match-string 4 line)))))
             ;; /proc/stat's cpu line: user nice system idle iowait irq
             ;; softirq steal (guest's time counted in user's already).
             (stat-busy (line)
               (let* ((times (mapcar #'string-to-number (seq-take (cdr (split-string line)) 8)))
                      (stat (cons (apply #'+ times) (+ (nth 3 times) (nth 4 times))))
                      (total (- (car stat) (or (car last-stat) 0)))
                      (idle (- (cdr stat) (or (cdr last-stat) 0))))
                 (setq last-stat stat)
                 (if (> total 0) (* 100.0 (/ (float (- total idle)) total)) 0.0))))
          (pcase-let* ((`(,system ,ps) (split-string out "\n---\n"))
                       (`(,cores ,load ,stat) (split-string system "\n" t))
                       (cores (max 1 (string-to-number cores)))
                       (loads (mapcar #'string-to-number (split-string load "[{} ]+" t)))
                       (processes (delq nil (mapcar #'process (split-string ps "\n" t))))
                       (busy (one-decimal (min 100.0 (if stat
                                                         (stat-busy stat)
                                                       (/ (apply #'+ (mapcar #'cadr processes)) cores))))))
            (agent-ui-panel-update panel "cpu" :value busy)
            (agent-ui-panel-update
             panel "load"
             :figures (list (list :label "Load 1m" :value (or (nth 0 loads) 0) :good "none")
                            (list :label "5m" :value (or (nth 1 loads) 0) :good "none")
                            (list :label "15m" :value (or (nth 2 loads) 0) :good "none")
                            (list :label "Cores" :value cores :good "none")
                            (list :label "Tasks" :value (length processes) :good "none")))
            (agent-ui-panel-append panel "cpu-history" :values (list busy))
            (agent-ui-panel-update
             panel "processes"
             :rows (mapcar (pcase-lambda (`(,pid ,pcpu ,time ,command))
                             (list pid (truncate-string-to-width command 40 nil nil "…") (one-decimal pcpu) time))
                           (seq-take processes 12))))))))))
