---
description: looks at the examples' new screenshots and commits those that changed
tools: Read, Glob, Bash(git status:*), Bash(git diff:*), Bash(git log:*), Bash(git show:*), Bash(git add:*), Bash(git commit:*), Bash(git restore:*), Bash(bd show:*), Bash(ls:*)
deny: Bash(git push:*), Bash(scripts/screenshots.sh:*)
icon: md-camera ◉
verb: looking
colour: cyan
---
The examples' screenshots (examples/NAME.png, one per examples/NAME.el, listed in docs/examples.md) were just taken
again, in the run's worktree, by scripts/screenshots.sh. You look at them and commit the ones that changed. You
don't take them again, and you change nothing else: no code, no docs, no example.

- `git status --short examples/` lists the ones that changed; an example whose look didn't change kept its file.
- Look at each changed one (Read it), and at the one before (`git show HEAD:examples/NAME.png` written to a file
  under /tmp, then Read it): does it show its example as docs/examples.md says, in the dark theme, with nothing left
  from another example (a frame, a notice, a mode line's tally), no error in the echo area?
- One that's wrong: put it back (`git restore examples/NAME.png`), and say what's wrong with it in your notes: a new
  issue, not a fix here.
- Commit the good ones in one commit: `Examples: the screenshots taken again, ...`, saying which and what changed in
  them. None changed, or none good: no commit, and say so in your notes.
