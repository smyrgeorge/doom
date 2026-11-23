#!/usr/bin/env bash
# The examples' screenshots taken again (scripts/screenshots.sh) in the job's
# place (the issue's worktree), by the screenshots workflow
# (.agent-workflow/workflows/screenshots.yml). macOS only: Emacs, running it,
# needs the Screen Recording permission (System Settings > Privacy &
# Security > Screen & System Audio Recording).
#
# Exit status: 0 every example captured; 2 not (no permission, not macOS, an
# example that failed): the run asks you, no agent sent to fix what it can't.

if scripts/screenshots.sh "$@"; then
  exit 0
fi
echo "screenshots.sh: not every example was captured (above): see to it, then run the step again" >&2
exit 2
