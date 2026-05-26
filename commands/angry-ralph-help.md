---
name: angry-ralph-help
description: "Show Angry Ralph usage and help"
allowed-tools: []
hide-from-slash-command-tool: "true"
---

# Angry Ralph Help

Print the following help text to the user (do not modify it):

```
🔥 ANGRY RALPH — Angry code reviewer in a self-referential loop

USAGE:
  /angry-ralph PROMPT... [OPTIONS]

ARGUMENTS:
  PROMPT...    Task description (multiple words, no quotes needed)

OPTIONS:
  --max-iterations <n>    Max iterations before auto-stop (default: unlimited)
  --stop-when <level>     Completion threshold (default: clean)
  --scope <scope>         Diff scope for reviews (default: cumulative)
  --mode <mode>           token-saving|opus (default: token-saving)
  -h, --help              Show help in setup script

MODE:
  token-saving  Opus orchestrates; subagents run at sonnet (saves tokens)
  opus          Opus orchestrates; subagents run at opus (max quality)

STOP-WHEN LEVELS:
  clean      Stop when zero CRITICAL and zero IMPORTANT findings
             (NITPICKs are tolerated)
  spotless   Stop when zero findings of ANY severity
  manual     Only stop at --max-iterations (no auto-completion)

SCOPE:
  cumulative  Review all changes since loop started (git diff from baseline tag)
  latest      Review only files changed in the most recent iteration

EXAMPLES:
  /angry-ralph Build a REST API --max-iterations 10
  /angry-ralph Fix the auth bug --stop-when spotless --scope latest
  /angry-ralph Refactor cache layer --stop-when manual --max-iterations 5
  /angry-ralph Add user authentication --stop-when clean

HOW IT WORKS:
  1. You run /angry-ralph with a task
  2. Opus orchestrates — dispatches a worker agent (odd iterations = work pass)
  3. Opus tries to exit → hook blocks and triggers review
  4. Opus dispatches angry-reviewer agent (even iterations = review pass)
  5. If issues found → hook blocks and triggers fix pass
  6. Repeat until review passes threshold or max iterations hit

  In token-saving mode (default), subagents run at sonnet.
  In opus mode, subagents run at opus for maximum quality.

MONITORING:
  grep '^iteration:' .claude/angry-ralph.local.md

CANCELLING:
  /cancel-angry-ralph

STANDALONE AGENT:
  The angry-reviewer agent can also be used standalone (no loop)
  via the Agent tool for one-shot code reviews from any session.
```
