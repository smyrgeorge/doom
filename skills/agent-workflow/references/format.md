# A workflow's keys

Part of the agent-workflow skill: read [SKILL.md](../SKILL.md) first.

A workflow is `NAME.yml` (or `.yaml`): `NAME` a lowercase letter, then lowercase letters, digits or `-`.

## The workflow

| Key | Value | Check |
|---|---|---|
| `name` | its file's name | another name: an error |
| `description` | what it's for | none: a warning |
| `for` | an issue type, or a list: `[feature, task]` | not one of Beads' types: a warning |
| `concurrency` | how many of the pool's agents work on its runs at once | a whole number above 0 |
| `budget` | `cost` (dollars), `tokens`, `time` (`3h`, `90m`, `1h30m`) a run may spend | numbers above 0, a duration |
| `max-rounds` | how many times a job may send the work back before the run asks | a whole number above 0 |
| `jobs` | its jobs, each a name, then its keys | none: an error |

## A job

| Key | Value |
|---|---|
| `needs` | the job, or the list of jobs, it runs after; jobs that don't need each other run in parallel |
| `if` | one Lisp form: the job runs only if it holds as it's about to start ([conditions.md](conditions.md)) |
| `steps` | its steps, a list, in order; or one step's keys on the job itself (`agent: docs`) |
| `approve` | `true`: its last step's result waits for the user's OK |
| `outcomes` | what an agent's outcome does: `continue`, or `rerun JOB` (that job and every job after it again) |
| `max-rounds` | how many times this job may send the work back |
| `concurrency` | how many of it run at once, across the workflow's runs (`merge: 1`) |

## A step

One of these, and only one:

| Key | Does | With |
|---|---|---|
| `agent` | an LLM in agent-shell, with that profile | `prompt`: its first message (its variables filled in); none: its job on the issue |
| `run` | a script, by its shell | `shell`: bash by default, `python3`, `node`, any interpreter |
| `elisp` | Lisp in the user's Emacs | (quick: it blocks Emacs) |
| `uses` | a built-in: `merge` | `with`: `{suite: make test}` |

And: `timeout` (a duration: a script's), `retries` (how many times a script failing with 1 is fixed and run again; 0 by
default), `on-fail` (the profile of the agent sent to fix a step, in a job with no agent of its own), `approve`.

## What the check refuses

An error leaves the workflow out: YAML that doesn't parse; no jobs; a job's name that isn't one; `needs` naming no
job, or its own; needs going round (`a → b → a`); a step with no kind, or two; `agent` or `on-fail` naming no profile
of the project's; `uses` naming no built-in; `shell` without `run`; `prompt` on a step that isn't an agent's; an `if`
that isn't one Lisp form; `elisp` that isn't Lisp; a variable that isn't one; `jobs.X.notes` of no job; an outcome's
`rerun` naming no job; a number, duration or `true`/`false` that isn't one.

A warning keeps it: an unknown key; a `for` type Beads doesn't have; `{jobs.X.notes}` of a job not before it (empty
then); `retries` or `on-fail` on an agent step; no description; a `run:` of a file outside `.agent-workflow/`.
