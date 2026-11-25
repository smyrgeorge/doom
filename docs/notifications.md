# Notifications

When something happens while you're in another app, a desktop notification says so. It shows in macOS's Notification
Center, or in Linux's notifications. Notifications only come while Emacs isn't in front. In Emacs, you see what
happened there.

| Key | Action |
|---|---|
| `SPC t n` | All notifications on / off |
| `SPC t N` | One kind on / off |
| `M-x +my/notify-test` | Show one now, to check that your desktop shows Emacs's |

- macOS asks once whether Emacs may notify (System Settings → Notifications → Emacs). Emacs in a terminal posts them
  as Script Editor's.
- On Linux, a click brings Emacs forward on what it's about.

## Kinds

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
| `agent-workflow-message` | A run's agent's own message: "doom-a1b · feature, build: the tests pass", a click opening its pane |

- A session's notifications are titled by its agent (`Claude`, `Codex`...), whichever it is.
- A crew's notifications come once per change. A click opens its crew with that agent selected.
- A session's own notifications aren't sent for a crew's sessions, nor for a workflow run's.

## Settings

Set these in `config.el`:

| Setting | Default | What |
|---|---|---|
| `+my/notify-enabled` | `t` | `nil` turns all notifications off |
| `+my/notify-off` | `nil` | The kinds turned off, such as `'(agent-shell-message agent-shell-turn-done)` |

## The agent's own messages

The agent sends its own messages, the `agent-shell-message` kind. It's told how and when:

```sh
emacsclient --eval '(+my/notify-agent-shell "The tests pass" "/its/working/directory")'
```

- Any code can call `(+my/notify-agent-shell TEXT DIRECTORY)` too. The notification names the project, and a click
  shows its session.
- Two sessions in one folder are told apart by their buffers' names (`Claude`, `Claude<2>`). A message is from the
  session whose turn is running, or from the one a third argument names: a buffer, or its name.

## Adding one

A part in `config/notify/` defines its kinds, then fires them from a hook of what it's about. The part is named after
the module it's about (`agent-shell.el`, `agent-workspace.el`), and so are its kinds.

```elisp
(+my/notify-define 'build-done "Build" "A build finished")
(add-hook 'compilation-finish-functions
          (lambda (buffer status) (+my/notify 'build-done status :buffer buffer)))
```

- `+my/notify` shows it only if notifications are on, its kind is on, and Emacs isn't in front.
- Its `:title` gives it a title other than its kind's, such as a session's agent.
