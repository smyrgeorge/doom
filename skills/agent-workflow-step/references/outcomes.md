# Outcomes, approval, loops, budgets

Part of the agent-workflow-step skill: read [SKILL.md](../SKILL.md) first.

## Outcomes

Your job's `outcomes` (what you're told lists them) say what follows your `done OUTCOME`:

| The workflow says | Then |
|---|---|
| `continue` (or `done`, always there) | your job is done; those that need it start |
| `rerun JOB` | JOB and every job after it run again, your notes its note: say exactly what to change, at file:line |

An outcome your job doesn't have is refused, and the reply says which it has.

## Approval

A step marked `approve` waits, once you've said done, for the user's OK. Rejected, you're told their note, in your
session: change what it says, then say done again. It waits for their OK again.

## Loops

Sending the work back is counted. Past the workflow's `max-rounds` (10), or after a round that changed nothing on the
branch, the run asks the user instead: they may go on (with a note for you, or for the job you sent it back to),
accept the result as it is, or stop. Send work back only for what matters (a bug, a missing test, the acceptance
criteria not met), not for taste: each round costs a full build and review.

## Budgets

A run may have a budget (cost, tokens, time). At 80% it's said; at its budget your session is stopped, its work kept,
and the user asked; going on, you're resumed, told so. Work to the point.

## Scripts after you

A job's steps run in order: a script after yours (tests, a check) sends its output back to you when it fails with 1.
Fix what it says, commit, say done: it runs again, up to its retries. Your job holds you to its last step.
