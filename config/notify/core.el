;;; $DOOMDIR/config/notify/core.el -*- lexical-binding: t; -*-
;; Defining kinds of notifications and firing them, turning them on and off.
;; Loaded from config/notify.el.

;; KINDS (see config/notify.el)
(defun +my/notify-define (kind title description)
  "Define notification KIND: shown under TITLE, DESCRIPTION saying what it's
about (in SPC t N). Defining it again replaces it."
  (setf (alist-get kind +my/notify-kinds) (list title description)))

(defun +my/notify-on-p (kind)
  "Non-nil if notifications are on, and KIND (defined) too."
  (and +my/notify-enabled
       (assq kind +my/notify-kinds)
       (not (memq kind +my/notify-off))))

;; EMACS IN FRONT
(defun +my/notify-emacs-in-front-p ()
  "Non-nil if a frame of Emacs has the focus. Not known (a terminal that
doesn't say): taken as in front, notifying nothing. Not the daemon's first
frame (it's no window: its focus is never known)."
  (seq-some (lambda (frame)
              (and (not (frame-initial-p frame))
                   (frame-focus-state frame)))
            (frame-list)))

;; FIRING ONE
(defun +my/notify--show (buffer)
  "A notification clicked: Emacs forward, on BUFFER if it's still there."
  (let ((window (and (buffer-live-p buffer) (get-buffer-window buffer t))))
    (select-frame-set-input-focus (if window (window-frame window) (selected-frame)))
    (cond (window (select-window window))
          ((buffer-live-p buffer) (pop-to-buffer buffer)))))

(cl-defun +my/notify (kind text &key buffer)
  "Notify of KIND, TEXT, if notifications and KIND are on and Emacs isn't in
front (see config/notify.el). BUFFER: what it's about, shown on a click.
Non-nil if it was shown."
  (when (and (+my/notify-on-p kind)
             (not (+my/notify-emacs-in-front-p)))
    (+my/os-notify (car (alist-get kind +my/notify-kinds)) text
                   (and buffer (lambda () (+my/notify--show buffer))))))

(defun +my/notify-test ()
  "Show a notification now, Emacs in front or not: does the desktop show
Emacs's? (See config/notify.el.)"
  (interactive)
  (if (+my/os-notify "Emacs" "Notifications work: Emacs can tell you what happened while you're away.")
      (message "Sent a notification: if none shows, let Emacs notify (macOS: System Settings > Notifications > Emacs)")
    (message "No notification: neither the desktop's (D-Bus) nor notify-send is there")))

;; ON AND OFF
(defun +my/notify-toggle ()
  "Turn all notifications on or off (SPC t n)."
  (interactive)
  (setq +my/notify-enabled (not +my/notify-enabled))
  (message "Notifications %s" (if +my/notify-enabled "on" "off")))

(defun +my/notify--kind-label (entry)
  "ENTRY of `+my/notify-kinds' as SPC t N lists it: its description, on or
off, its name."
  (pcase-let ((`(,kind ,_title ,description) entry))
    (format "%s (%s, %s)" description (if (memq kind +my/notify-off) "off" "on") kind)))

(defun +my/notify-toggle-kind (kind)
  "Turn notification KIND on or off (SPC t N: picked from them)."
  (interactive
   (let ((labels (mapcar (lambda (entry) (cons (+my/notify--kind-label entry) (car entry)))
                         (reverse +my/notify-kinds))))
     (unless labels
       (user-error "No notifications defined"))
     (list (cdr (assoc (completing-read "Turn on / off: " labels nil t) labels)))))
  (setq +my/notify-off (if (memq kind +my/notify-off)
                           (remq kind +my/notify-off)
                         (cons kind +my/notify-off)))
  (message "%s: %s" (nth 1 (alist-get kind +my/notify-kinds))
           (if (memq kind +my/notify-off) "off" "on")))
