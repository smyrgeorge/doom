# Notifications

When something happens while you're in another app, a desktop notification says so: macOS's Notification Center,
Linux's notifications. Only while Emacs isn't in front; in Emacs, you see it there.

| Kind | When |
|---|---|
| `agent-shell-message` | A [session](agent-shell.md)'s message, in its own words: when you asked to be told, or something needs you |
| `agent-shell-turn-done` | A session finished its turn, or stopped on an error (overloaded, logged out...) |
| `agent-shell-permission` | A session asks for your permission (to run a command, edit a file...) |
| `agent-shell-question` | A session asks you a question in its conversation (the question named) |
| `agent-ui-question` | A session's turn ended with a [question waiting on its canvas](agent-ui.md#a-question-waiting), said instead of "finished" |
| `agent-ui-bug` | A bug filed in [Agent UI's own issues](agent-ui.md#bugs-in-agent-ui) |
| `agent-workspace-hand` | An agent of a [crew](agent-workspace.md) wants your permission or asks you something, named: "ada (builder) wants to run npm install" |
| `agent-workspace-done` | An agent finished its turn: "ada (builder) finished doom-a1b" |
| `agent-workspace-stuck` | An error stopped an agent, saying why |
| `agent-workspace-napping` | A [looping](agent-workspace.md#loops) agent found no ready issue left: "ada (builder) is napping: nothing to build" |
| `agent-workspace-message` | An agent's own message: "ada (builder): the tests pass" |
| `agent-workflow-needs-you` | A [workflow](agent-workflow.md)'s run waits for you, a click opening its pane |

A session's notifications are titled by its agent (`Claude`, `Codex`...), whichever it is. A crew's come once per
change, and a click opens its crew with that agent selected; a session's own aren't sent for a crew's sessions, nor for
a workflow run's.

The agent sends its message itself (it's told how and when):
`emacsclient --eval '(+my/notify-agent-shell "The tests pass" "/its/working/directory")'`. Any code can call
`(+my/notify-agent-shell TEXT DIRECTORY)` too: the notification names the project, a click shows its session. Two
sessions in one folder are told apart by their buffers' names (`doom`, `doom<2>`); a message is from the one whose turn
is running, or the one a third argument names (a buffer, or its name). `+my/notify-claude`, its old name, still works.

| Key | Action |
|---|---|
| `SPC t n` | All notifications on / off |
| `SPC t N` | One kind on / off |

`M-x +my/notify-test` shows one now, to check that your desktop shows Emacs's: macOS asks once whether Emacs may notify
(System Settings → Notifications → Emacs; Emacs in a terminal posts them as Script Editor's). On Linux, a click brings
Emacs forward on what it's about.

In `config.el`, `(setq +my/notify-enabled nil)` turns them all off, and
`(setq +my/notify-off '(agent-shell-message agent-shell-turn-done))` the kinds named (their old names, `claude`,
`claude-turn-done`, `agent-hand`..., still turn them off).

## Adding one

A part in `config/notify/`, named after the module it's about (`agent-shell.el`, `agent-workspace.el`), defines its
kinds (named after it too), then fires them from a hook of what it's about:

```elisp
(+my/notify-define 'build-done "Build" "A build finished")
(add-hook 'compilation-finish-functions
          (lambda (buffer status) (+my/notify 'build-done status :buffer buffer)))
```

`+my/notify` shows it only if notifications are on, its kind is on, and Emacs isn't in front; its `:title` names
something other than its kind's (a session's agent).
