# Angry Ralph

Angry code reviewer in a self-referential loop. Dispatches a brutally honest reviewer agent to audit your code, fixes the issues it finds, then reviews again — repeating until the review comes back clean.

Built as a [Claude Code](https://docs.anthropic.com/en/docs/claude-code) plugin.

## Install

```bash
claude plugin add https://github.com/ISubamariner/angry-ralph
```

## Quick Start

```
/angry-ralph Build a REST API --max-iterations 10
```

Angry Ralph will:
1. Work on your task (iteration 1)
2. Review the changes with a brutal code audit (iteration 2)
3. Fix every CRITICAL and IMPORTANT issue found (iteration 3)
4. Review again (iteration 4)
5. Repeat until the review comes back clean or max iterations hit

## Usage

```
/angry-ralph PROMPT [--max-iterations N] [--stop-when LEVEL] [--scope SCOPE] [--mode MODE]
```

### Options

| Flag | Values | Default | Description |
|------|--------|---------|-------------|
| `--max-iterations` | any positive integer | unlimited | Hard stop after N iterations |
| `--stop-when` | `clean`, `spotless`, `manual` | `clean` | Quality threshold for auto-stop |
| `--scope` | `cumulative`, `latest` | `cumulative` | What code the reviewer looks at |
| `--mode` | `token-saving`, `opus` | `token-saving` | Which model runs the subagents |

### Stop-when levels

- **clean** — Stop when zero CRITICAL and zero IMPORTANT findings. NITPICKs are tolerated.
- **spotless** — Stop when zero findings of ANY severity, including NITPICKs.
- **manual** — Never auto-stop. Only stops at `--max-iterations`.

### Scope

- **cumulative** — Review ALL changes since the loop started (uses a git baseline tag). Best for catching regressions across iterations.
- **latest** — Review only files changed in the most recent iteration. Faster but may miss cross-iteration issues.

### Mode

- **token-saving** (default) — Opus orchestrates, subagents run at Sonnet. Good balance of quality and cost.
- **opus** — Opus orchestrates, subagents run at Opus. Maximum quality, higher token usage.

## How It Works

Angry Ralph uses the [Ralph loop technique](https://www.anthropic.com/engineering/claude-code-best-practices) — a Stop hook that intercepts Claude's exit attempts and injects the next iteration's prompt.

Each loop alternates between two phases:

- **Work pass** (odd iterations): A general-purpose agent works on the task or fixes issues from the last review
- **Review pass** (even iterations): The angry-reviewer agent audits all changes and categorizes findings as CRITICAL, IMPORTANT, or NITPICK

The loop stops when:
- The review meets the `--stop-when` threshold, OR
- `--max-iterations` is reached, OR
- You run `/cancel-angry-ralph`

### The Angry Reviewer

The reviewer checks for:
- **Security**: data leaks, injection attacks, OWASP top 10, hardcoded secrets
- **Correctness**: null crashes, error handling gaps, race conditions, resource leaks, missing validation
- **Quality**: test coverage, codebase consistency

It's angry, but fair — every finding includes a specific fix recommendation.

## Standalone Reviews

The angry-reviewer agent can be used outside the loop for one-shot reviews. Claude Code will auto-dispatch it when you ask for a "brutal review" or "angry code review".

## Monitoring & Cancellation

```bash
# Check current iteration
grep '^iteration:' .claude/angry-ralph.local.md

# Cancel the loop
/cancel-angry-ralph
```

## Requirements

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- Bash (included on macOS/Linux; Git Bash on Windows)
- Git (recommended for cumulative scope; falls back to latest scope without it)

## License

MIT
