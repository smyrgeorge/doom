;;; $DOOMDIR/config/pdf/actions.el -*- lexical-binding: t; -*-
;; Option+Enter on a PDF's selection. Loaded from config/pdf.el.

;; OPTION+ENTER (config/actions.el)
;; The menu's PDF actions, for the text selected in the page, which Emacs asks
;; the page for (an answer awaited, its function a symbol, as for copying)
;; before showing the menu.
(defvar-local +my/pdf--selection nil
  "The page's selected text while the actions menu is up.")

(defvar +my/pdf--actions-for nil
  "The PDF whose selection was asked for: WebKit's answer doesn't say.")

(defun +my/pdf-actions ()
  "Option+Enter: the actions menu, with the PDF's for its selected text."
  (interactive)
  (setq +my/pdf--actions-for (current-buffer))
  (unless (and (not +my/pdf--native)
               (+my/webkit-ask "window.pdfx ? pdfx.selection() : ''"
                               #'+my/pdf--selection-received))
    (+my/pdf--actions-menu (current-buffer) nil)))

(defun +my/pdf--selection-received (text)
  "WebKit's answer to `+my/pdf-actions': the menu after this event,
not inside it."
  (run-at-time 0 nil #'+my/pdf--actions-menu +my/pdf--actions-for text))

(defun +my/pdf--actions-menu (buffer text)
  "The actions menu for BUFFER's PDF, TEXT selected in it."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (setq +my/pdf--selection (and (stringp text) (not (string-blank-p text)) text))
      (unwind-protect (+my/context-actions)
        (setq +my/pdf--selection nil)))))

(defun +my/pdf--claude-context (text)
  "For `+my/claude-ask': TEXT quoted, after the PDF's file and page."
  (let ((file buffer-file-name)
        (page (plist-get (+my/pdf--state) :page)))
    (lambda (cwd)
      (let ((relative (and cwd file (file-relative-name file cwd))))
        (format "From %s%s:\n\n%s"
                (if (and relative (not (string-prefix-p ".." relative)))
                    relative
                  (abbreviate-file-name (or file (buffer-name))))
                (if (natnump page) (format ", page %d" page) "")
                (replace-regexp-in-string "^" "> " (string-trim text)))))))

(defun +my/context-actions-pdf ()
  "In a PDF: for its selected text, copy, search the PDF or the web, Claude;
always Preview and print."
  (when (derived-mode-p '+my/pdf-mode)
    (let ((text +my/pdf--selection)
          (buffer (current-buffer)))
      (append
       (when text
         (list (list "PDF" "Copy" (lambda () (+my/webkit-copied text)))
               (list "PDF" "Search the PDF for it"
                     (lambda () (with-current-buffer buffer (+my/pdf--find text))))
               (list "PDF" "Search the web for it"
                     (lambda ()
                       (require 'url-util)
                       (browse-url (concat "https://www.google.com/search?q="
                                           (url-hexify-string (string-trim text))))))
               (list "Claude" "Explain selection with Claude"
                     (lambda ()
                       (with-current-buffer buffer
                         (+my/claude-ask "Explain this passage. Don't change any files."
                                         (+my/pdf--claude-context text)))))
               (list "Claude" "Add selection to Claude prompt"
                     (lambda ()
                       (with-current-buffer buffer
                         (require 'agent-shell)
                         (agent-shell-insert
                          :text (funcall (+my/pdf--claude-context text) (agent-shell-cwd))
                          :shell-buffer (agent-shell-shell-buffer)))))))
       (list (list "PDF" "Open in Preview"
                   (lambda () (with-current-buffer buffer (+my/pdf-open-in-preview))))
             (list "PDF" "Print..."
                   (lambda () (with-current-buffer buffer (+my/pdf-print)))))))))

;; First in the menu (config/actions.el is loaded before this file).
(when (boundp '+my/context-action-providers)
  (add-to-list '+my/context-action-providers #'+my/context-actions-pdf))
