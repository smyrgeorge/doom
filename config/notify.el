;;; $DOOMDIR/config/notify.el -*- lexical-binding: t; -*-
;; Desktop notifications, while Emacs isn't the app in front. Loaded from
;; config.el; its code is in config/notify/.

;; ====== VARIABLES ======

;; NOTIFICATIONS
;; Something you'd want to know while you're in another app (Claude Code
;; finished, Claude Code needs you) shows as a desktop notification: macOS's
;; Notification Center, Linux's notifications (`+my/os-notify', config/os.el).
;; Only while no Emacs frame has the focus: in Emacs, you see it there. Each
;; kind can be turned off on its own:
;;   SPC t n    all notifications on / off
;;   SPC t N    one kind on / off (picked from them)
;;   M-x +my/notify-test   one now, Emacs in front or not: does the desktop
;;              show Emacs's? (macOS asks once whether Emacs may notify)
;; In config.el, (setq +my/notify-enabled nil) turns them all off, and (setq
;; +my/notify-off '(KIND...)) the kinds named.
;;
;; ADDING ONE: a part in config/notify/ for what notifies (claude.el: Claude
;; Code's sessions) defines its kind, then fires it from a hook of that thing:
;;   (+my/notify-define 'KIND "Title" "What it's about, in SPC t N")
;;   (+my/notify 'KIND "What happened" :buffer BUFFER)
;; `+my/notify' shows it only if notifications are on, KIND is on and Emacs
;; isn't in front; a click (Linux) brings Emacs forward on BUFFER.
;;
;; Notifications so far (config/notify/claude.el):
;; - claude-turn-done: a Claude Code session finished its turn;
;; - claude-permission: a Claude Code session asks for your permission (to
;;   run a command, edit a file...);
;; - claude-question: a Claude Code session asks you a question in its
;;   conversation (a form; its turn waits for the answer);
;; - claude: a message the caller words, `+my/notify-claude': Claude
;;   itself, through emacsclient (its system prompt says how and when: what
;;   you asked to be told, what needs you), or any code.
;; And Agent UI's (config/notify/agent-ui.el):
;; - agent-ui-bug: a bug filed in Agent UI's own issues (by the agent, or b
;;   on a canvas element);
;; - agent-ui-question: a session's turn ended with a question waiting on its
;;   canvas (a choice, rows to pick): said instead of claude-turn-done.
(defvar +my/notify-enabled t
  "Desktop notifications on (see above); SPC t n toggles it.")

(defvar +my/notify-off nil
  "The kinds of notifications turned off (see above); SPC t N toggles one.")

(defvar +my/notify-kinds nil
  "The kinds of notifications, (KIND TITLE DESCRIPTION), each defined by the
part that fires it (`+my/notify-define').")

;; ====== KEY BINDINGS ======

(map! :leader
      :desc "Notifications"        "t n" #'+my/notify-toggle
      :desc "A notification's kind" "t N" #'+my/notify-toggle-kind)

;; ====== CODE ======

;; In config/notify/, in this order: each part can use what the ones before it
;; define.
(load! "notify/core")
(load! "notify/claude")
(load! "notify/agent-ui")
