;;; $DOOMDIR/examples/pdf.el -*- lexical-binding: t; -*-
;; Example: a PDF in WebKit, its pages dark (config/pdf.el, docs/pdf.md).
;; M-x +my/example-pdf writes a short report to the temp folder (three pages:
;; headings, text, coloured charts; an outline) and opens it in PDF.js, its
;; pages dark (as config.el has them; turned on if they're off):
;; inverted to dark greys, the charts' hues kept; a whole page in the window
;; (P).
;; Try j / k, J / K, / to search, O for the outline, SPC m d for light pages.
;; The file is deleted once it's closed, its place not kept, dark pages as
;; they were before.

;; ====== VARIABLES ======

(defconst +my/example-pdf--pages
  '(;; Page 1: the title, a paragraph, a bar chart.
    ((text bold 26 72 700 "Fruit shop: quarterly report")
     (text regular 13 72 676 "Sales, costs and the outlook for the third quarter" (0.40 0.40 0.45))
     (rect 72 660 468 2 (0.85 0.33 0.20))
     (text bold 16 72 620 "1  Sales")
     (text regular 11 72 598 "Sales grew by a fifth over the quarter. Apples are still the best seller, and plums,")
     (text regular 11 72 584 "new on the shelves since July, are already third. The chart shows each fruit's sales,")
     (text regular 11 72 570 "in crates sold per week.")
     (rect 112 380 60 160 (0.86 0.24 0.24))
     (rect 202 380 60 120 (0.30 0.68 0.33))
     (rect 292 380 60 96 (0.55 0.33 0.78))
     (rect 382 380 60 64 (0.96 0.60 0.13))
     (rect 100 378 360 1.5 (0.3 0.3 0.3))
     (text regular 10 124 364 "Apples")
     (text regular 10 218 364 "Pears")
     (text regular 10 309 364 "Plums")
     (text regular 10 393 364 "Oranges")
     (text bold 11 132 548 "50")
     (text bold 11 222 508 "38")
     (text bold 11 312 484 "30")
     (text bold 11 402 452 "20")
     (rect 72 250 468 80 (0.90 0.95 1.00))
     (rect 72 250 4 80 (0.20 0.45 0.85))
     (text bold 12 90 308 "Highlights")
     (text regular 11 90 290 "Best week: the first of September, 61 crates of apples.")
     (text regular 11 90 274 "Plums sold out twice: order more for the fourth quarter.")
     (text regular 9 72 60 "Fruit shop, quarterly report" (0.5 0.5 0.5))
     (text regular 9 520 60 "1" (0.5 0.5 0.5)))
    ;; Page 2: costs, as horizontal bars.
    ((text bold 16 72 700 "2  Costs")
     (text regular 11 72 678 "Costs rose less than sales: the margin is up two points. Transport is the largest,")
     (text regular 11 72 664 "then the shop's rent; packaging fell with the new reusable crates.")
     (text regular 11 72 620 "Transport")
     (rect 170 616 300 16 (0.13 0.59 0.95))
     (text regular 11 72 590 "Rent")
     (rect 170 586 220 16 (0.13 0.59 0.95))
     (text regular 11 72 560 "Staff")
     (rect 170 556 180 16 (0.13 0.59 0.95))
     (text regular 11 72 530 "Packaging")
     (rect 170 526 60 16 (0.10 0.74 0.61))
     (text regular 11 72 500 "Energy")
     (rect 170 496 90 16 (0.13 0.59 0.95))
     (text regular 10 480 620 "31%")
     (text regular 10 400 590 "23%")
     (text regular 10 360 560 "19%")
     (text regular 10 240 530 "6%")
     (text regular 10 270 500 "9%")
     (text bold 12 72 440 "Margin")
     (text regular 11 72 420 "Sales less costs, as a share of sales: 18% (16% a quarter ago).")
     (text regular 9 72 60 "Fruit shop, quarterly report" (0.5 0.5 0.5))
     (text regular 9 520 60 "2" (0.5 0.5 0.5)))
    ;; Page 3: the outlook, a timeline.
    ((text bold 16 72 700 "3  Outlook")
     (text regular 11 72 678 "The fourth quarter brings citrus season and the holidays. Three steps are planned:")
     (rect 72 600 468 3 (0.6 0.6 0.6))
     (rect 100 594 14 14 (0.86 0.24 0.24))
     (rect 280 594 14 14 (0.96 0.60 0.13))
     (rect 460 594 14 14 (0.30 0.68 0.33))
     (text bold 11 72 570 "October")
     (text regular 10 72 556 "More plums, a second")
     (text regular 10 72 543 "supplier.")
     (text bold 11 252 570 "November")
     (text regular 10 252 556 "Citrus stand by the")
     (text regular 10 252 543 "entrance.")
     (text bold 11 432 570 "December")
     (text regular 10 432 556 "Gift baskets, ordered")
     (text regular 10 432 543 "online.")
     (text regular 9 72 60 "Fruit shop, quarterly report" (0.5 0.5 0.5))
     (text regular 9 520 60 "3" (0.5 0.5 0.5))))
  "The report's pages: (text FONT SIZE X Y STRING [RGB]) and (rect X Y W H
RGB), in points from the bottom left of a US Letter page.")

