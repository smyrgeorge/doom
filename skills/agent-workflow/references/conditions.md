# if: and the variables

Part of the agent-workflow skill: read [SKILL.md](../SKILL.md) first.

## if:

One Lisp form, evaluated in the user's Emacs as the job is about to start (its needs done). It holds: the job runs;
else it's skipped (and counts as done for those that need it). An error in it: the run waits for the user. The check
only reads it.

| Helper | Is |
|---|---|
| `(issue-id)` | its id: `"doom-a1b"` |
| `(issue-type)` | its type, a symbol: `'bug`, `'feature` |
| `(issue-labels)` | its labels, a list of strings |
| `(issue-priority)` | 0 to 4 |
| `(issue-title)` | its title |
| `(job-outcome 'review)` | what a job said: `"approved"`, `"changes"`, `"done"`; nil before it |
| `(job-status 'build)` | `done`, `skipped`, `running`, `pending`... |

```yaml
if: (member "security" (issue-labels))
if: (and (eq (issue-type) 'bug) (<= (issue-priority) 1))
if: (not (equal (job-outcome 'review) "approved"))
```

In YAML, a form with `: ` in it goes in quotes, or under `if: |`.

## Variables

In a step's `prompt` and an agent's instructions, as `{NAME}`; in an agent's `tools` and `deny` too (filled in
shell-quoted). Anything else in braces that looks like one (`{word}`, `{a.b}`) is refused; `{ "a": 1 }` isn't one.

| Variable | Is |
|---|---|
| `{issue}`, `{issue.title}`, `{issue.description}`, `{issue.acceptance}`, `{issue.notes}` | the issue |
| `{branch}`, `{worktree}` | the issue's branch, where the step's agent works |
| `{main}`, `{main-branch}`, `{project}` | the user's checkout, its main branch, its folder's name |
| `{diff.stat}` | the branch's changes against the main branch |
| `{jobs.JOB.outcome}`, `{jobs.JOB.notes}` | what an earlier job said (JOB one of the workflow's) |
| `{output}` | a failing script's output |
| `{note}` | the user's, when it sent the work back |
| `{round}`, `{try}` | how many times round, how many tries |
