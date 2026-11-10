;;; $DOOMDIR/examples/panel.el -*- lexical-binding: t; -*-
;; Example: a project panel (config/agent-ui/panels.el, docs/agent-ui.md). M-x
;; +my/example-panel puts this config's own cpu panel (.agent-ui/panels/cpu.el)
;; in a project of its own in the temp folder and opens it as SPC o U does,
;; alone in the frame: how busy the CPU is, its load, its last minute and the
;; processes using it most, filled every second by its code, without waiting.
;; Its code runs without asking: it's this config's own. The folder is deleted
;; once the panel is closed. macOS (sysctl, ps).

;; ====== CODE ======

(defun +my/example-panel--canvas ()
  "The example's panel's canvas, if it's open."
  (seq-find (lambda (buffer) (equal (buffer-name buffer) "Agent UI: cpu (service)"))
            (buffer-list)))

(defun +my/example-panel ()
  "Example: a project's panel, the CPU's, filled every second (its folder
deleted once it's closed). See examples/panel.el."
  (interactive)
  (let* ((dir (+my/example-folder "panel"))
         ;; Its project: named for its canvas, "cpu (service)".
         (root (file-name-as-directory (expand-file-name "service" dir)))
         (panels (expand-file-name ".agent-ui/panels/" root)))
    (make-directory panels t)
    (copy-file (expand-file-name ".agent-ui/panels/cpu.el" doom-user-dir) panels)
    (delete-other-windows)
    (let ((canvas (let ((agent-ui-panel-allow-function (lambda (_panel) t)))
                    (agent-ui-open-panel-here "cpu" root))))
      (+my/example-delete-when-closed dir (list canvas))
      (message "Panel example: gR reads it again, q closes it")
      canvas)))

(defun +my/example-panel-ready ()
  "Non-nil once the panel shows its processes and some of its last minute
\(the screenshot's waiting for it)."
  (when-let* ((canvas (+my/example-panel--canvas)))
    (and (>= (length (plist-get (agent-ui-get "cpu-history" :canvas canvas) :values)) 12)
         (plist-get (agent-ui-get "processes" :canvas canvas) :rows))))

(provide 'example-panel)