(defconst +my/example-pdf--outline '(("Sales" . 1) ("Costs" . 2) ("Outlook" . 3))
  "The report's outline: (TITLE . PAGE).")

;; ====== CODE ======

(defun +my/example-pdf--string (text)
  "TEXT as a PDF string literal."
  (concat "(" (replace-regexp-in-string "[\\\\()]" "\\\\\\&" text) ")"))

(defun +my/example-pdf--rgb (rgb)
  (mapconcat (lambda (n) (format "%.2f" n)) rgb " "))

(defun +my/example-pdf--content (ops)
  "A page's content stream for OPS (see `+my/example-pdf--pages')."
  (mapconcat
   (lambda (op)
     (pcase op
       (`(text ,font ,size ,x ,y ,string . ,rgb)
        (format "%s rg BT /%s %s Tf %s %s Td %s Tj ET"
                (+my/example-pdf--rgb (or (car rgb) '(0.10 0.10 0.12)))
                (if (eq font 'bold) "F2" "F1") size x y (+my/example-pdf--string string)))
       (`(rect ,x ,y ,w ,h ,rgb)
        (format "%s rg %s %s %s %s re f" (+my/example-pdf--rgb rgb) x y w h))))
   ops "\n"))

(defun +my/example-pdf--write (file)
  "Write the report (see above) to FILE as a PDF; its xref table is right
\(offsets counted)."
  (let* ((pages (length +my/example-pdf--pages))
         (objects nil)
         (n 0)
         (new (lambda () (setq n (1+ n))))
         (catalog (funcall new))
         (pages-obj (funcall new))
         (regular (funcall new))
         (bold (funcall new))
         (page-objs (cl-loop repeat pages collect (funcall new)))
         (content-objs (cl-loop repeat pages collect (funcall new)))
         (outlines-obj (funcall new))
         (item-objs (cl-loop repeat (length +my/example-pdf--outline) collect (funcall new))))
    (push (cons catalog (format "<< /Type /Catalog /Pages %d 0 R /Outlines %d 0 R >>" pages-obj outlines-obj))
          objects)
    (push (cons pages-obj (format "<< /Type /Pages /Kids [%s] /Count %d >>"
                                  (mapconcat (lambda (o) (format "%d 0 R" o)) page-objs " ")
                                  pages))
          objects)
    (push (cons regular "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>") objects)
    (push (cons bold "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>") objects)
    (cl-loop for page in page-objs
             for content in content-objs
             for ops in +my/example-pdf--pages
             do (let ((stream (+my/example-pdf--content ops)))
                  (push (cons page (format "<< /Type /Page /Parent %d 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 %d 0 R /F2 %d 0 R >> >> /Contents %d 0 R >>"
                                           pages-obj regular bold content))
                        objects)
                  (push (cons content (format "<< /Length %d >>\nstream\n%s\nendstream" (length stream) stream))
                        objects)))
    (push (cons outlines-obj (format "<< /Type /Outlines /First %d 0 R /Last %d 0 R /Count %d >>"
                                     (car item-objs) (car (last item-objs)) (length item-objs)))
          objects)
    (cl-loop for (title . page) in +my/example-pdf--outline
             for item in item-objs
             for i from 0
             do (push (cons item (format "<< /Title %s /Parent %d 0 R%s%s /Dest [%d 0 R /XYZ 0 792 0] >>"
                                         (+my/example-pdf--string title) outlines-obj
                                         (if (> i 0) (format " /Prev %d 0 R" (nth (1- i) item-objs)) "")
                                         (if (nth (1+ i) item-objs) (format " /Next %d 0 R" (nth (1+ i) item-objs)) "")
                                         (nth (1- page) page-objs)))
                      objects))
    (let ((out "%PDF-1.4\n")
          (offsets nil))
      (dolist (object (sort objects (lambda (a b) (< (car a) (car b)))))
        (push (length out) offsets)
        (setq out (concat out (format "%d 0 obj\n%s\nendobj\n" (car object) (cdr object)))))
      (let ((xref (length out)))
        (setq out (concat out (format "xref\n0 %d\n0000000000 65535 f \n" (1+ n))
                          (mapconcat (lambda (offset) (format "%010d 00000 n \n" offset))
                                     (nreverse offsets) "")
                          (format "trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n"
                                  (1+ n) catalog xref))))
      (let ((coding-system-for-write 'binary))
        (write-region out nil file nil 'silent)))
    file))

(defun +my/example-pdf--dark (buffer)
  "Dark pages in BUFFER's PDF once PDF.js has opened it (15 s at most)."
  (let ((timer nil)
        (until (+ (float-time) 15)))
    (setq timer
          (run-with-timer
           0.2 0.2
           (lambda ()
             (let ((window (and (buffer-live-p buffer) (get-buffer-window buffer t))))
               (cond ((or (not window) (> (float-time) until))
                      (cancel-timer timer))
                     ((with-current-buffer buffer
                        (let ((state (+my/pdf--state)))
                          (and state (natnump (plist-get state :pages)) (> (plist-get state :pages) 0))))
                      (cancel-timer timer)
                      (with-selected-window window
                        (unless (plist-get (+my/pdf--state) :dark)
                          (+my/pdf-toggle-dark))
                        ;; A whole page, its chart too (P).
                        (+my/pdf-fit-page))))))))))

(defun +my/example-pdf ()
  "Example: a PDF in WebKit, its pages dark (deleted once closed). See
examples/pdf.el."
  (interactive)
  (let* ((dir (+my/example-folder "pdf"))
         (file (+my/example-pdf--write (expand-file-name "report.pdf" dir)))
         (dark +my/pdf-dark-pages))
    (delete-other-windows)
    (find-file file)
    (let ((buffer (current-buffer)))
      (+my/example-pdf--dark buffer)
      (+my/example-delete-when-closed
       dir (list buffer)
       ;; After the PDF's own closing (which keeps its place and settings).
       (lambda ()
         (run-at-time 0 nil (lambda ()
                              (setq +my/pdf-dark-pages dark)
                              (+my/pdf--forget-place file)))))
      (message "PDF example: j / k scroll, J / K pages, / searches, O the outline, SPC m d light pages")
      buffer)))

(defun +my/example-pdf-ready ()
  "Non-nil once the example's PDF is open in PDF.js, its pages dark."
  (seq-some (lambda (buffer)
              (and (eq (buffer-local-value 'major-mode buffer) '+my/pdf-mode)
                   (buffer-local-value '+my/example--closing buffer)
                   (with-current-buffer buffer
                     (let ((state (+my/pdf--state)))
                       (and state (plist-get state :dark)
                            (natnump (plist-get state :pages)) (> (plist-get state :pages) 0))))))
            (buffer-list)))

(provide 'example-pdf)
