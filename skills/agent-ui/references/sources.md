# Following a long command: sources

Part of the agent-ui skill: read [SKILL.md](../SKILL.md) first.

Your tool calls run one after another: while you wait on a command, nothing you'd update moves. Give the element a
**`source`** instead, and Emacs updates it from what happens, while you go on:

- `{"command": "make -j8"}`: Emacs runs it (in your directory, or `dir`); the reply names a `log` with all its output,
  for you to read later. When it ends: `done` (exit 0) or `failed` (else), patches where `$code` is the exit code; a
  progress bar is marked done or failed by itself.
- `{"file": "build.log", "from": "end"}`: a file followed as it grows (yours: `make > build.log 2>&1 &`).
- `{"poll": "df -h /", "every": 10}`: a command run every so many seconds.

Each line of its output that matches a rule's `match` changes the element: `set` as an update, `append` as an
append. In them, a string that's only `"$1"` is that group (a number if it reads as one), `"$0"` the match, and `$N`
in other text is replaced. `match` is a regular expression as in `grep -E` (groups, `\d`, `\s`, `\w`, `|`, `?`, `+`,
`*`, `{n,m}`), written in JSON: each `\` doubled (`\\d`, `\\[`). `tail: N` instead sets a `text` element to the last N
lines; `into: PROP` sets that property to all of it (a `diff`'s `diff`).

```sh
agent-ui show <<'EOF'
{"id": "build", "type": "progress", "title": "Build", "max": 1,
 "source": {"command": "ninja -C build",
            "match": "^\\[(\\d+)/(\\d+)\\] (.*)$",
            "set": {"value": "$1", "max": "$2", "label": "$3"}}}
EOF
agent-ui show <<'EOF'
{"id": "tests", "type": "table", "title": "Tests", "columns": ["Test", "Result"], "key": "Test",
 "source": {"command": "cargo test 2>&1",
            "rules": [{"match": "^test (\\S+) \\.\\.\\. (ok|FAILED|ignored)$",
                       "append": {"rows": [["$1", "$2"]]}}],
            "failed": {"title": "Tests: failed (exit $code)"}}}
EOF
agent-ui show <<'EOF'
{"id": "log", "type": "text", "title": "Server log", "text": "",
 "source": {"file": "server.log", "from": "end", "tail": 8}}
EOF
agent-ui show <<'EOF'
{"id": "mem", "type": "chart", "title": "Memory", "unit": "MB", "window": 60, "values": [],
 "source": {"poll": "ps -o rss= -p 4242", "every": 5,
            "match": "(\\d+)", "append": {"values": ["$1"]}}}
EOF
```

`agent-ui list` says how each source goes: `running`, `exit`, `lines` read, its `log`, and the `error` of a change its
rules made that the element refused (a value that isn't a number...), or why it couldn't run (its `dir` missing: the
element is shown without it, the `show` reply's `source` says so). A source stops when its element is removed or
shown again, or the session's canvas closes; its log is deleted then. To show progress from a script of your own, update the element from it
(`agent-ui update ...` in its loop; `batch` for many at once).
