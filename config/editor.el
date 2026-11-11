;;; $DOOMDIR/config/editor.el -*- lexical-binding: t; -*-
;; The editor: editing, scrolling, tabs, Option+Enter, getting around, the
;; sticky header, spelling, tree-sitter grammars, long lines, Evil, the mode
;; line. Loaded from config.el; its code is in config/editor/.

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
;; sessions, dired, magit, new buffers (SPC b N) and the buffer list (SPC b i)
;; get tabs; other buffers only while shown. With
;; Doom's workspaces, a window's tabs are the current workspace's buffers only
;; (a new workspace starts in the last one's window, its history with it).
;; Closing a tab (its ✕, a middle click) takes it off that window, which goes
;; back to the tab it showed before; closing its last tab closes the window
;; (the frame's only one, beside side panels, shows Doom's dashboard instead).
;; A file is closed too once no window has it as a tab any more (asking first
;; if it has unsaved changes); so is the buffer list (SPC b i), q too. A
;; Claude session only leaves the tab line: close it with its own commands.
;; Tabs look as they did: an icon, a bar on the current one, • when unsaved.
;; Right-clicking a tab: Emacs's Close and Close other tabs, and
;; Split Vertically (a pane on the right) and Split Horizontally (below): the
;; new pane has only that tab and takes focus; the tab stays where it was too.
(defvar +my/tabs-height 22
  "Height of the tab row in graphical frames, in pixels.")

(defvar +my/tabs-bar-width 2
  "Width of the bar marking the current tab, in pixels.")

(defvar +my/tabs-real-modes '(ibuffer-mode)
  "Major modes whose buffers keep a tab though they visit no file, as files
do: in the workspace, listed by SPC b b, killed once no window has them as
a tab (q too). The buffer list (SPC b i).")

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

;; STICKY HEADER
;; The header line of code windows shows the classes/functions the top visible
;; line is inside, once their first lines have scrolled out of view: e.g.
;; "class Foo › def bar(self):". Otherwise it
;; shows the file's path in the project. Nested scopes come from tree-sitter
;; where the major mode uses it; other modes get the enclosing defun only.
;; In Markdown (markdown-ts-mode) the scopes are the headings: "# Guide › ## Setup".
;; The header row is always there, so the text doesn't shift when it changes.
;; Only where scopes can be told (e.g. not in HTML: web-mode has no notion of
;; them): elsewhere there's no header row.
(defvar +my/sticky-separator " › "
  "Between the scopes in the header.")

(defvar +my/sticky-defun-types
  '((kotlin . "\\`\\(class\\|object\\|function\\)_declaration\\'\\|\\`companion_object\\'"))
  "Tree-sitter node types of the scopes the sticky header shows (classes,
functions), by language, for languages whose mode declares neither its
defuns nor an outline (kotlin-ts-mode); the others' come from their mode.
An entry overrides a mode's own (set in config.el).")

;; SPELLING
;; CAMELCASE
;; Check identifiers like AgreementController as Agreement + Controller
;; instead of flagging them whole. Only applies to words that
;; would otherwise be marked as misspelled.
(setq spell-fu-word-delimit-camel-case t)

;; TECH WORDS
;; dict/tech.txt holds ~40k programming words English lacks (rect, rgba, async,
;; kotlin, stdout, postgres...), built by scripts/dict.sh from cspell's
;; dictionaries. Load it in every spell-checked buffer, next to English and the
;; personal dictionary. It's read-only, so zg / "Add to dictionary" still go to
;; the personal dictionary without asking which one.
(defvar +my/spell-tech-words-file (expand-file-name "dict/tech.txt" doom-user-dir))

;; TREE-SITTER GRAMMARS
;; The first file of a language asked to download and build its tree-sitter
;; grammar (Doom's "Missing tree-sitter grammars: ... Install now?"). Instead,
;; once Emacs has started and been idle a moment, every grammar the enabled
;; languages need (what their modules in init.el register with
;; `set-tree-sitter!') that isn't there yet is downloaded and built, with the
;; same recipes, into Doom's grammar folder (.local/etc/tree-sitter). In the
;; background: another Emacs (`emacs --batch') builds them, as building them
;; here would freeze Emacs for minutes. Its output is in *tree-sitter
;; grammars*; a message says when it starts and ends. A language enabled later
;; (init.el, `doom sync') gets its grammars at the next start.
;; M-x +my/tree-sitter-install-grammars does it now.
(defvar +my/tree-sitter-install-delay 10
  "Idle seconds after startup before missing grammars get built; nil: never.")

(defconst +my/tree-sitter-buffer "*tree-sitter grammars*"
  "Where the build's output goes.")

;; LONG LINES
;; Files with very long lines (e.g. an HTML report embedding its data as one
;; 50,000-character line) open in `so-long-mode', which still wraps them: one
;; line then fills screens of rows, and each scroll step over it lays it all out
;; again (~60 ms a step: the scroll stuttered). Don't wrap there (~13 ms): the
;; line takes one row; M-x toggle-truncate-lines to read it wrapped.
;; Lines over 5,000 characters count as very long (Doom keeps Emacs's 10,000
;; in native-comp builds): an HTML report with 7,000-character SVG lines stayed
;; in web-mode, where redisplay walks each such line character by character
;; (highlighting, ligatures), ~6 ms a line a pass: scrolling stalled for
;; seconds. A notice says so, with the way back (editor/long-lines.el).
(defvar +my/long-line-threshold 5000
  "Files with lines longer than this many characters open in `so-long-mode'.")

(after! so-long
  (setq so-long-threshold +my/long-line-threshold)
  (setf (alist-get 'truncate-lines so-long-variable-overrides) t))

;; LARGE FILES
;; Decided before a file's mode runs, not after (editor/large-files.el): very
;; long lines open in `so-long-mode' at once, the file's own mode never run; a
;; large file (more lines than Doom's `doom-file-lines-threshold-alist', 20,000
;; here, or bigger than this) opens in its own mode without the language
;; server, spelling, syntax checking, the sticky header and the stripe, with a
;; notice and Open normally (asked first over the second size).
(defvar +my/large-file-size (* 1024 1024)
  "Files bigger than this many bytes open light (see above).")

(defvar +my/large-file-ask-size (* 10 1024 1024)
  "Opening normally a large file bigger than this asks first.")

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

;; On Linux also Ctrl+1..9 (config/os.el, KEYS), as Linux's browsers (Alt+1..9
;; stay Doom's workspaces).
(map! :unless (+my/macos-p)
      :gn "C-1" #'+my/tabs-select-1
      :gn "C-2" #'+my/tabs-select-2
      :gn "C-3" #'+my/tabs-select-3
      :gn "C-4" #'+my/tabs-select-4
      :gn "C-5" #'+my/tabs-select-5
      :gn "C-6" #'+my/tabs-select-6
      :gn "C-7" #'+my/tabs-select-7
      :gn "C-8" #'+my/tabs-select-8
      :gn "C-9" #'+my/tabs-select-9)

;; Cmd+W closes the current tab, like its ✕ (Doom's closed the window, or the
;; workspace with its last window); where there are no tabs (popups, side
;; panels), the window, as before.
(map! "s-w" #'+my/tabs-close-current)

;; On Linux also Ctrl+Shift+W (Ctrl+W is Vim's windows), as Linux's terminals.
(map! :unless (+my/macos-p) "C-S-w" #'+my/tabs-close-current)

;; The tab menu (right click, see above).
(after! tab-line
  (keymap-set tab-line-tab-map "<tab-line> <down-mouse-3>" #'+my/tabs-context-menu))

;; OPTION+ENTER
;; Visual state too: code actions and Claude actions work on the selection.
(map! :nvi "M-RET" #'+my/context-actions)

;; Org keeps M-RET for "new heading/item".
(map! :after org :map org-mode-map :ni "M-RET" #'org-meta-return)

;; GO TO DECLARATION OR USAGES
;; Cmd+B on a symbol: on a use, jump to its declaration; on the
;; declaration itself, list its usages (Enter opens one). Cmd+[ goes back.
(map! "s-b" #'+my/goto-declaration-or-usages)

;; On Linux Ctrl+Shift+B (Ctrl+B is Vim's page up).
(map! :unless (+my/macos-p) "C-S-b" #'+my/goto-declaration-or-usages)

;; BACK / FORWARD
;; Cmd+[ / Cmd+]: back / forward through the places the cursor jumped from and
;; to (better-jumper).
(map! "s-[" #'better-jumper-jump-backward)

(map! "s-]" #'better-jumper-jump-forward)

;; On Linux Alt+← / Alt+→, as browsers (C-o / C-i too, Vim's); in insert
;; state they still move by words.
(map! :unless (+my/macos-p)
      :nvm "M-<left>"  #'better-jumper-jump-backward
      :nvm "M-<right>" #'better-jumper-jump-forward)

;; PREVIOUS / NEXT BUFFER
;; M-[ / M-], GUI only: in a terminal, M-[ / M-] are ESC [ / ESC ], the
;; prefixes of escape sequences (mouse, focus, OSC), so binding them flips
;; buffers. (Defined here: the bindings call it as this file loads.)
(defun +my/gui-only (cmd)
  `(menu-item "" ,cmd :filter ,(lambda (c) (when (display-graphic-p) c))))

(map! "M-[" (+my/gui-only #'previous-buffer)
      "M-]" (+my/gui-only #'next-buffer))

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
(load! "editor/navigation")
(load! "editor/sticky")
(load! "editor/spell")
(load! "editor/tree-sitter")
(load! "editor/long-lines")
(load! "editor/large-files")
