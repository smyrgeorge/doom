;;; $DOOMDIR/config/agent-workspace/hands.el -*- lexical-binding: t; -*-
;; Raised hands answered from one place. Loaded from
;; config/agent-workspace.el, after room.el. No Doom here.
;;
;; A raised hand's options:
;; - a permission: agent-shell's own buttons in the agent's session (Allow,
;;   Always allow, Reject...), pressed as they are, from anywhere;
;; - a question on its Agent UI canvas, a choice: its options, answered as
;;   the canvas's own Answer button does (the answer sent to the agent, the
;;   question answered there);
;; - anything else (agent-shell's form, another kind of question): "go to
;;   it", its pane opened, the cursor on it.
;; They're buttons in the room's feed (under the hand; "→ Allow (you)" once
;; answered there; gone when it's answered elsewhere), on the agent's bar and
;; its pane's header line; A picks one; a goes to the next raised hand.

(require 'cl-lib)
(require 'seq)
(require 'subr-x)

(declare-function +my/agent-shell-permission-buttons "config/agent-shell/permissions")
(declare-function +my/agent-shell-press-permission "config/agent-shell/permissions")
(declare-function agent-ui-get "agent-ui/canvas")
(declare-function agent-ui-update "agent-ui/canvas")
(declare-function agent-ui-ask-answer-text "agent-ui/ask")
(declare-function agent-ui-ask-answered-text "agent-ui/ask")
(declare-function agent-ui-canvas-buffer-name "agent-ui/canvas")
(declare-function agent-ui--show-question "agent-ui/agent")
(declare-function agent-shell-jump-to-latest-permission-button-row "agent-shell")
(defvar agent-ui--canvas-name)

;; ====== A HAND'S OPTIONS ======

(defun agent-workspace--canvas-choice (agent)
  "AGENT's raised hand's question on its canvas, if it's a choice: (CANVAS
ID ELEMENT), CANVAS its name."
  (let ((ask (agent-workspace-agent-ask agent)))
    (when-let* ((canvas (plist-get ask :canvas))
                ((buffer-live-p canvas))
                (id (plist-get ask :id))
                (name (buffer-local-value 'agent-ui--canvas-name canvas))
                (element (ignore-errors (agent-ui-get id :canvas name))))
      (when (equal (plist-get element :type) "choice")
        (list name id element)))))

(defun agent-workspace-hand-options (agent)
  "AGENT's raised hand's options: ((LABEL . PRESS)...), PRESS a function of
no argument answering it so; nil if its hand isn't raised."
  (when (eq (agent-workspace-agent-state agent) 'hand)
    (let ((buffer (agent-workspace-agent-buffer agent)))
      (or
       ;; A permission: agent-shell's own buttons.
       (and (eq (plist-get (agent-workspace-agent-ask agent) :kind) 'permission)
            (buffer-live-p buffer)
            (fboundp '+my/agent-shell-permission-buttons)
            (mapcar (lambda (button)
                      (let ((label (car button)))
                        (cons label (lambda () (+my/agent-shell-press-permission buffer label)))))
                    (+my/agent-shell-permission-buttons buffer)))
       ;; A choice on its canvas: its options.
       (when-let* ((choice (agent-workspace--canvas-choice agent)))
         (pcase-let ((`(,canvas ,id ,element) choice))
           (mapcar (lambda (option)
                     (let ((label (if (stringp option) option (plist-get option :label))))
                       (cons label
                             (lambda ()
                               (agent-workspace-send
                                agent (agent-ui-ask-answer-text (format "choice %s" id)
                                                                (plist-get element :question)
                                                                (list label) nil)
                                :submit t)
                               (agent-ui-update id (list :answered (agent-ui-ask-answered-text (list label) nil))
                                                :canvas canvas)))))
                   (plist-get element :options))))
       ;; Anything else: go to it.
       (list (cons "Go to it" (lambda () (agent-workspace--go-to-hand agent))))))))

(defun agent-workspace--go-to-hand (agent)
  "AGENT selected, the cursor on what it asks: its permission's buttons (its
session shown), or its question (its canvas's tab shown: its own, ask...)."
  (let* ((ask (agent-workspace-agent-ask agent))
         (canvas (plist-get ask :canvas))
         (canvas (and (buffer-live-p canvas) (memq canvas (agent-workspace-agent-tabs agent)) canvas)))
    (if canvas
        (agent-workspace--tab-pick agent canvas)
      (agent-workspace--session-shown agent))
    (agent-workspace-select agent t)
    (if-let* ((window (and canvas (get-buffer-window canvas))))
        (progn
          (select-window window)
          ;; Agent UI's own: the cursor on it, all of it in view.
          (when-let* ((id (plist-get ask :id)))
            (ignore-errors (agent-ui--show-question canvas id t))))
      (when (buffer-live-p (agent-workspace-agent-buffer agent))
        (with-current-buffer (agent-workspace-agent-buffer agent)
          (ignore-errors (agent-shell-jump-to-latest-permission-button-row)))))))

(defun agent-workspace-hand-answer (agent label &optional key)
  "Answer AGENT's raised hand with its option LABEL (see
`agent-workspace-hand-options'): said in its room. KEY: only if it's still
the hand KEY names (`agent-workspace--ask-key': a button drawn for it),
else a user error, nothing answered."
  (when (and key (not (and (eq (agent-workspace-agent-state agent) 'hand)
                           (equal (agent-workspace--ask-key (agent-workspace-agent-ask agent)) key))))
    (user-error "%s no longer asks that: nothing answered" (agent-workspace-agent-name agent)))
  (let ((press (cdr (assoc label (agent-workspace-hand-options agent)))))
    (unless press
      (user-error "%s's hand has no option %s" (agent-workspace-agent-name agent) label))
    (let ((ask (agent-workspace-agent-ask agent)))
      (funcall press)
      (unless (equal label "Go to it")
        (agent-workspace--room-answered agent ask label)))))

;; ====== IN THE ROOM ======

(defun agent-workspace--ask-key (ask)
  "A raised hand's ASK, as the room's entry for it remembers it: its own
key (`agent-workspace--raise-hand')."
  (or (plist-get ask :key)
      (plist-get ask :request-id)
      (and (plist-get ask :id) (format "%s/%s" (plist-get ask :id) (plist-get ask :title)))
      (plist-get ask :title)))

(defun agent-workspace--room-answered (agent ask label)
  "AGENT's hand ASK answered LABEL from here: its room's entry says so."
  (let ((project (agent-workspace-agent-project agent))
        (key (agent-workspace--ask-key ask)))
    (when-let* ((buffer (and (agent-workspace--app project) (agent-workspace--room-buffer project))))
      (with-current-buffer buffer
        (dolist (entry agent-workspace--room-entries)
          (when (and (eq (plist-get entry :kind) 'hand)
                     (equal (plist-get entry :agent) (agent-workspace-agent-name agent))
                     (equal (plist-get entry :ask) key))
            (plist-put entry :answered label))))
      (agent-workspace--room-redraw-soon project))))

(defun agent-workspace--hand-buttons (agent ask-key)
  "Buttons for AGENT's raised hand, if it's still the one ASK-KEY names:
its options, each pressing it."
  (when (and (eq (agent-workspace-agent-state agent) 'hand)
             (equal (agent-workspace--ask-key (agent-workspace-agent-ask agent)) ask-key))
    (mapconcat (lambda (option)
                 (let ((label (car option)))
                   (propertize (concat "[" label "]")
                               'agent-workspace-button t
                               'face 'agent-workspace-button
                               'mouse-face 'highlight
                               'help-echo (format "%s: %s" (agent-workspace-agent-name agent) label)
                               'local-map (let ((map (make-sparse-keymap))
                                                (press (lambda () (interactive)
                                                         (agent-workspace-hand-answer agent label ask-key))))
                                            (define-key map [header-line mouse-1] press)
                                            map)
                               'keymap (let ((map (make-sparse-keymap))
                                             (press (lambda () (interactive)
                                                      (agent-workspace-hand-answer agent label ask-key))))
                                         (define-key map [mouse-1] press)
                                         (define-key map [header-line mouse-1] press)
                                         (define-key map (kbd "RET") press)
                                         map))))
               (agent-workspace-hand-options agent) " ")))

(defface agent-workspace-button '((t :inherit (warning bold)))
  "A raised hand's button."
  :group 'agent-workspace)

(defun agent-workspace--room-hand-line (project entry)
  "The line under a hand ENTRY in PROJECT's room: its buttons while it's
raised, what you answered from here, else nothing."
  (let ((indent (make-string agent-workspace--room-indent ?\s)))
    (cond
     ((plist-get entry :answered)
      (concat indent (propertize (format "→ %s (you)" (plist-get entry :answered)) 'face 'shadow)))
     ((when-let* ((agent (agent-workspace-agent (plist-get entry :agent) project))
                  (buttons (agent-workspace--hand-buttons agent (plist-get entry :ask))))
        (concat indent buttons (propertize "   A: answer, a: the next hand" 'face 'shadow)))))))

;; ====== THE COMMANDS ======

(defun agent-workspace-answer ()
  "Answer the raised hand of the agent here (else the next one): its
options picked from. Its hand changed while you pick: nothing answered,
said."
  (interactive)
  (let ((agent (agent-workspace--current)))
    (unless (eq (agent-workspace-agent-state agent) 'hand)
      (agent-workspace-next-hand)
      (setq agent (agent-workspace--current)))
    (unless (eq (agent-workspace-agent-state agent) 'hand)
      (user-error "No hand raised"))
    (let* ((options (agent-workspace-hand-options agent))
           ;; The hand asked: one asked meanwhile (output read as the prompt
           ;; waits) isn't answered with what you picked for this one.
           (key (agent-workspace--ask-key (agent-workspace-agent-ask agent)))
           (label (completing-read (format "%s %s: " (agent-workspace-agent-name agent)
                                           (agent-workspace-state-text agent))
                                   (mapcar #'car options) nil t nil nil (caar options))))
      (agent-workspace-hand-answer agent label key))))
