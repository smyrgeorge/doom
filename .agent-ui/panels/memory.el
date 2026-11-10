;;; memory.el --- Agent UI panel: this Mac's memory (a demo) -*- lexical-binding: t; -*-
;; Where the memory goes (as Activity Monitor counts it: app memory, wired,
;; compressed, cached files, free), its pressure, swap, its last minute, the
;; compressor's work and the processes holding the most, every second: from
;; sysctl, vm_stat and ps (macOS), one command run without waiting, its
;; output read here. Rates are per second, from the last fetch's counters
;; (kept in :fetch's closure: nothing global).
(agent-ui-panel
 :version 1
 :ui (:type "panel" :id "memory" :title "Memory (demo): this Mac, every second"
      :children
      ((:type "panel" :id "meters" :layout "row" :border :false
        :children ((:type "gauge" :id "used" :title "Used" :unit "%" :value 0
                    :thresholds ((:at 0 :face "success") (:at 75 :face "warning") (:at 90 :face "error")))
                   (:type "stats" :id "figures"
                    :figures ((:label "Physical" :value 0 :unit "G" :good "none")
                              (:label "Used" :value 0 :unit "G" :good "none")
                              (:label "Cached files" :value 0 :unit "G" :good "none")
                              (:label "Swap used" :value 0 :unit "G" :good "none")))))
       (:type "tags" :id "pressure" :title "Memory pressure" :tags ((:label "…" :face "muted")))
       (:type "chart" :id "breakdown" :title "Where it goes" :kind "bar" :unit "G"
        :labels ("App memory" "Wired" "Compressed" "Cached files" "Free") :values (0 0 0 0 0))
       (:type "panel" :id "history" :layout "row" :border :false
        :children ((:type "chart" :id "used-history" :title "Used, the last minute" :unit "%"
                    :values () :window 60 :min 0 :max 100 :height 5)
                   (:type "chart" :id "compressor" :title "Compressor, pages per second" :window 60 :height 5
                    :series ((:name "compressed" :values ()) (:name "decompressed" :values ())))))
       (:type "table" :id "processes" :title "Top processes by memory"
        :columns ("PID" "Command" "Memory" "MEM %") :align ("right" "left" "right" "right"))))
 :every 1
 :fetch
 (let ((last nil))                      ; (COMPRESSIONS DECOMPRESSIONS TIME), the last fetch's
   (lambda (panel)
     (agent-ui-panel-run
      panel (concat "sysctl -n hw.memsize vm.swapusage kern.memorystatus_vm_pressure_level; echo ---; vm_stat; "
                    "echo ---; ps -A -o pid=,rss=,pmem=,comm=")
      (lambda (out)
        (cl-labels
            ((number (regexp text)
               (if (string-match regexp text) (string-to-number (match-string 1 text)) 0))
             (gib (bytes) (/ (round (/ bytes 107374182.4)) 10.0))
             (size (kb) (if (>= kb 1048576)
                            (format "%.1f G" (/ kb 1048576.0))
                          (format "%d M" (round (/ kb 1024.0)))))
             (process (line)
               (when (string-match "\\`[ \t]*\\([0-9]+\\)[ \t]+\\([0-9]+\\)[ \t]+\\([0-9.]+\\)[ \t]+\\(.*\\)\\'" line)
                 (list (match-string 1 line)
                       (string-to-number (match-string 2 line))
                       (string-to-number (match-string 3 line))
                       (file-name-nondirectory (match-string 4 line))))))
          (pcase-let* ((`(,system ,vm ,ps) (split-string out "\n---\n"))
                       (`(,total ,swap ,pressure) (split-string system "\n" t))
                       (total (string-to-number total))
                       (page (number "page size of \\([0-9]+\\)" vm))
                       (pages (lambda (name) (* page (number (concat name ": +\\([0-9]+\\)") vm))))
                       (app (- (funcall pages "Anonymous pages") (funcall pages "Pages purgeable")))
                       (wired (funcall pages "Pages wired down"))
                       (compressed (funcall pages "Pages occupied by compressor"))
                       (cached (+ (funcall pages "File-backed pages") (funcall pages "Pages purgeable")))
                       (free (+ (funcall pages "Pages free") (funcall pages "Pages speculative")))
                       (used (+ app wired compressed))
                       (percent (/ (round (/ (* 1000.0 used) (max 1 total))) 10.0))
                       (swap-used (* 1048576 (number "used = \\([0-9.]+\\)M" swap)))
                       (now (list (number "Compressions: +\\([0-9]+\\)" vm)
                                  (number "Decompressions: +\\([0-9]+\\)" vm)
                                  (float-time)))
                       (processes (sort (delq nil (mapcar #'process (split-string ps "\n" t)))
                                        (lambda (a b) (> (nth 1 a) (nth 1 b))))))
            (agent-ui-panel-update panel "used" :value percent)
            (agent-ui-panel-update
             panel "figures"
             :figures (list (list :label "Physical" :value (gib total) :unit "G" :good "none")
                            (list :label "Used" :value (gib used) :unit "G" :good "none")
                            (list :label "Cached files" :value (gib cached) :unit "G" :good "none")
                            (list :label "Swap used" :value (gib swap-used) :unit "G" :good "none")))
            (agent-ui-panel-update
             panel "pressure"
             :tags (list (pcase pressure
                           ("4" '(:label "critical" :face "error"))
                           ("2" '(:label "warning" :face "warning"))
                           (_ '(:label "normal" :face "success")))))
            (agent-ui-panel-update panel "breakdown"
                                   :values (list (gib app) (gib wired) (gib compressed) (gib cached) (gib free)))
            (agent-ui-panel-append panel "used-history" :values (list percent))
            (when last
              (let ((seconds (max 0.001 (- (nth 2 now) (nth 2 last)))))
                (agent-ui-panel-append
                 panel "compressor"
                 :series (list (list :name "compressed" :values (list (round (/ (- (nth 0 now) (nth 0 last)) seconds))))
                               (list :name "decompressed" :values (list (round (/ (- (nth 1 now) (nth 1 last)) seconds))))))))
            (setq last now)
            (agent-ui-panel-update
             panel "processes"
             :rows (mapcar (pcase-lambda (`(,pid ,rss ,pmem ,command))
                             (list pid (truncate-string-to-width command 40 nil nil "…")
                                   (size rss) (/ (round (* pmem 10)) 10.0)))
                           (seq-take processes 12))))))))))
