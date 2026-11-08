;;; $DOOMDIR/config/lsp/capabilities.el -*- lexical-binding: t; -*-
;; What lsp-mode tells servers it supports, as strict servers read it.
;; Loaded from config/lsp.el.

;; INLINE COMPLETION
;; lsp-mode sends `"inlineCompletion": null' among its text document
;; capabilities: a server that reads them strictly refuses such an `initialize'
;; and never starts (TypeScript 7: "null value is not allowed for field
;; inlineCompletion"). The capability as an object instead, as the protocol
;; has it (other servers read it the same).
(defadvice! +my/lsp-inline-completion-capability-a (capabilities)
  :filter-return #'lsp--client-capabilities
  ;; New lists: the capabilities are partly a backquoted constant.
  (mapcar (lambda (entry)
            (if (eq (car-safe entry) 'textDocument)
                (cons 'textDocument
                      (mapcar (lambda (capability)
                                (if (equal capability '(inlineCompletion))
                                    '(inlineCompletion (dynamicRegistration . :json-false))
                                  capability))
                              (cdr entry)))
              entry))
          capabilities))
