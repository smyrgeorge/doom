;;; $DOOMDIR/config/pdf/outline.el -*- lexical-binding: t; -*-
;; The outline in the minibuffer. Loaded from config/pdf.el.

;; THE OUTLINE IN THE MINIBUFFER (o)
;; The page's headings, as `parent › heading' with their page, in their order.
(defvar +my/pdf--outline-for nil
  "The PDF whose outline was asked for: WebKit's answer doesn't say.")

(defun +my/pdf-outline ()
  "o: go to a heading of the PDF's outline, picked in the minibuffer."
  (interactive)
  (setq +my/pdf--outline-for (current-buffer))
  ;; An answer awaited (see JAVASCRIPT in config/webkit/js.el).
  (unless (and (not +my/pdf--native)
               (+my/webkit-ask "window.pdfx ? pdfx.outlineList() : '[]'"
                               #'+my/pdf--outline-received))
    (message "No outline here (no PDF.js)")))

(defun +my/pdf--outline-received (json)
  "WebKit's answer to `+my/pdf-outline': the minibuffer after this
event, not inside it."
  (run-at-time 0 nil #'+my/pdf--outline-pick +my/pdf--outline-for json))

(defun +my/pdf--outline-pick (buffer json)
  "Pick one of the headings in JSON, BUFFER's page's, and go there."
  (let ((headings (and (stringp json)
                       (ignore-errors
                         (json-parse-string json :array-type 'list :object-type 'plist
                                            :null-object nil))))
        (separator (if (boundp '+my/sticky-separator) +my/sticky-separator " › "))
        (seen (make-hash-table :test #'equal))
        candidates)
    (if (not headings)
        (message "This PDF has no outline")
      (let ((index 0))
        (dolist (heading headings)
          (let* ((titles (plist-get heading :t))
                 (parents (butlast titles))
                 (name (concat (if parents
                                   (propertize (concat (string-join parents separator) separator)
                                               'face 'shadow)
                                 "")
                               (car (last titles))))
                 (count (puthash name (1+ (gethash name seen 0)) seen)))
            ;; Same names (two "Introduction"s) told apart.
            (when (> count 1)
              (setq name (concat name (propertize (format " (%d)" count) 'face 'shadow))))
            (push (list name index (plist-get heading :p)) candidates)
            (setq index (1+ index)))))
      (setq candidates (nreverse candidates))
      (let* ((annotate (lambda (name)
                         (when-let* ((page (nth 2 (assoc name candidates))))
                           (propertize (format "  p. %d" page) 'face 'completions-annotations))))
             (choice (completing-read
                      "Outline: "
                      (lambda (string predicate action)
                        (if (eq action 'metadata)
                            `(metadata (display-sort-function . identity)
                                       (cycle-sort-function . identity)
                                       (annotation-function . ,annotate))
                          (complete-with-action action candidates string predicate)))
                      nil t))
             (index (nth 1 (assoc choice candidates))))
        (when (and index (buffer-live-p buffer))
          (with-current-buffer buffer
            (+my/pdf--js (format "outlineGo(%d)" index))))))))
