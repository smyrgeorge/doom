# Patterns

Part of the agent-workflow skill: read [SKILL.md](../SKILL.md) first. Each checks with no error (the starters'
profiles).

## Something small

```yaml
name: quick
description: Something small, built, reviewed, merged.
for: [chore]
jobs:
  build:
    agent: build
  review:
    needs: build
    agent: review
    outcomes:
      approved: continue
      changes: rerun build
  merge:
    needs: review
    concurrency: 1
    uses: merge
    on-fail: build
```

## A bug, a failing test first

```yaml
name: bugfix
description: A bug, reproduced as a failing test first, fixed, reviewed, merged.
for: [bug]
jobs:
  reproduce:
    agent: test
    prompt: |
      Reproduce {issue}: {issue.title}, as a test that fails because of it.
  fix:
    needs: reproduce
    agent: build
    prompt: "Fix {issue}. The test that shows it: {jobs.reproduce.notes}"
  review:
    needs: fix
    agent: review
    outcomes:
      approved: continue
      changes: rerun fix
  merge:
    needs: review
    concurrency: 1
    uses: merge
    on-fail: build
```

## Reviews in parallel, an approval gate, a suite on the merge

```yaml
name: careful
description: Built and checked, reviewed and audited at once, approved by the user, merged after its suite.
for: [feature]
budget: {cost: 20}
jobs:
  build:
    steps:
      - agent: build
      - run: make test
        timeout: 20m
        retries: 2
  review:
    needs: build
    agent: review
    outcomes:
      approved: continue
      changes: rerun build
  security:
    needs: build
    agent: security
  approve:
    needs: [review, security]
    elisp: |
      (message "Ready for your OK: %s" (issue-title))
    approve: true
  merge:
    needs: approve
    concurrency: 1
    uses: merge
    with: {suite: make test}
    on-fail: build
```
