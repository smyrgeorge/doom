;;; $DOOMDIR/examples/dashboard.el -*- lexical-binding: t; -*-
;; Example: a project dashboard (agent-ui-dashboards.el, the agent-ui package; docs/agent-ui.md). M-x
;; +my/example-dashboard puts this config's own cpu dashboard (.agent-ui/dashboards/cpu.el)
;; in a project of its own in the temp folder and opens it as SPC o U does,
;; alone in the frame: how busy the CPU is, its load, its last minute and the
;; processes using it most, filled every second by its code, without waiting.
;; Its code runs without asking: it's this config's own. The folder is deleted
;; once the dashboard is closed. macOS (sysctl, ps) and Linux (/proc, ps).

;; ====== CODE ======

(defun +my/example-dashboard--canvas ()
  "The example's dashboard's canvas, if it's open."
  (seq-find (lambda (buffer) (equal (buffer-name buffer) "Agent UI: cpu (service)"))
            (buffer-list)))

(defun +my/example-dashboard ()
  "Example: a project's dashboard, the CPU's, filled every second (its folder
deleted once it's closed). See examples/dashboard.el."
  (interactive)
  (let* ((dir (+my/example-folder "dashboard"))
         ;; Its project: named for its canvas, "cpu (service)".
         (root (file-name-as-directory (expand-file-name "service" dir)))
         (dashboards (expand-file-name ".agent-ui/dashboards/" root)))
    (make-directory dashboards t)
    (copy-file (expand-file-name ".agent-ui/dashboards/cpu.el" doom-user-dir) dashboards)
    (+my/example-alone)
    (let ((canvas (let ((agent-ui-dashboard-allow-function (lambda (_dashboard) t)))
                    (agent-ui-open-dashboard-here "cpu" root))))
      (+my/example-delete-when-closed dir (list canvas))
      (message "Dashboard example: gR reads it again, q closes it")
      canvas)))

(defun +my/example-dashboard-ready ()
  "Non-nil once the dashboard shows its processes and some of its last minute
\(the screenshot's waiting for it)."
  (when-let* ((canvas (+my/example-dashboard--canvas)))
    (and (>= (length (plist-get (agent-ui-get "cpu-history" :canvas canvas) :values)) 12)
         (plist-get (agent-ui-get "processes" :canvas canvas) :rows))))

(provide 'example-dashboard)
