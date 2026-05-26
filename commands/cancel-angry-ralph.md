---
name: cancel-angry-ralph
description: "Cancel active Angry Ralph loop"
allowed-tools: ["Bash(test -f .claude/angry-ralph.local.md)", "Bash(rm .claude/angry-ralph.local.md)", "Read(.claude/angry-ralph.local.md)", "Bash(git tag -d *)"]
hide-from-slash-command-tool: "true"
---

# Cancel Angry Ralph

1. Check if `.claude/angry-ralph.local.md` exists: `test -f .claude/angry-ralph.local.md && echo "EXISTS" || echo "NOT_FOUND"`

2. **If NOT_FOUND**: Say "No active Angry Ralph loop found."

3. **If EXISTS**:
   - Read `.claude/angry-ralph.local.md` to get iteration and baseline_ref from frontmatter
   - Remove the state file: `rm .claude/angry-ralph.local.md`
   - If baseline_ref is not empty and matches the pattern `angry-ralph-baseline-[0-9]+-[0-9]+`, delete the git tag: `git tag -d -- "<baseline_ref>"` (ignore errors if not a git repo). Do NOT run git tag -d if the value doesn't match that pattern.
   - Report: "Cancelled Angry Ralph loop (was at iteration N)"
