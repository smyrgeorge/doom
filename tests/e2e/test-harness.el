;;; tests/e2e/test-harness.el -*- lexical-binding: t; -*-
;; The end-to-end harness itself: a GUI Emacs, on screen, timers running while
;; a test waits, the browser stubbed.
(ert-deftest e2e-harness/gui-frame ()
  (should (display-graphic-p))
  (should (frame-visible-p (selected-frame))))
(ert-deftest e2e-harness/timers-run-while-waiting ()
  (let ((fired nil))
    (run-at-time 0.2 nil (lambda () (setq fired t)))
    (should (+test-wait-for (lambda () fired) 2))))
(ert-deftest e2e-harness/the-browser-never-opens ()
  (setq +test-browsed nil)
  (browse-url "https://example.com/never-opened")
  (should (equal +test-browsed '("https://example.com/never-opened"))))
