;;; $DOOMDIR/config/emacs/libraries.el -*- lexical-binding: t; -*-
;; Emacs's own libraries this config uses, loaded when first used, not as
;; Emacs starts (config/emacs.el, LIBRARIES). Loaded from config/emacs.el,
;; first: the other files use it.
;;
;; Loading one costs ~8 ms here, however small it is (a native-compiled .eln
;; opened; its .elc loads in ~1.5): config.el's top-level `require's loaded 33
;; of them, 0.26 s of its 0.45 s (doom-djc.36). So no file requires them at
;; its top level. Their functions this config calls are autoloaded: by Emacs
;; (`browse-url', `url-hexify-string', `url-generic-parse-url',
;; `color-name-to-rgb', `color-blend', `text-property-search-forward',
;; `completing-read-multiple'...), else here. A function needing a library's
;; variable (to bind it) or its faces requires it first itself (`crm-separator'
;; in the agent-workflow package's issue picker, the ANSI faces in
;; config/agent-workspace/core.el).

(dolist (library '(("map" map-elt map-nested-elt map-put!)
                   ("svg" svg-create svg-image svg-node svg-text svg-circle svg-rectangle
                    svg-line svg-polyline svg-clip-path svg--append)
                   ("dom" dom-node)
                   ("xml" xml-escape-string)
                   ("parse-time" parse-iso8601-time-string)
                   ("iso8601" iso8601-parse)
                   ("mailcap" mailcap-file-name-to-mime-type)
                   ("browse-url" browse-url-file-url)
                   ("text-property-search" text-property-search-backward)
                   ("ansi-color" ansi-color-filter-apply)
                   ("filenotify" file-notify-add-watch file-notify-rm-watch file-notify-valid-p)
                   ("json" json-encode json-read)))
  ;; Nothing done for one already loaded (Doom's, or another package's).
  (dolist (function (cdr library))
    (autoload function (car library))))
