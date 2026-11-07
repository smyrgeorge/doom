;;; $DOOMDIR/config/profiling/report.el -*- lexical-binding: t; -*-
;; A profile written as text an agent can read: a summary, the call trees, the
;; raw profiles. Loaded from config/profiling.el.

(defun +my/profiling--name (entry)
  "A backtrace ENTRY as text: a function's name, `Automatic GC'..."
  (cond ((stringp entry) entry)
        ((symbolp entry) (symbol-name entry))
        (t (require 'help-fns)
           (substring-no-properties (help-fns-function-name entry)))))

(defun +my/profiling--amount (type count)
  "COUNT as text: samples for TYPE `cpu', bytes for `memory'."
  (if (eq type 'memory)
      (file-size-human-readable count)
    (profiler-format-number count)))

(defun +my/profiling--line (type count total indent name)
  "A line of a list or a tree: COUNT, its share of TOTAL, then NAME after
INDENT spaces."
  (format "%9s %6.1f%%  %s%s\n"
          (+my/profiling--amount type count)
          (if (zerop total) 0 (/ (* 100.0 count) total))
          (make-string indent ?\s)
          name))

(defun +my/profiling--flat (log)
  "LOG's total, and its functions' counts: (TOTAL SELF ALL), SELF and ALL
lists of (NAME . COUNT), biggest first. SELF counts the samples the function
was running in, ALL those it was anywhere on the stack in (itself, or
something it called)."
  (let ((self (make-hash-table :test #'equal))
        (all (make-hash-table :test #'equal))
        (total 0))
    (maphash
     (lambda (backtrace count)
       (setq total (+ total count))
       ;; The running function first; nil pads the rest of the vector.
       (let ((seen nil))
         (mapc (lambda (entry)
                 (when entry
                   (let ((name (+my/profiling--name entry)))
                     (unless seen
                       (cl-incf (gethash name self 0) count))
                     ;; Recursion counts once.
                     (unless (member name seen)
                       (push name seen)
                       (cl-incf (gethash name all 0) count)))))
               backtrace)))
     log)
    (cl-flet ((sorted (table)
                (let ((items nil))
                  (maphash (lambda (name count) (push (cons name count) items)) table)
                  (sort items (lambda (a b) (> (cdr a) (cdr b)))))))
      (list total (sorted self) (sorted all)))))

(defun +my/profiling--insert-tree (type tree total min indent)
  "Insert TREE's branches of at least MIN, INDENT spaces deep, biggest first;
the ones left out as one line, when together they reach MIN."
  (let ((left 0)
        (left-count 0))
    (dolist (child (profiler-calltree-children tree))
      (let ((count (profiler-calltree-count child)))
        (cond
         ;; The top-down tree's "..." (stacks too deep to know their
         ;; start), when there were none.
         ((zerop count))
         ((< count min)
          (setq left (1+ left)
                left-count (+ left-count count)))
         (t
          (insert (+my/profiling--line type count total indent
                                       (+my/profiling--name (profiler-calltree-entry child))))
          (+my/profiling--insert-tree type child total min (+ indent 2))))))
    (when (and (> left 0) (>= left-count min))
      (insert (+my/profiling--line
               type left-count total indent
               (format "(%d more, each under %s%%)" left +my/profiling-min-percent))))))

(defun +my/profiling--write-tree (file type log total reverse)
  "Write LOG's call tree into FILE: each call under the one that made it, or
with REVERSE each running function above the calls that led to it."
  (let ((tree (profiler-calltree-build log :reverse reverse)))
    (profiler-calltree-sort tree #'profiler-calltree-count>)
    (with-temp-file file
      (insert (if reverse
                  "Bottom up: each function that was running, under it the calls that led to it.\n"
                "Top down: each call under the one that made it.\n")
              (format "%s; branches under %s%% left out.\n\n"
                      (if (eq type 'memory) "Bytes allocated, their share" "Samples, their share")
                      +my/profiling-min-percent))
      (+my/profiling--insert-tree type tree total
                                  (/ (* total +my/profiling-min-percent) 100.0) 0))))

(defun +my/profiling--write-raw (file type log)
  "Write LOG as a TYPE profile into FILE, for M-x profiler-find-profile."
  (let ((profile (profiler-make-profile :type type :timestamp (current-time) :log log)))
    (with-temp-file file
      (let ((print-level nil)
            (print-length nil))
        (prin1 (profiler-fixup-profile profile) (current-buffer))))))

(defun +my/profiling--header (info)
  "The summary's first lines, from INFO (see `+my/profiling--write')."
  (let ((start (plist-get info :start))
        (stop (plist-get info :stop)))
    (concat
     (format "Emacs profile. Before reading it, read the skill %s\n\n" (plist-get info :skill))
     (if start
         (format "Recorded %s to %s (%.1f s)\n"
                 (format-time-string "%F %T" start) (format-time-string "%T" stop) (- stop start))
       (format "Stopped %s (started some other way: when is unknown)\n"
               (format-time-string "%F %T" stop)))
     (format "Profiler: %s, a sample every %g ms, stacks of up to %d calls\n"
             (plist-get info :mode) (/ profiler-sampling-interval 1e6)
             profiler-max-stack-depth)
     (format "Emacs %s, native compilation %s\n" emacs-version
             (if (and (fboundp 'native-comp-available-p) (native-comp-available-p)) "on" "off"))
     (when (plist-get info :gcs)
       (format "Garbage collections during the run: %d, %.2f s\n"
               (plist-get info :gcs) (plist-get info :gc-elapsed))))))

(defun +my/profiling--section (type title name total self all)
  "The summary's part for a TYPE profile: TITLE, the files' NAME, its TOTAL,
the SELF and ALL lists of `+my/profiling--flat'."
  (with-temp-buffer
    (insert (format "\n== %s: %s %s ==\n" title (+my/profiling--amount type total)
                    (if (eq type 'memory) "allocated" "samples"))
            (format "Files: %s-calls.txt (top down), %s-callers.txt (bottom up), %s.profile (raw)\n"
                    name name name)
            (format "\nSelf: in the function itself (top %d)\n" +my/profiling-top))
    (pcase-dolist (`(,fn . ,count) (take +my/profiling-top self))
      (insert (+my/profiling--line type count total 0 fn)))
    (insert (format "\nTotal: in the function or what it called (top %d)\n" +my/profiling-top))
    (pcase-dolist (`(,fn . ,count) (take +my/profiling-top all))
      (insert (+my/profiling--line type count total 0 fn)))
    (buffer-string)))

(defun +my/profiling--write (dir info cpu-log mem-log)
  "Write the profile into DIR: summary.txt, and for each log (CPU-LOG,
MEM-LOG, either nil) its call trees and raw profile. INFO is
`+my/profiling--run''s plist with :stop, :gcs, :gc-elapsed and :skill."
  (let ((sections nil))
    (pcase-dolist (`(,type ,name ,title ,log) `((cpu "cpu" "CPU" ,cpu-log)
                                                (memory "mem" "Memory" ,mem-log)))
      (when log
        (pcase-let ((`(,total ,self ,all) (+my/profiling--flat log)))
          (+my/profiling--write-tree (expand-file-name (concat name "-calls.txt") dir)
                                     type log total nil)
          (+my/profiling--write-tree (expand-file-name (concat name "-callers.txt") dir)
                                     type log total t)
          (+my/profiling--write-raw (expand-file-name (concat name ".profile") dir) type log)
          (push (+my/profiling--section type title name total self all) sections))))
    (with-temp-file (expand-file-name "summary.txt" dir)
      (insert (+my/profiling--header info))
      (if sections
          (mapc #'insert (nreverse sections))
        (insert "\nNothing was recorded.\n")))))
