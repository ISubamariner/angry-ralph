---
name: angry-ralph
description: "Start Angry Ralph review-fix loop"
argument-hint: "PROMPT [--max-iterations N] [--stop-when clean|spotless|manual] [--scope cumulative|latest] [--mode token-saving|opus]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-angry-ralph.sh:*)", "Agent", "Read", "Edit", "MultiEdit", "Write", "Bash(git diff *)", "Bash(git status)", "Bash(git tag *)", "Grep", "Glob"]
hide-from-slash-command-tool: "true"
---

# Angry Ralph

Execute the setup script to initialize the loop:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-angry-ralph.sh" $ARGUMENTS
```

Work on the task. When you try to exit, the Angry Ralph hook will alternate between:
- **Work passes** (odd iterations): dispatch a general-purpose agent to work on the task or fix issues
- **Review passes** (even iterations): dispatch the angry-ralph:angry-reviewer agent to review changes

You are the **orchestrator**. On the first pass, simply work on the task directly. After that, the hook will tell you which Agent to dispatch and with what parameters. Follow its instructions to dispatch the correct agent with the correct model.

CRITICAL RULES:
- Only output `<review-result>CLEAN</review-result>` when the review agent found genuinely zero CRITICAL and zero IMPORTANT issues
- Only output `<review-result>SPOTLESS</review-result>` when the review agent found genuinely zero issues of any severity
- Do NOT output false review results to escape the loop
- The loop continues until the review genuinely passes or max iterations is reached
