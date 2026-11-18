;;; tests/e2e/test-harness.el -*- lexical-binding: t; -*-
;; The end-to-end harness itself: a GUI Emacs, on screen, timers running while
;; a test waits, a wait's clock stopped while its page is hidden, the browser
;; stubbed.
(ert-deftest e2e-harness/gui-frame ()
  (should (display-graphic-p))
  (should (frame-visible-p (selected-frame))))
(ert-deftest e2e-harness/timers-run-while-waiting ()
  (let ((fired nil))
    (run-at-time 0.2 nil (lambda () (setq fired t)))
    (should (+test-wait-for (lambda () fired) 2))))
(ert-deftest e2e-harness/a-wait-s-clock-stops-while-its-page-is-hidden ()
  "A wait's clock stops while the frame's page is hidden (tests/helper.el's
A PAGE HIDDEN): hidden for 2 s (as WebKit says it, its frame covered or on a
Space not shown: stood in for, the screen not the test's), a 1 s wait for
what comes after them is met, its seconds hidden counted apart; shown all
along, the clock runs."
  (let ((shown-at (+ (float-time) 2)))
    (cl-letf (((symbol-function '+test--watch-pages-p) (lambda () t))
              ((symbol-function '+test--visibility-ask)
               (lambda () (setq +test--visibility (if (< (float-time) shown-at) "hidden" "visible")))))
      (should (+test-wait-for (lambda () (>= (float-time) shown-at)) 1))
      (should (> +test-hidden 1.5))
      (should-not (+test-wait-for #'ignore 1))
      (should (= +test-hidden 0)))))

(ert-deftest e2e-harness/the-browser-never-opens ()
  (setq +test-browsed nil)
  (browse-url "https://example.com/never-opened")
  (should (equal +test-browsed '("https://example.com/never-opened"))))
