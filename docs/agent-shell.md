# Your agent

A coding agent runs in an Emacs buffer through [agent-shell](https://github.com/xenodium/agent-shell). Yours is chosen
in `config.el`, Claude Code here. It can be any agent agent-shell speaks to over ACP: Codex, Gemini CLI, OpenCode, Qwen
Code, GitHub Copilot's CLI, Goose, Cursor's agent...

```elisp
(setq agent-shell-preferred-agent-config 'claude-code)   ; or codex, gemini-cli...; nil: asked each time
```

| Key | Action |
|---|---|
| `SPC o c` | A session with your agent, in a new [tiled](editor.md#tiling) pane. It asks for a new one or one to resume |
| `SPC o C` | The same, in the window you're in. The file there stays as a tab |
| `RET` | Send the prompt, in insert and normal state |
| `S-RET` | A newline in the prompt |
| `Option+Enter` (Linux: `Alt+Enter`) | Send the error at point or the selection to the agent |
| `M-x agent-shell` | Start any other agent, picked from agent-shell's list |

## Setting it up

- `scripts/tools.sh` installs your agent's adapter, or its CLI.
- To install others, name them in `AGENTS`: `AGENTS="codex gemini-cli" scripts/tools.sh`.
- Claude Code logs in with the `claude` CLI's login. Run `claude` once in a terminal.

Set these in `config.el`:

| Setting | Default | What |
|---|---|---|
| `agent-shell-preferred-agent-config` | `'claude-code` | Your agent. `nil` asks each time |
| `+my/agent-shell-insert-ret-newline` | `nil` | `t` makes `RET` in insert state a newline. The prompt is then sent with `RET` from normal state |
| `agent-shell-context-sources` | `'(files region)` | What a new session's prompt starts with. Add `error` and `line` for the error at point, or else the line you're on |
| `agent-shell-elicitation--experimental-feature-enabled` | `t` | A quick question as a form in the conversation. `nil` turns the forms off |

## Sessions

- A session's buffer is named after its agent: `Claude`, then `Claude<2>` and `Claude<3>`, in whichever project they
  run. Other agents' are named the same way (`Codex`, `Gemini`...).
- A session starts in insert state. Its prompt is empty but for what you chose: the selection, dired's marked files (or
  those in the selection there), or the image you're on.
- A session's mode line shows Nyan Cat for where you are in the conversation. Other buffers' mode lines don't.
- Sessions are told they run in Emacs. `path:line` references become links, images show inline in the theme's colours,
  and the agent can ask Emacs what you're looking at.
- Every agent is told the same. It's in the agent's system prompt where it takes one from Emacs, as Claude Code does.
  Otherwise it comes before the first message of a new session.
- While you're in another app, a [notification](notifications.md) says when a session finished its turn, stopped on an
  error, or asks for your permission. It's titled by the session's agent.
- Several sessions can work on one project at once, as a crew. Each is an agent with a name, a role and its own git
  worktree, run from one app (`SPC o w`, [Agent workspace](agent-workspace.md)).

## What the agent shows you

The agent shows you information under its conversation, each kind as the element that fits it: figures, tables,
charts, diagrams, plans, changes. Its reply keeps the words ([Agent UI](agent-ui.md)).

- Its questions come there too, as interactive elements: a list to pick from, options side by side, a yes or no, a
  form. Your answer becomes its next prompt.
- Only a quick question, with 2 to 4 short options, comes as a form in the conversation. The agent waits for your
  answer.
- The form is Claude Code's `AskUserQuestion`, or another agent's own tool if it has one. These forms are still
  experimental in agent-shell, and a [setting](#setting-it-up) turns them off.

## Diagrams in replies

The agent's ```` ```mermaid ```` blocks are drawn as diagrams in its replies, in the theme's colours
([Mermaid](mermaid.md)). The agent is told to use them for diagrams.

| Key | Action |
|---|---|
| `RET` or a click, on a diagram | Open it at full size |

- A block is drawn once it's complete. Until then, its source shows.
- With an error, Mermaid's message shows under the source.
- A diagram is no taller than the window.
- Copying a reply as Markdown keeps the source, and so does the transcript.

## The agent's diffs

A change the agent asks permission for opens as a diff. The keys its header line names work in normal state.

| Key | Action |
|---|---|
| `v` (in the session) | Open the change as a diff, while the agent waits for your permission |
| `n` (in the session) | Reject the change, and interrupt the agent |
| `n` / `p` (in the diff) | The next / previous hunk |
| `y` (in the diff) | Accept the change |
| `RET` (in the diff) | Open the file at the change |

## Drawing for the agent

In a session's buffer, `C-c C-d` opens a new [drawing](drawings.md) in a new pane. It's saved in the project's
`.agent-shell/drawings/`.

| Key | Action |
|---|---|
| `C-c C-d` (`SPC m d`), in a session | A new drawing for the agent |
| `C-c C-c` | Insert it into the prompt as an image, and close it |
| `C-c C-k` | Discard it |
| `M-p` / `M-n` | An earlier drawing instead, to change and insert again |

- The image is a PNG beside the drawing.
- An agent that takes no images gets the drawing's file instead, to read itself.

## Issues for the agent

In a project that tracks its [issues](issues.md) with Beads, the agent works with them through `bd`. Each `bd` command
the agent runs refreshes the issue lists and issues you have open, so its changes show as it makes them.

| Key | Action |
|---|---|
| `C-c C-i` (`SPC m i`), in a session | Pick one of the project's open issues for the prompt, ready ones first |
| `C-c C-a` (`SPC m a`), on an issue | Put it in the prompt of the project's session, from the list or the issue's own buffer |

- An issue goes into the prompt as `Beads issue ID: title`, for you to say what to do with it.
- A session started in the project is told it uses Beads, with Beads' own guide for agents (`bd prime`).
- Some projects' Claude Code settings run `bd prime` as a session starts, with a SessionStart hook. This config's
  `.claude/settings.json` does. Claude Code then gets the guide from there, not twice.
- Another agent reads none of those settings, and is given the guide.

## Profiling Emacs

When Emacs is slow, record a profile and hand it to your agent.

| Key | Action |
|---|---|
| `SPC h T` | Start the profiler. Do what's slow, then press it again to stop |

- The profile is written as text under `~/.config/emacs/.local/cache/profiles/`.
- A message says where it is, and tells the agent to read the [`emacs-profiling` skill](ai-agents.md) first. The
  message is also copied, to paste to your agent.
