;;; $DOOMDIR/config/beads/hidden.el -*- lexical-binding: t; -*-
;; What the issue list hides, and notices saying so. Loaded from
;; config/beads.el.

;; CLOSED ISSUES
;; The list asks bd for every issue (config/beads/bd.el), and shows the work
;; still open: its closed issues hidden (`+my/beads-closed-shown'), unless its
;; status filter asks for them (f s closed). Counted from bd's answer, no bd
;; call of their own.
(defvar-local +my/beads--closed-shown nil
  "Whether this list shows its closed issues.")

(defvar-local +my/beads--closed 0
  "How many closed issues this list's filter lets through (shown or hidden).")

(defvar-local +my/beads--closed-hidden nil
  "Whether this list hid its closed issues, at its last refresh.")

(defvar +my/beads--listing nil
  "The issue list being refreshed, while it is.")

(defun +my/beads--closed-p (issue)
  (equal (alist-get 'status issue) "closed"))

(defun +my/beads--status-filter-p (filter)
  "Whether FILTER (beads.el's) picks issues by their status."
  (let ((config (plist-get filter :config)))
    (or (eq (plist-get config :type) 'status)
        (seq-some #'+my/beads--status-filter-p (plist-get config :filters))
        (and (plist-get config :original)
             (+my/beads--status-filter-p (plist-get config :original))))))

(defun +my/beads--hide-closed-a (issues)
  "`beads-client-list''s ISSUES, while a list is refreshed: without the closed
ones, unless it shows them (see above); how many noted."
  (if (not (and +my/beads--listing (eq (current-buffer) +my/beads--listing)))
      issues
    (let ((closed (seq-filter #'+my/beads--closed-p issues)))
      (setq +my/beads--closed (length (if beads-list--filter
                                          (beads-filter-apply beads-list--filter closed)
                                        closed))
            +my/beads--closed-hidden (not (or +my/beads--closed-shown
                                              (+my/beads--status-filter-p beads-list--filter))))
      (if +my/beads--closed-hidden
          (seq-remove #'+my/beads--closed-p issues)
        issues))))

(defun +my/beads-listing-a (fn &rest args)
  "`beads-list-refresh': its list noted while it runs (see above)."
  (let ((+my/beads--listing (current-buffer)))
    (apply fn args)))

(defun +my/beads--list-h ()
  "A new issue list: closed issues shown or not, as `+my/beads-closed-shown'."
  (setq +my/beads--closed-shown +my/beads-closed-shown))

(add-hook 'beads-list-mode-hook #'+my/beads--list-h)

(defun +my/beads-show-closed ()
  "Show the list's closed issues."
  (interactive)
  (setq +my/beads--closed-shown t)
  (beads-list-refresh t))

(defun +my/beads-hide-closed ()
  "Hide the list's closed issues."
  (interactive)
  (setq +my/beads--closed-shown nil)
  (beads-list-refresh t))

(defun +my/beads-clear-filter ()
  "Clear the list's filter (and its marked issues only, `* *')."
  (interactive)
  (setq beads-list--filter nil
        beads-list--show-only-marked nil)
  (beads-list-refresh t))

;; THE NOTICES (config/banner.el's), over the list's column titles: what its
;; filter shows (Clear filter), and its closed issues hidden (Show closed) or
;; shown (Hide closed). None when it shows all its open work. beads.el draws
;; its column titles anew (each refresh, a sort): they're put back over them.
(defun +my/beads--filter-text (filter)
  "FILTER (beads.el's) said: \"priority P0\", \"type bug, label emacs\"..."
  (let* ((config (plist-get filter :config))
         (value (plist-get config :value)))
    (pcase (plist-get config :type)
      ('status (format "status %s" (if (eq value 'not-closed) "not closed"
                                     (string-replace "_" " " value))))
      ('priority (format "priority P%s" value))
      ('issue-type (format "type %s" value))
      ('assignee (if value (format "assignee %s" value) "unassigned"))
      ('label (format "label %s" value))
      ('search (format "search \"%s\"" value))
      ('parent (format "children of %s" value))
      ('composed (mapconcat #'+my/beads--filter-text (plist-get config :filters) ", "))
      (_ (beads-filter-name filter)))))

(defun +my/beads--notice (id text actions)
  "Notice ID shown with TEXT and ACTIONS, or closed if TEXT is nil."
  (cond (text (+my/banner-show id text :actions actions))
        ((assq id (bound-and-true-p +my/banner--list)) (+my/banner-close id))))

(defun +my/beads--notices ()
  "The list's notices, as it is now (see above)."
  (when (fboundp '+my/banner-show)
    (let ((closed +my/beads--closed)
          (filter (delq nil (list (and beads-list--filter (+my/beads--filter-text beads-list--filter))
                                  (and beads-list--show-only-marked "marked only")))))
      (+my/beads--notice
       'beads-filter
       (and filter (format "Filtered: %s." (string-join filter ", ")))
       '(("Clear filter" . +my/beads-clear-filter)))
      (+my/beads--notice
       'beads-closed
       (and (> closed 0)
            (or +my/beads--closed-hidden +my/beads--closed-shown)
            (format "%d closed %s %s." closed (if (= closed 1) "issue" "issues")
                    (if +my/beads--closed-hidden "hidden" "shown")))
       (if +my/beads--closed-hidden
           '(("Show closed" . +my/beads-show-closed))
         '(("Hide closed" . +my/beads-hide-closed)))))))

(defun +my/beads-notices-a (&rest _)
  "`tabulated-list-init-header' in an issue list: its notices over it."
  (when (derived-mode-p 'beads-list-mode)
    (+my/beads--notices)))

(after! beads-client
  ;; Outside the answers fetched in the background (config/beads/refresh.el).
  (advice-add 'beads-client-list :filter-return #'+my/beads--hide-closed-a '((depth . -50))))
(after! beads-list
  (advice-add 'beads-list-refresh :around #'+my/beads-listing-a))
(advice-add 'tabulated-list-init-header :after #'+my/beads-notices-a)
