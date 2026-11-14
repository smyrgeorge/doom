;;; $DOOMDIR/config/search.el -*- lexical-binding: t; -*-
;; Search Everywhere on SPC s a. Loaded from config.el; its code is in
;; config/search/.

;; ====== VARIABLES ======

;; SEARCH EVERYWHERE
;; One list with tabs: Classes, Files,
;; Symbols and Actions. Typing searches all of them at once; to show one tab,
;; type its key then SPC (or `<' then the key): c Classes, f Files, s Symbols,
;; a Actions. `<<' (or DEL on an empty input) goes back to all.
;; - Classes / Symbols: the language server's workspace symbols, queried as you
;;   type (from 2 characters; only in buffers with an LSP server): each one's
;;   name, kind and container, then its file and line. Classes are classes,
;;   interfaces/traits, structs, enums and objects.
;; - Files: the project's files, recently opened ones first: each one's name,
;;   then its folder.
;; - Actions: every command (what M-x runs), as M-x lists them (recently used
;;   ones first, then the shortest), with their key bindings and docs.
;; What tells rows apart comes first: a narrow frame still shows it.
;; Emacs can't see a lone Shift key press on macOS, so there is no double Shift.

(defconst +my/search-everywhere--class-kinds '(5 10 11 19 23)
  "LSP SymbolKinds listed under Classes: Class, Enum, Interface, Object, Struct.")

;; ====== KEY BINDINGS ======

(map! :leader :desc "Search everywhere" "s a" #'+my/search-everywhere)

;; FIND IN FILES
;; Cmd+Shift+F: search the project's files (ripgrep, through Doom's SPC s p),
;; next to Cmd+F for the current buffer. With text selected, it searches for
;; that text.
(map! "s-F" #'+default/search-project)

;; On Linux Ctrl+Shift+F, as Linux's IDEs (in normal state Doom had it toggle
;; full screen: F11 still does).
(map! :unless (+my/macos-p)
      :gn "C-S-f" #'+default/search-project)

;; ====== CODE ======

;; In config/search/, in this order: each part can use what the ones before it
;; define.
(load! "search/symbols")
(load! "search/files")
(load! "search/actions")
(load! "search/everywhere")
