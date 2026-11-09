# Notifications

When something happens while you're in another app, a desktop notification says so: macOS's Notification Center,
Linux's notifications. Only while Emacs isn't in front; in Emacs, you see it there.

| Notification | When |
|---|---|
| Claude Code | A session's message, in its own words: when you asked to be told, or something needs you |
| Claude Code finished | A [Claude Code](claude-code.md) session finished its turn |
| Claude Code needs you | A session asks for your permission (to run a command, edit a file...) |

Claude sends its message itself (its system prompt says how and when):
`emacsclient --eval '(+my/notify-claude "The tests pass" "/its/working/directory")'`. Any code can call
`(+my/notify-claude TEXT DIRECTORY)` too: the notification names the project, a click shows its session.

| Key | Action |
|---|---|
| `SPC t n` | All notifications on / off |
| `SPC t N` | One kind on / off |

`M-x +my/notify-test` shows one now, to check that your desktop shows Emacs's: macOS asks once whether Emacs may notify
(System Settings → Notifications → Emacs). On Linux, a click brings Emacs forward on what it's about.

In `config.el`, `(setq +my/notify-enabled nil)` turns them all off, and
`(setq +my/notify-off '(claude claude-turn-done))` the kinds named.

## Adding one

A part in `config/notify/` defines its kind, then fires it from a hook of what it's about:

```elisp
(+my/notify-define 'build-done "Build" "A build finished")
(add-hook 'compilation-finish-functions
          (lambda (buffer status) (+my/notify 'build-done status :buffer buffer)))
```

`+my/notify` shows it only if notifications are on, its kind is on, and Emacs isn't in front.
