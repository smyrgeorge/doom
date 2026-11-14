;;; $DOOMDIR/config/agent-ui/elements/markdown.el -*- lexical-binding: t; -*-
;; Agent UI's Markdown, drawn as agent-shell draws the agent's replies
;; (headings, emphasis, lists, tables, highlighted code, links), at the
;; canvas's width; without agent-shell, as it's written, wrapped. Loaded from
;; config/agent-ui/elements.el. Its ```mermaid blocks: elements/mermaid.el.

(require 'cl-lib)
(require 'subr-x)

(declare-function agent-shell-markdown-replace-markup "agent-shell-markdown")

(defun agent-ui-markdown--render (markdown width &optional ctx)
  "MARKDOWN drawn by agent-shell's renderer, its tables WIDTH wide, its
diagrams for CTX; nil without agent-shell."
  (when (require 'agent-shell-markdown nil t)
    (with-temp-buffer
      (insert markdown)
      ;; The buffer is in no window: the renderer would size tables to the
      ;; selected one's.
      (cl-letf (((symbol-function 'agent-shell-markdown--display-width)
                 (lambda (&optional _window) width)))
        (agent-shell-markdown-replace-markup
         ;; Images are the image type's (doom-nwj.12): here, their text.
         :render-images nil :highlight-blocks t :complete t))
      (agent-ui-markdown--diagrams ctx)
      (string-trim (buffer-string) "\n+" "\n+"))))

(defun agent-ui-markdown--diagrams (ctx)
  "The ```mermaid blocks agent-shell's renderer left as diagrams to draw
\(config/agent-shell/mermaid.el): each drawn here, for CTX
\(elements/mermaid.el)."
  (when (fboundp '+my/agent-shell-mermaid--regions)
    (pcase-dolist (`(,start ,end . ,diagram) (reverse (+my/agent-shell-mermaid--regions)))
      (goto-char start)
      (delete-region start end)
      (insert (agent-ui-mermaid-draw diagram ctx)))))

(defun agent-ui-markdown--text (props ctx)
  (let ((markdown (plist-get props :markdown))
        (width (plist-get ctx :width)))
    ;; Its lines wrapped: agent-shell leaves that to its window, and a
    ;; canvas's lines are cut (its tables already fit). Each line's rest
    ;; under its text's start: a list item's, a code line's indent.
    (agent-ui-wrap-hanging (or (agent-ui-markdown--render markdown width ctx) markdown)
                           width)))

(agent-ui-define markdown
  "Markdown, drawn as your replies are in agent-shell: headings, bold,
italic, inline code, lists, task lists, tables, fenced code highlighted by
its language, links, ```mermaid blocks drawn as diagrams. For notes,
summaries, a plan that stays in view while the conversation scrolls. Images
in it show as their text."
  :props ((markdown string "The Markdown" :required t))
  :example (:id "plan" :title "Plan"
            :markdown "1. **Parse** the config\n2. Check it against `schema.json`\n3. Write the report")
  :text #'agent-ui-markdown--text)
