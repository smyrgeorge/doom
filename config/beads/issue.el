;;; $DOOMDIR/config/beads/issue.el -*- lexical-binding: t; -*-
;; An issue's view (RET in the list, its preview): all of it shown, in a pane
;; of any width. Loaded from config/beads.el.

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

;; NARROW PANES
;; beads.el laid an issue out for 60 columns or more: its rules 60
;; characters long (two lines at 40 columns, three at 25), its fields three to
;; a line (narrower, an [edit] went beside the next field's name), a long line
;; of its text going on from the pane's edge, not under itself, a
;; dependency's title cut at 40 characters. Here (beads.el's view drawn by
;; its own components, these laid out anew) its rules span its pane, its
;; fields go on to the next line whole, each with its [edit], a long line goes
;; on under itself (indented as it is: under a list item's text), a
;; dependency's title is whole. vui draws it again when its pane's width
;; changes, and here when another pane shows it (an issue opens in the
;; pane of the one before).
(defun +my/beads--rule (char)
  "A rule of CHAR across the window showing the issue (but its last column:
in a terminal a line filling it goes on to the next)."
  (vui-flex :width 'window
            (vui-flex-item (lambda (width) (vui-text (make-string (max 1 (1- width)) char))))))

(defun +my/beads--wrap-h ()
  "An issue's buffer: a long line goes on under itself at a word (see
above)."
  (setq-local word-wrap t)
  (when (require 'adaptive-wrap nil t)
    (adaptive-wrap-prefix-mode 1)))

(defun +my/beads--reflow-h ()
  "An issue's vui buffer: drawn again for the width of a window it's newly
shown in (vui does on a window's resize), as above."
  (add-hook 'window-buffer-change-functions #'vui--on-window-size-change nil t))

(add-hook 'beads-detail-mode-hook #'+my/beads--wrap-h)
(add-hook 'beads-detail-vui-mode-hook #'+my/beads--wrap-h)
(add-hook 'beads-detail-vui-mode-hook #'+my/beads--reflow-h)

(with-eval-after-load 'beads-vui
  (vui-defcomponent beads-vui-detail-view (issue &key on-refresh on-navigate editable)
    "ISSUE's view: its title, fields, sections, relationships and comments,
with rules across the window (see above). ON-REFRESH is called after an
edit, ON-NAVIGATE to go to an issue; EDITABLE, edit buttons."
    :render
    (beads-callbacks-provider
     (list :on-refresh on-refresh :on-navigate on-navigate)
     (beads-issue-provider
      issue
      (vui-vstack
       (vui-hstack
        (vui-text (format "[%s] " (alist-get 'id issue)) :face 'bold)
        (vui-text (alist-get 'title issue "") :face '(:height 1.2 :weight bold))
        (when editable
          (vui-fragment
           (vui-text " ")
           (vui-button "edit title"
                       :on-click (beads-vui-make-edit-handler issue 'title on-refresh)
                       :face 'link))))
       (vui-newline)
       (+my/beads--rule ?═)
       (vui-newline)
       (vui-component 'beads-vui-metadata-row :issue issue :editable editable :on-refresh on-refresh)
       (vui-newline)
       (+my/beads--rule ?─)
       (vui-newline)
       (vui-newline)
       (vui-component 'beads-vui-content-sections :issue issue :editable editable :on-refresh on-refresh)
       (vui-component 'beads-vui-relationships :issue issue)
       (vui-component 'beads-vui-comments :issue issue)))))

  (vui-defcomponent beads-vui-metadata-row (issue &key editable on-refresh)
    "ISSUE's fields, each with its edit button if EDITABLE (ON-REFRESH called
after an edit), as many to a line as the window has room for (see above)."
    :render
    (let ((status (alist-get 'status issue))
          (priority (alist-get 'priority issue))
          (created-by (alist-get 'created_by issue))
          (created (alist-get 'created_at issue))
          (labels (alist-get 'labels issue))
          (parent-id (alist-get 'parent_id issue))
          (edit (lambda (field) (when editable (beads-vui-make-edit-handler issue field on-refresh)))))
      (vui-vstack
       (vui-flex
        :width 'window :wrap t :spacing 5
        (vui-component 'beads-vui-editable-field
          :key 'status :label "Status" :value status :face (beads-vui-status-face status)
          :on-edit (funcall edit 'status))
        (vui-component 'beads-vui-editable-field
          :key 'priority :label "Priority" :value (format "P%d" priority)
          :face (beads-vui-priority-face priority) :on-edit (funcall edit 'priority))
        (vui-component 'beads-vui-editable-field
          :key 'type :label "Type" :value (beads--format-type issue) :on-edit (funcall edit 'issue_type)))
       (vui-flex
        :width 'window :wrap t :spacing 2
        (vui-component 'beads-vui-editable-field
          :key 'assignee :label "Assignee" :value (or (alist-get 'assignee issue) "(none)")
          :on-edit (funcall edit 'assignee))
        (when created-by
          (vui-component 'beads-vui-labeled-value :key 'created-by :label "Created by" :value created-by))
        (when created
          (vui-component 'beads-vui-labeled-value
            :key 'created :label "Created" :value (beads-vui-format-timestamp created))))
       (when parent-id
         (vui-hstack
          (vui-text "Parent: " :face 'bold)
          (vui-component 'beads-vui-clickable-id :issue-id parent-id)))
       (when (and labels (> (length labels) 0))
         (vui-component 'beads-vui-labeled-value
           :label "Labels" :value (mapconcat #'identity (append labels nil) ", "))))))

  (vui-defcomponent beads-vui-section-header (title)
    "A section's header: TITLE under a rule across the window (see above)."
    :render
    (vui-vstack
     (+my/beads--rule ?─)
     (vui-text (concat title ":") :face '(:weight bold :underline t))
     (vui-newline)))

  (vui-defcomponent beads-vui-dep-link (dep)
    "A dependency or dependent DEP: its id to go to it, its title whole, its
status and how it depends (see above)."
    :render
    (let ((status (alist-get 'status dep))
          (type (alist-get 'dependency_type dep)))
      (vui-hstack
       (vui-text "  ")
       (vui-component 'beads-vui-clickable-id :issue-id (alist-get 'id dep))
       (vui-text " ")
       (vui-text (alist-get 'title dep ""))
       (when status
         (vui-text (format " [%s]" status) :face (beads-vui-status-face status)))
       (when (and type (not (string= type "parent-child")))
         (vui-text (format " (%s)" type) :face 'shadow))))))
