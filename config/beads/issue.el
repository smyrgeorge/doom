;;; $DOOMDIR/config/beads/issue.el -*- lexical-binding: t; -*-
;; An issue's view (RET in the list, its preview): all of it shown. Loaded
;; from config/beads.el.

;; ITS NOTES
;; beads.el's view drew an issue's description, design and acceptance
;; criteria, not its notes (e n edits them; a bug reported again from code
;; adds to them, config/beads/file.el): after them here, as Markdown, with
;; their edit button. Its comments and the issues depending on it (an epic's,
;; a blocker's), which beads.el draws, are asked of bd (config/beads/bd.el).
(with-eval-after-load 'beads-vui
  (vui-defcomponent beads-vui-content-sections (issue &key editable on-refresh)
    "ISSUE's description, design, acceptance criteria and notes, each with
its edit button if EDITABLE (ON-REFRESH called after an edit)."
    :render
    (vui-fragment
     (mapcar (lambda (section)
               (vui-component 'beads-vui-content-section
                              :title (car section)
                              :content (alist-get (cdr section) issue)
                              :on-edit (when editable
                                         (beads-vui-make-edit-handler issue (cdr section) on-refresh))))
             '(("Description" . description)
               ("Design Notes" . design)
               ("Acceptance Criteria" . acceptance_criteria)
               ("Notes" . notes))))))
