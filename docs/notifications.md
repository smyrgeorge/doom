# Notifications

When something happens while you're in another app, a desktop notification says so: macOS's Notification Center,
Linux's notifications. Only while Emacs isn't in front; in Emacs, you see it there.

| Notification | When |
|---|---|
| Claude Code | A session's message, in its own words: when you asked to be told, or something needs you |
| Claude Code finished | A [Claude Code](claude-code.md) session finished its turn, or stopped on an error (overloaded, logged out...) |
| Claude Code needs you | A session asks for your permission (to run a command, edit a file...) |
| Claude Code asks | A session asks you a question in its conversation (the question named) |
| Agent UI: a question | A session's turn ended with a [question waiting on its canvas](agent-ui.md#a-question-waiting), said instead of "finished" |
| Agent UI: a bug | A bug filed in [Agent UI's own issues](agent-ui.md#bugs-in-agent-ui) |
| Agent crew: a hand | An agent of a [crew](agent-workspace.md) wants your permission or asks you something, named: "ada (builder) wants to run npm install" |
| Agent crew: done | An agent finished its turn: "ada (builder) finished doom-a1b" |
| Agent crew: stuck | An error stopped an agent, saying why |
| Agent crew: napping | A [looping](agent-workspace.md#loops) agent found no ready issue left: "ada (builder) is napping: nothing to build" |
| Agent crew: a message | An agent's own message: "ada (builder): the tests pass" |

A crew's notifications come once per change, and a click opens its crew with that agent selected. Claude Code's own
aren't sent for a crew's sessions.

Claude sends its message itself (its system prompt says how and when):
`emacsclient --eval '(+my/notify-claude "The tests pass" "/its/working/directory")'`. Any code can call
`(+my/notify-claude TEXT DIRECTORY)` too: the notification names the project, a click shows its session. Two sessions
in one folder are told apart by their buffers' names (`doom`, `doom<2>`); a message is from the one whose turn is
running, or the one a third argument names (a buffer, or its name).

| Key | Action |
|---|---|
| `SPC t n` | All notifications on / off |
| `SPC t N` | One kind on / off |

`M-x +my/notify-test` shows one now, to check that your desktop shows Emacs's: macOS asks once whether Emacs may notify
(System Settings → Notifications → Emacs; Emacs in a terminal posts them as Script Editor's). On Linux, a click brings
Emacs forward on what it's about.

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
