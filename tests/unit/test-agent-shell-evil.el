;;; tests/unit/test-agent-shell-evil.el -*- lexical-binding: t; -*-
;; config/agent-shell.el's EVIL KEYS: RET in agent-shell per Evil state (it
;; sends in normal state too; in insert state too, or a newline if chosen),
;; and in a diff Claude shows (*agent-shell-diff*), the keys its header line
;; names, in normal state. With evil-collection's agent-shell keys, as Doom's
;; evil +everywhere sets them up. No agent: a buffer with agent-shell's keys,
;; and a real diff buffer.

;; Doom's `use-package!' reads it (Doom's package manager defines it).
(defvar doom-disabled-packages nil)

(require 'evil)
(+test-load "config/childframe" "config/banner" "config/webkit" "config/excalidraw"
            "config/agent-shell")
(require 'agent-shell)
(require 'agent-shell-diff)
;; evil-collection's agent-shell keys (n and p typed at the prompt, the
;; permission and g keys), as Doom's evil +everywhere loads them.
(require 'evil-collection)
(evil-collection-require 'agent-shell)
(evil-collection-agent-shell-setup)

;; ====== HELPERS ======

(defun +test-ase--key (key state &optional map)
  "What KEY runs (remapped, as typed) in a buffer with agent-shell's keys
\(or MAP's), in Evil STATE."
  (with-temp-buffer
    (use-local-map (or map agent-shell-mode-map))
    (evil-local-mode 1)
    (evil-change-state state)
    (key-binding (kbd key) t)))

;; ====== RET ======

(ert-deftest agent-shell-evil/ret-sends-in-both-states ()
  "RET sends in normal state too (Evil's moved a line down) and in insert
state as before; S-RET a newline, M-RET the other way of sending; n and p
typed at the prompt; evil-collection's keys kept."
  (should-not +my/agent-shell-insert-ret-newline)
  (should (eq (+test-ase--key "RET" 'normal) #'agent-shell-submit))
  (should (eq (+test-ase--key "RET" 'insert) #'agent-shell-submit))
  (should (eq (+test-ase--key "S-<return>" 'insert) #'newline))
  (should (eq (+test-ase--key "M-<return>" 'insert) #'agent-shell-submit-override))
  (should (eq (+test-ase--key "n" 'insert) #'self-insert-command))
  (should (eq (+test-ase--key "p" 'insert) #'self-insert-command))
  (should (eq (+test-ase--key "gx" 'normal) #'agent-shell-interrupt)))

(ert-deftest agent-shell-evil/ret-a-newline-in-insert-if-chosen ()
  "`+my/agent-shell-insert-ret-newline' set (in config.el, before the file
loads): RET in insert state a newline, the prompt sent from normal state."
  (unwind-protect
      (let ((+my/agent-shell-insert-ret-newline t))
        (+test-load "config/agent-shell")
        (should (eq (+test-ase--key "RET" 'insert) #'newline))
        (should (eq (+test-ase--key "RET" 'normal) #'agent-shell-submit))
        (should (eq (+test-ase--key "S-<return>" 'insert) #'newline)))
    (evil-define-key* 'insert agent-shell-mode-map (kbd "RET") nil)
    (+test-load "config/agent-shell"))
  (should (eq (+test-ase--key "RET" 'insert) #'agent-shell-submit)))

;; ====== THE DIFF ======

(ert-deftest agent-shell-evil/the-diff-s-keys-as-its-header-says ()
  "A diff Claude shows opens in normal state, where each key its header line
names does what it says: n / p the hunks, y accept, C-c C-c reject, RET
open the file, q quit; evil-collection's gy and gn kept."
  (let* ((dir (make-temp-file (+test-tmp-file "ase-") t))
         (file (expand-file-name "a.txt" dir))
         (done nil))
    (with-temp-file file (insert "one\ntwo\nthree\n"))
    (save-window-excursion
      (let ((buffer (agent-shell-diff
                     :diffs (list (list (cons :old "one\ntwo\nthree\n") (cons :new "1\ntwo\n3\n")
                                        (cons :file file)))
                     :on-accept (lambda () (push 'accepted done))
                     :on-reject (lambda () (push 'rejected done) t))))
        (unwind-protect
            (with-current-buffer buffer
              (evil-local-mode 1)
              (should (eq (evil-initial-state-for-buffer buffer) 'normal))
              (evil-change-state 'normal)
              ;; Its header line, agent-shell's: "  a.txt n next hunk  p
              ;; previous hunk  y accept ...", each key as found when the
              ;; diff opened. Each key it names, in normal state.
              (let ((named (split-string (string-remove-prefix
                                          "  a.txt " (substring-no-properties header-line-format))
                                         "  " t)))
                (pcase-dolist (`(,said ,command)
                               '(("next hunk" diff-hunk-next)
                                 ("previous hunk" diff-hunk-prev)
                                 ("accept" agent-shell-diff-accept-all)
                                 ("reject" agent-shell-diff-reject-all)
                                 ("open file" agent-shell-diff-open-file)
                                 ("quit" kill-current-buffer)))
                  (let ((segment (seq-find (lambda (s) (string-suffix-p (concat " " said) s)) named)))
                    (should segment)
                    (should (eq (key-binding (kbd (string-remove-suffix (concat " " said) segment)) t)
                                command)))))
              ;; The header's own keys too, and evil-collection's.
              (pcase-dolist (`(,key ,command)
                             '(("n" diff-hunk-next) ("p" diff-hunk-prev)
                               ("y" agent-shell-diff-accept-all) ("RET" agent-shell-diff-open-file)
                               ("C-c C-c" agent-shell-diff-reject-all) ("q" kill-current-buffer)
                               ("gy" agent-shell-diff-accept-all) ("gn" agent-shell-diff-reject-all)))
                (should (eq (key-binding (kbd key) t) command)))
              ;; y, typed: accepted, the diff closed.
              (execute-kbd-macro "y")
              (should (equal done '(accepted)))
              (should-not (buffer-live-p buffer)))
          (when (buffer-live-p buffer)
            (let ((kill-buffer-query-functions nil))
              (kill-buffer buffer)))
          (delete-directory dir t))))))
