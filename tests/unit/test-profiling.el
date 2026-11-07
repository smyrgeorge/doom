;;; tests/unit/test-profiling.el -*- lexical-binding: t; -*-
;; config/profiling.el: SPC h T starts the profiler; again, it stops it and
;; writes the profile as text into a new folder (a summary, the call trees, the
;; raw profiles), says where and that an agent should read the skill first, and
;; copies that. The real profiler, profiling a busy function.

(+test-load "config/profiling")

(require 'profiler)

;; ====== HELPERS ======

(defun +test-profiling--spin (seconds)
  "Keep Emacs busy for SECONDS, allocating as it goes."
  (let ((end (+ (float-time) seconds)))
    (while (< (float-time) end)
      (make-list 100 'x))))

(defmacro +test-profiling--with (&rest body)
  "BODY with profiles written to a folder of its own; the profiler stopped and
its logs dropped after."
  (declare (indent 0))
  `(let ((+my/profiling-directory (make-temp-file (+test-tmp-file "profiles/run-") t))
         (+my/profiling-mode 'cpu+mem)
         (kill-ring nil))
     (unwind-protect (progn ,@body)
       (profiler-reset)
       (setq +my/profiling--run nil))))

(defun +test-profiling--read (dir file)
  "FILE of the profile in DIR, as text."
  (with-temp-buffer
    (insert-file-contents (expand-file-name file dir))
    (buffer-string)))

(defun +test-profiling--log (&rest backtraces)
  "A profiler log of BACKTRACES: (COUNT FUNCTION...), the running one first."
  (let ((log (make-hash-table :test #'equal)))
    (dolist (backtrace backtraces)
      ;; Padded with nil, as the profiler's are: a stack it saw whole.
      (puthash (vconcat (cdr backtrace) [nil]) (car backtrace) log))
    log))

;; ====== KEYS ======

(ert-deftest profiling/takes-over-doom-toggle ()
  (should (eq (command-remapping 'doom/toggle-profiler) #'+my/profiling-toggle)))

;; ====== RECORDING ======

(ert-deftest profiling/toggle-starts-then-writes-profile ()
  (+test-profiling--with
    (+my/profiling-toggle)
    (should (profiler-running-p 'cpu))
    (should (profiler-running-p 'mem))
    (+test-profiling--spin 0.3)
    (let ((dir (+my/profiling-toggle)))
      (should-not (profiler-running-p))
      (should (file-in-directory-p dir +my/profiling-directory))
      (dolist (file '("summary.txt" "cpu-calls.txt" "cpu-callers.txt" "cpu.profile"
                      "mem-calls.txt" "mem-callers.txt" "mem.profile"))
        (should (file-exists-p (expand-file-name file dir))))
      (let ((summary (+test-profiling--read dir "summary.txt")))
        (should (string-match-p (regexp-quote (+my/profiling--skill)) summary))
        (should (string-match-p "^Recorded .* ([0-9.]+ s)$" summary))
        (should (string-match-p "stacks of up to 32 calls" summary))
        (should (string-match-p "^== CPU: " summary))
        (should (string-match-p "^== Memory: " summary))
        (should (string-match-p "+test-profiling--spin" summary)))
      (should (string-match-p "+test-profiling--spin" (+test-profiling--read dir "cpu-calls.txt")))
      (should (string-match-p "+test-profiling--spin" (+test-profiling--read dir "cpu-callers.txt"))))))

(ert-deftest profiling/stop-says-where-and-copies ()
  (+test-profiling--with
    (+test-clear-messages)
    (+my/profiling-start)
    (+test-profiling--spin 0.05)
    (let ((dir (+my/profiling-stop))
          (skill (expand-file-name "skills/emacs-profiling/SKILL.md" +test-root)))
      (should (file-exists-p skill))
      (should (equal (car kill-ring)
                     (format "Emacs profile in %s\nBefore reading it, read the skill %s" dir skill)))
      (should (= 1 (+test-messages (regexp-quote dir))))
      (should (= 1 (+test-messages (regexp-quote skill)))))))

(ert-deftest profiling/stacks-are-deeper ()
  (+test-profiling--with
    (+my/profiling-start)
    (+test-profiling--spin 0.05)
    (+my/profiling-stop)
    (let ((lengths nil))
      (maphash (lambda (backtrace _) (cl-pushnew (length backtrace) lengths))
               profiler-cpu-log)
      ;; Garbage collections' are shorter: [Automatic\ GC nil].
      (should (= (apply #'max lengths) 32)))))

(ert-deftest profiling/raw-profile-reads-back ()
  (+test-profiling--with
    (+my/profiling-start)
    (+test-profiling--spin 0.1)
    (let* ((dir (+my/profiling-stop))
           (profile (profiler-read-profile (expand-file-name "cpu.profile" dir))))
      (should (eq (profiler-profile-type profile) 'cpu))
      (should (< 0 (hash-table-count (profiler-profile-log profile)))))))

(ert-deftest profiling/each-run-its-own-folder-and-logs ()
  (+test-profiling--with
    (+my/profiling-start)
    (+test-profiling--spin 0.05)
    (let ((first (+my/profiling-stop))
          (+my/profiling-mode 'cpu))
      (+my/profiling-start)
      (should-not (profiler-running-p 'mem))
      (+test-profiling--spin 0.05)
      (let ((second (+my/profiling-stop)))
        (should-not (equal first second))
        (should (file-exists-p (expand-file-name "mem.profile" first)))
        ;; The first run's memory log isn't written again.
        (should (file-exists-p (expand-file-name "cpu.profile" second)))
        (should-not (file-exists-p (expand-file-name "mem.profile" second)))
        (should-not (string-match-p "== Memory" (+test-profiling--read second "summary.txt")))))))

(ert-deftest profiling/stops-a-profiler-started-elsewhere ()
  (+test-profiling--with
    (profiler-start 'cpu)
    (+test-profiling--spin 0.05)
    (let ((dir (+my/profiling-toggle)))
      (should-not (profiler-running-p))
      (should (string-match-p "started some other way"
                              (+test-profiling--read dir "summary.txt"))))))

(ert-deftest profiling/start-and-stop-refuse-twice ()
  (+test-profiling--with
    (should-error (+my/profiling-stop) :type 'user-error)
    (+my/profiling-start)
    (should-error (+my/profiling-start) :type 'user-error)
    (+my/profiling-stop)))

;; ====== THE TEXT ======

(ert-deftest profiling/self-and-total ()
  (pcase-let ((`(,total ,self ,all)
               (+my/profiling--flat
                (+test-profiling--log '(90 c b a) '(9 d a) '(1 e d a) '(3 f f a) '(4 b a)))))
    (should (= total 107))
    (should (equal self '(("c" . 90) ("d" . 9) ("b" . 4) ("f" . 3) ("e" . 1))))
    ;; Recursion (f calling f) counts once.
    (should (equal (take 4 all) '(("a" . 107) ("b" . 94) ("c" . 90) ("d" . 10))))
    (should (equal (assoc "f" all) '("f" . 3)))))

(ert-deftest profiling/trees-leave-out-small-branches ()
  (let ((+my/profiling-min-percent 5)
        (log (+test-profiling--log '(90 c b a) '(6 d a) '(2 e a) '(2 g a)))
        (file (+test-tmp-file "profiling/tree.txt")))
    (+my/profiling--write-tree file 'cpu log 100 nil)
    (let ((lines (cddr (split-string (+test-profiling--read "/" file) "\n" t))))
      (should (equal (mapcar #'string-trim lines)
                     '("100  100.0%  a"
                       "90   90.0%    b"
                       "90   90.0%      c"
                       "6    6.0%    d"
                       ;; e and g: 2 each, 4 together, under 5.
                       ))))
    (setq log (+test-profiling--log '(90 c b a) '(6 d a) '(3 e a) '(2 g a)))
    (+my/profiling--write-tree file 'cpu log 100 nil)
    (should (string-match-p "^ +5 +5\\.0%    (2 more, each under 5%)$"
                            (+test-profiling--read "/" file)))))

(ert-deftest profiling/callers-tree-is-bottom-up ()
  (let ((+my/profiling-min-percent 0)
        (file (+test-tmp-file "profiling/callers.txt")))
    (+my/profiling--write-tree file 'cpu (+test-profiling--log '(3 c b a) '(1 c d)) 4 t)
    (should (equal (mapcar #'string-trim
                           (cddr (split-string (+test-profiling--read "/" file) "\n" t)))
                   '("4  100.0%  c"
                     "3   75.0%    b"
                     "3   75.0%      a"
                     "1   25.0%    d")))))
