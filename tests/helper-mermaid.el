;;; tests/helper-mermaid.el -*- lexical-binding: t; -*-
;; What the Mermaid tests (tests/unit/test-mermaid.el, test-agent-shell-mermaid.el...)
;; share: a stand-in theme (faces' colours faked), a stand-in mmdc (a script:
;; no node or Chrome), waiting for processes. Loaded by each of them, after
;; tests/helper.el and config/mermaid.el.

;; ====== A STAND-IN THEME ======

(defconst +test-mermaid--dark
  '((default :foreground "#bbc2cf" :background "#282c34")
    (shadow :foreground "#5b6268")
    (font-lock-keyword-face :foreground "#51afef")
    (font-lock-function-name-face :foreground "#c678dd")
    (font-lock-string-face :foreground "#98be65")
    (font-lock-type-face :foreground "#ecbe7b")
    (font-lock-builtin-face :foreground "#c678dd")
    (warning :foreground "#ecbe7b")
    (error :foreground "#ff6c6b")
    (success :foreground "#98be65"))
  "doom-one's colours, as faces give them; the other faces have none.")

(defconst +test-mermaid--light
  '((default :foreground "#383a42" :background "#fafafa")
    (font-lock-keyword-face :foreground "#e45649"))
  "A light theme's.")

(defmacro +test-mermaid--theme (faces &rest body)
  "BODY with the faces' colours as FACES says: ((FACE :foreground C
:background C)...), with no colour for any other face (or a default's)."
  (declare (indent 1))
  `(let ((faces ,faces)
         (+my/mermaid--json nil))
     (cl-letf (((symbol-function 'face-foreground)
                (lambda (face &rest _) (plist-get (alist-get face faces) :foreground)))
               ((symbol-function 'face-background)
                (lambda (face &rest _) (plist-get (alist-get face faces) :background))))
       ,@body)))

;; ====== A STAND-IN MMDC ======
;; A script taking mmdc's arguments: the source on its input, its SVG (the
;; source and the config it was given in it) written to -o; a source saying
;; ERROR fails as Mermaid does, SLOW takes 3 s. Each run's arguments logged.

(defconst +test-mermaid--mmdc-script
  "#!/bin/sh
dir=$(dirname \"$0\")
echo \"$*\" >> \"$dir/runs.log\"
out= config=
while [ $# -gt 0 ]; do
  case \"$1\" in -o) out=$2; shift ;; -c) config=$2; shift ;; esac
  shift
done
source=$(cat)
case \"$source\" in *SLOW*) sleep 3 ;; esac
case \"$source\" in
  *ERROR*)
    echo 'Error: Parse error on line 2:' >&2
    echo '...A --> ERROR' >&2
    echo \"Expecting 'SEMI', got 'NODE_STRING'\" >&2
    echo 'Parser.parseError (https://mermaid-cli-intercept.invalid/mermaid.mjs:1:2)' >&2
    echo '    at async renderMermaid (file:///mmdc/src/index.js:690:22)' >&2
    exit 1 ;;
esac
{ printf '<svg id=\"my-svg\"><text><tspan>Write</tspan><tspan> the</tspan></text>'
  printf '<desc>%s</desc><desc>' \"$source\"; cat \"$config\"; printf '</desc></svg>'; } > \"$out\"
"
  "The stand-in mmdc (see above).")

(defun +test-mermaid--make-mmdc ()
  "A stand-in mmdc in a folder of its own: its path."
  (let ((file (expand-file-name "mmdc" (make-temp-file (+test-tmp-file "mermaid/bin-") t))))
    (with-temp-file file (insert +test-mermaid--mmdc-script))
    (set-file-modes file #o755)
    file))

(defmacro +test-mermaid--with-mmdc (&rest body)
  "BODY with the stand-in mmdc, an empty cache, no drawing waiting: `mmdc' its
path; `shown' the buffers the commands would show."
  (declare (indent 0))
  `(let* ((mmdc (+test-mermaid--make-mmdc))
          (+my/mermaid-mmdc mmdc)
          (mermaid-mmdc-location mmdc)
          (+my/mermaid-cache-directory (file-name-as-directory (make-temp-file (+test-tmp-file "mermaid/cache-") t)))
          (+my/mermaid--waiting (make-hash-table :test #'equal))
          (+my/mermaid--queue nil)
          (+my/mermaid--running 0)
          (+my/mermaid--pruned t)
          (+my/mermaid--written nil)
          (shown nil))
     (cl-letf (((symbol-function 'display-buffer) (lambda (buffer &rest _) (push buffer shown) nil)))
       (unwind-protect (progn ,@body)
         (dolist (process (process-list))
           (when (equal (process-name process) "mmdc") (delete-process process)))
         (dolist (buffer shown)
           (when (buffer-live-p (get-buffer buffer))
             (with-current-buffer buffer (set-buffer-modified-p nil))
             (kill-buffer buffer)))))))

(defun +test-mermaid--runs (mmdc)
  "The stand-in MMDC's runs: each its arguments (a list), oldest first."
  (let ((log (expand-file-name "runs.log" (file-name-directory mmdc))))
    (when (file-exists-p log)
      (mapcar #'split-string
              (split-string (with-temp-buffer (insert-file-contents log) (buffer-string)) "\n" t)))))

(defun +test-mermaid--wait (predicate &optional seconds)
  "Wait (processes and timers running) until PREDICATE, SECONDS at most (10)."
  (let ((end (+ (float-time) (or seconds 10))))
    (while (and (not (funcall predicate)) (< (float-time) end))
      (accept-process-output nil 0.05))
    (funcall predicate)))

(defun +test-mermaid--text (file)
  (with-temp-buffer (insert-file-contents file) (buffer-string)))

(defun +test-mermaid--arg (args flag)
  (cadr (member flag args)))
