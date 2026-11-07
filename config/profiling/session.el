;;; $DOOMDIR/config/profiling/session.el -*- lexical-binding: t; -*-
;; Starting and stopping the profiler, and saying where the profile went.
;; Loaded from config/profiling.el.

(defvar +my/profiling--run nil
  "The profile being recorded, from `+my/profiling-start': a plist of :start
(a `float-time'), :mode, and :gcs and :gc-elapsed at the start.")

(defun +my/profiling--skill ()
  "The skill telling an agent how to read a profile."
  (expand-file-name "skills/emacs-profiling/SKILL.md" doom-user-dir))

(defun +my/profiling--new-directory ()
  "A new, empty folder under `+my/profiling-directory', named by the time."
  (let* ((base (expand-file-name (format-time-string "%Y-%m-%d_%H-%M-%S")
                                 +my/profiling-directory))
         (dir base)
         (n 1))
    (while (file-exists-p dir)
      (setq n (1+ n)
            dir (format "%s-%d" base n)))
    (make-directory dir t)
    (file-name-as-directory dir)))

(defun +my/profiling-start ()
  "Start the profiler (`+my/profiling-mode'); `+my/profiling-stop' writes what
it records."
  (interactive)
  (require 'profiler)
  (when (profiler-running-p)
    (user-error "The profiler is already running"))
  (let ((mode (if (fboundp 'profiler-cpu-start) +my/profiling-mode 'mem)))
    ;; A previous run's logs would be written again with this one's.
    (profiler-reset)
    (profiler-start mode)
    (setq +my/profiling--run (list :start (float-time) :mode mode
                                   :gcs gcs-done :gc-elapsed gc-elapsed))
    (message "Profiling (%s): %s stops it and writes the profile"
             mode (substitute-command-keys "\\[+my/profiling-toggle]"))))

(defun +my/profiling-stop ()
  "Stop the profiler and write what it recorded into a new folder under
`+my/profiling-directory'. The message says where, and that an agent should
read the profiling skill before the profile; the same text is copied, to
paste to one. Returns the folder."
  (interactive)
  (require 'profiler)
  (unless (profiler-running-p)
    (user-error "The profiler isn't running"))
  (let* ((cpu (profiler-running-p 'cpu))
         (mem (profiler-running-p 'mem))
         ;; Started some other way (M-x profiler-start): less is known.
         (run (or +my/profiling--run
                  (list :mode (cond ((and cpu mem) 'cpu+mem) (cpu 'cpu) (t 'mem))))))
    (profiler-stop)
    (setq +my/profiling--run nil)
    (let ((info (append (list :stop (float-time)
                              :gcs (and (plist-get run :gcs)
                                        (- gcs-done (plist-get run :gcs)))
                              :gc-elapsed (and (plist-get run :gc-elapsed)
                                               (- gc-elapsed (plist-get run :gc-elapsed)))
                              :skill (+my/profiling--skill))
                        run))
          (dir (+my/profiling--new-directory)))
      (+my/profiling--write dir info
                            (and cpu profiler-cpu-log)
                            (and mem profiler-memory-log))
      (let ((text (format "Emacs profile in %s\nBefore reading it, read the skill %s"
                          dir (+my/profiling--skill))))
        (kill-new text)
        (message "%s\n(Copied, to paste to an agent.)" text))
      dir)))

(defun +my/profiling-toggle ()
  "Start the profiler, or stop it and write the profile (`+my/profiling-stop')."
  (interactive)
  (require 'profiler)
  (if (profiler-running-p)
      (+my/profiling-stop)
    (+my/profiling-start)))
