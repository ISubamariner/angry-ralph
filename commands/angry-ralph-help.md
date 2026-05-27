---
name: angry-ralph-help
description: "Show Angry Ralph usage and help"
allowed-tools: ["Bash(bash * --help)"]
hide-from-slash-command-tool: "true"
---

# Angry Ralph Help

Run the setup script with `--help` to show usage:

```bash
bash scripts/setup-angry-ralph.sh --help
```

Then also append this additional context (not in the script help):

```
HOW IT WORKS:
  1. You run /angry-ralph with a task
  2. Opus orchestrates — dispatches a worker agent (odd iterations = work pass)
  3. Opus tries to exit → hook blocks and triggers review
  4. Opus dispatches angry-reviewer agent (even iterations = review pass)
  5. If issues found → hook blocks and triggers fix pass
  6. Repeat until review passes threshold or max iterations hit

  In token-saving mode (default), subagents run at sonnet.
  In opus mode, subagents run at opus for maximum quality.

STANDALONE AGENT:
  The angry-reviewer agent can also be used standalone (no loop)
  via the Agent tool for one-shot code reviews from any session.
```
