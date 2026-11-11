;;; memory.el --- Agent UI panel: this machine's memory (a demo) -*- lexical-binding: t; -*-
;; Where the memory goes, its pressure, swap, its last minute, the
;; compressor's work and the processes holding the most, every second: one
;; command run without waiting, its output read here. macOS: sysctl, vm_stat
;; and ps, as Activity Monitor counts it (app memory, wired, compressed,
;; cached files, free; used: the first three). Linux: /proc/meminfo (apps'
;; anonymous memory, the kernel's own, zswap's compressed pages, cached files,
;; free; used: all but what's available), its pressure from /proc/pressure
;; (PSI: warning when tasks waited on memory 10% of the last 10 seconds,
;; critical when all did), zswap's pages from /proc/vmstat, and ps. Rates are
;; per second, from the last fetch's counters (kept in :fetch's closure:
;; nothing global).
(agent-ui-panel
 :version 1
 :ui (:type "panel" :id "memory" :title "Memory (demo): this machine, every second"
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
      panel (if (eq system-type 'darwin)
                (concat "sysctl -n hw.memsize vm.swapusage kern.memorystatus_vm_pressure_level; echo ---; vm_stat; "
                        "echo ---; ps -A -o pid=,rss=,pmem=,comm=")
              (concat "cat /proc/meminfo; echo ---; grep -E '^zswp(out|in) ' /proc/vmstat; "
                      "echo ---; cat /proc/pressure/memory 2>/dev/null; echo ---; ps -A -o pid=,rss=,pmem=,comm="))
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
                       (file-name-nondirectory (match-string 4 line)))))
             ;; Each: :total, :used, :cached, :swap (bytes), :pressure
             ;; (normal, warning, critical; nil: not known), :labels and
             ;; :breakdown (bytes) for its chart, :counters (pages
             ;; compressed and decompressed so far), :ps (its lines).
             (macos (out)
               (pcase-let* ((`(,system ,vm ,ps) (split-string out "^---\n"))
                            (`(,total ,swap ,pressure) (split-string system "\n" t))
                            (page (number "page size of \\([0-9]+\\)" vm))
                            (pages (lambda (name) (* page (number (concat name ": +\\([0-9]+\\)") vm))))
                            (app (- (funcall pages "Anonymous pages") (funcall pages "Pages purgeable")))
                            (wired (funcall pages "Pages wired down"))
                            (compressed (funcall pages "Pages occupied by compressor"))
                            (cached (+ (funcall pages "File-backed pages") (funcall pages "Pages purgeable"))))
                 (list :total (string-to-number total)
                       :used (+ app wired compressed)
                       :cached cached
                       :swap (* 1048576 (number "used = \\([0-9.]+\\)M" swap))
                       :pressure (pcase pressure ("4" "critical") ("2" "warning") (_ "normal"))
                       :labels '("App memory" "Wired" "Compressed" "Cached files" "Free")
                       :breakdown (list app wired compressed cached
                                        (+ (funcall pages "Pages free") (funcall pages "Pages speculative")))
                       :counters (list (number "Compressions: +\\([0-9]+\\)" vm)
                                       (number "Decompressions: +\\([0-9]+\\)" vm))
                       :ps ps)))
             (linux (out)
               (pcase-let* ((`(,meminfo ,vmstat ,psi ,ps) (split-string out "^---\n"))
                            (kb (lambda (name) (* 1024 (number (concat "^" name ": +\\([0-9]+\\)") meminfo))))
                            (total (funcall kb "MemTotal"))
                            (cached (+ (funcall kb "Buffers") (funcall kb "Cached") (funcall kb "SReclaimable"))))
                 (list :total total
                       :used (- total (funcall kb "MemAvailable"))
                       :cached cached
                       :swap (- (funcall kb "SwapTotal") (funcall kb "SwapFree"))
                       :pressure (cond ((not (string-match-p "avg10=" psi)) nil)
                                       ((>= (number "^full avg10=\\([0-9.]+\\)" psi) 10) "critical")
                                       ((>= (number "^some avg10=\\([0-9.]+\\)" psi) 10) "warning")
                                       (t "normal"))
                       :labels '("App memory" "Kernel" "Compressed" "Cached files" "Free")
                       :breakdown (list (funcall kb "AnonPages")
                                        (+ (funcall kb "SUnreclaim") (funcall kb "KernelStack")
                                           (funcall kb "PageTables"))
                                        (funcall kb "Zswap")
                                        cached
                                        (funcall kb "MemFree"))
                       :counters (list (number "^zswpout \\([0-9]+\\)" vmstat)
                                       (number "^zswpin \\([0-9]+\\)" vmstat))
                       :ps ps))))
          (let* ((memory (if (eq system-type 'darwin) (macos out) (linux out)))
                 (total (plist-get memory :total))
                 (used (plist-get memory :used))
                 (percent (/ (round (/ (* 1000.0 used) (max 1 total))) 10.0))
                 (now (append (plist-get memory :counters) (list (float-time))))
                 (processes (sort (delq nil (mapcar #'process (split-string (plist-get memory :ps) "\n" t)))
                                  (lambda (a b) (> (nth 1 a) (nth 1 b))))))
            (agent-ui-panel-update panel "used" :value percent)
            (agent-ui-panel-update
             panel "figures"
             :figures (list (list :label "Physical" :value (gib total) :unit "G" :good "none")
                            (list :label "Used" :value (gib used) :unit "G" :good "none")
                            (list :label "Cached files" :value (gib (plist-get memory :cached)) :unit "G" :good "none")
                            (list :label "Swap used" :value (gib (plist-get memory :swap)) :unit "G" :good "none")))
            (agent-ui-panel-update
             panel "pressure"
             :tags (list (pcase (plist-get memory :pressure)
                           ("critical" '(:label "critical" :face "error"))
                           ("warning" '(:label "warning" :face "warning"))
                           ("normal" '(:label "normal" :face "success"))
                           (_ '(:label "not known" :face "muted")))))
            (agent-ui-panel-update panel "breakdown"
                                   :labels (plist-get memory :labels)
                                   :values (mapcar #'gib (plist-get memory :breakdown)))
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
