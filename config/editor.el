;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; The editor. Loaded from config.el; its code is in config/editor/; getting
;; around is config/navigation.el.

;; ====== VARIABLES ======

;; EDITING
;; SPC c ~: cycle the word at point through snake_case, UPPER_CASE,
;; PascalCase, camelCase and kebab-case.
(use-package! string-inflection
  :commands string-inflection-all-cycle)

;; RAINBOW BRACKETS
;; Color (), [] and {} by nesting depth in code, so matching pairs are easy
;; to spot.
(use-package! rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; SMOOTH SCROLL
;; Doom's smooth-scroll module (ultra-scroll) scrolls by the pixels each wheel
;; event reports, all at once: right for a trackpad's stream of small steps,
;; but a mouse wheel reports a few lines per notch (51 px here), so it still
;; moved in jumps. Bigger steps now glide, fast at first and slowing down
;; (ease-out); notches in quick succession add to what's left, without a
;; restart. A frame per refresh of the display (60 Hz), each covering a share
;; of what's left that depends on the time since the last one: a late frame
;; catches up instead of slowing the glide down.
(defvar +my/smooth-scroll-min-step 20
  "Wheel steps bigger than this many pixels glide; smaller ones (trackpads) don't.")

(defvar +my/smooth-scroll-frame (/ 1.0 60)
  "Seconds between the frames of a glide: the display's refresh (60 Hz).")

(defvar +my/smooth-scroll-time-constant 0.05
  "Seconds in which a glide covers ~63% of what's left; it ends after about
three times this.")

(after! ultra-scroll
  ;; Doom's module pauses hl-todo during scrolls (`ultra-scroll-hide-functions'),
  ;; so TODO/NOTE/FIXME lost their highlight while scrolling and got it back
  ;; when it stopped: they flickered. Keep them on.
  (remove-hook 'ultra-scroll-hide-functions #'hl-todo-mode)

  ;; Doom also has it freeze the mode line during scrolls, by pushing onto
  ;; `mode-line-format'. In a buffer whose mode line is a string (Doom's popups,
  ;; e.g. *Messages*) that made it an invalid list: evil, which updates the mode
  ;; line on every state change, then failed, so Esc couldn't close the popup;
  ;; and its cleanup timer failed when the window was gone. Leave it alone.
  (setq ultra-scroll-throttle-mode-line nil))

;; TABS PER WINDOW
;; Each window has its own tabs: the buffers
;; shown in it, in the order they first were (Emacs's tab line, instead of
;; Doom's centaur-tabs, whose tab groups were per project and shared by every
;; window). A split starts with one tab, the buffer it shows. Files, Claude
;; sessions, dired and magit get tabs; other buffers only while shown.
;; Closing a tab (its ✕, a middle click) takes it off that window, which goes
;; back to the tab it showed before; closing its last tab closes the window
;; (the frame's only one, beside side panels, shows Doom's dashboard instead).
;; A file is closed too once no window has it as a tab any more (asking first
;; if it has unsaved changes). A Claude session only leaves the tab line: close
;; it with its own commands.
;; Tabs look as they did: an icon, a bar on the current one, • when unsaved.
;; Right-clicking a tab: Emacs's Close and Close other tabs, and
;; Split Vertically (a pane on the right) and Split Horizontally (below): the
;; new pane has only that tab and takes focus; the tab stays where it was too.
(defvar +my/tabs-height 22
  "Height of the tab row in graphical frames, in pixels.")

(defvar +my/tabs-bar-width 2
  "Width of the bar marking the current tab, in pixels.")

;; The tab line drawn and closed as above (config/editor/tabs.el); none in the
;; sidebar or the dashboard.
(after! tab-line
  (setq tab-line-tabs-function #'+my/tabs-window-buffers
        tab-line-tab-name-format-function #'+my/tabs-format
        tab-line-cache-key-function #'+my/tabs-cache-key
        tab-line-close-tab-function #'+my/tabs-close
        tab-line-close-button-show t
        tab-line-new-button-show nil      ; new buffers come from the usual commands
        tab-line-switch-cycling t)
  (dolist (mode '(treemacs-mode +doom-dashboard-mode))
    (add-to-list 'tab-line-exclude-modes mode)))

;; On with the first buffer opened (Doom's `doom-first-buffer-hook').
(add-hook 'doom-first-buffer-hook #'global-tab-line-mode)

;; CONTEXT ACTIONS
;; One menu (grouped, in vertico) with everything that applies at point:
;; - Spelling: suggestions and "add to dictionary", when spell-fu flagged the
;;   word at point.
;; - Code actions: the LSP server's quick fixes and refactors for the point or
;;   the active region (same list as SPC c a).
;; - Claude: send the error at point or the selection to Claude Code
;;   (agent-shell), either as a ready prompt (fix / explain) or into the prompt
;;   for you to finish.
;; - PDF: in a PDF (config/pdf.el, which adds its provider first), for
;;   the selected text: copy, search the PDF or the web, Claude; Preview, print.
;;
;; Each section comes from a provider: a function that returns a list of
;; (GROUP LABEL FUNCTION). To add more, write a provider and
;; (add-to-list '+my/context-action-providers #'my-provider t).
(defvar +my/context-action-providers
  '(+my/context-actions-spelling
    +my/context-actions-lsp
    +my/context-actions-claude)
  "Functions returning the actions available at point, as (GROUP LABEL FUNCTION).
The menu shows groups in this order.")

(defvar +my/context-actions-max-suggestions 5
  "How many spelling suggestions to show (aspell lists the likeliest first).")

;; EVIL
;; Saving a buffer returns to normal state.
(add-hook! 'after-save-hook #'evil-normal-state)

;; ====== KEY BINDINGS ======

(map! :leader :desc "Cycle case style" "c ~" #'string-inflection-all-cycle)

;; Q CLOSES TRANSIENT MENUS
;; Transient menus (agent-shell's help and drawing menus, magit's...) closed
;; with Esc (Doom binds it) or C-g, but q only said "Unbound suffix: q". q
;; closes them too now, like Vim's q and Doom's popups. A menu that uses q for
;; something of its own keeps it: in magit's dispatch it buries the buffer, in
;; blame and git-timemachine it quits those (`transient-bind-q-to-quit' would
;; move such keys to Q, and Q's to M-q; not done).
(after! transient
  (keymap-set transient-base-map "q" #'transient-quit-one)
  (keymap-set transient-sticky-map "q" #'transient-quit-seq))

;; TABS
(map! :n "gt" #'tab-line-switch-to-next-tab
      :n "gT" #'tab-line-switch-to-prev-tab)

;; Cmd+1..8 show the window's tabs 1-8, Cmd+9 its last, as in browsers (Doom
;; had them switch workspaces: M-1..9 and SPC TAB 1..9 still do); where there
;; are no tabs (side panels, popups), they switch workspaces, as before.
(map! :gn "s-1" #'+my/tabs-select-1
      :gn "s-2" #'+my/tabs-select-2
      :gn "s-3" #'+my/tabs-select-3
      :gn "s-4" #'+my/tabs-select-4
      :gn "s-5" #'+my/tabs-select-5
      :gn "s-6" #'+my/tabs-select-6
      :gn "s-7" #'+my/tabs-select-7
      :gn "s-8" #'+my/tabs-select-8
      :gn "s-9" #'+my/tabs-select-9)

;; Cmd+W closes the current tab, like its ✕ (Doom's closed the window, or the
;; workspace with its last window); where there are no tabs (popups, side
;; panels), the window, as before.
(map! "s-w" #'+my/tabs-close-current)

;; The tab menu (right click, see above).
(after! tab-line
  (keymap-set tab-line-tab-map "<tab-line> <down-mouse-3>" #'+my/tabs-context-menu))

;; OPTION+ENTER
;; Visual state too: code actions and Claude actions work on the selection.
(map! :nvi "M-RET" #'+my/context-actions)

;; Org keeps M-RET for "new heading/item".
(map! :after org :map org-mode-map :ni "M-RET" #'org-meta-return)

;; ====== CODE ======

;; In config/editor/, in this order: each part can use what the ones before it
;; define.
(load! "editor/margin")
(load! "editor/wrapped")
(load! "editor/fontify")
(load! "editor/smooth")
(load! "editor/modeline")
(load! "editor/tabs")
(load! "editor/actions")
