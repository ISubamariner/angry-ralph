#!/bin/bash
set -euo pipefail

PROMPT_PARTS=()
MAX_ITERATIONS=0
STOP_WHEN="clean"
SCOPE="cumulative"
MODE="token-saving"

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Angry Ralph - Angry code reviewer in a self-referential loop

USAGE:
  /angry-ralph [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Task description (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>    Max iterations before auto-stop (default: unlimited)
  --stop-when <level>     clean|spotless|manual (default: clean)
  --scope <scope>         cumulative|latest (default: cumulative)
  --mode <mode>           token-saving|opus (default: token-saving)
  -h, --help              Show this help message

MODE:
  token-saving  Opus orchestrates; subagents run at sonnet (saves tokens)
  opus          Opus orchestrates; subagents run at opus (max quality)

STOP-WHEN LEVELS:
  clean     Stop when zero CRITICAL and zero IMPORTANT findings (NITPICKs ok)
  spotless  Stop when zero findings of ANY severity
  manual    Only stop at --max-iterations (no auto-completion)

SCOPE:
  cumulative  Review all changes since loop started (git diff from baseline)
  latest      Review only files changed in the most recent iteration

EXAMPLES:
  /angry-ralph Build a REST API --stop-when clean --max-iterations 10
  /angry-ralph Fix the auth bug --stop-when spotless --scope latest
  /angry-ralph Refactor cache --max-iterations 5 --stop-when manual

STOPPING:
  /cancel-angry-ralph    Cancel the active loop
  --max-iterations       Hard stop after N iterations
  --stop-when            Auto-stop when review passes threshold

MONITORING:
  grep '^iteration:' .claude/angry-ralph.local.md
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      # 0 = unlimited (set when --max-iterations is omitted); explicit 0 is rejected
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
        echo "❌ Error: --max-iterations requires a positive integer" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --stop-when)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --stop-when requires: clean, spotless, or manual" >&2
        exit 1
      fi
      case "$2" in
        clean|spotless|manual) STOP_WHEN="$2" ;;
        *)
          echo "❌ Error: --stop-when must be clean, spotless, or manual (got: $2)" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --scope)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --scope requires: cumulative or latest" >&2
        exit 1
      fi
      case "$2" in
        cumulative|latest) SCOPE="$2" ;;
        *)
          echo "❌ Error: --scope must be cumulative or latest (got: $2)" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --mode)
      if [[ -z "${2:-}" ]]; then
        echo "❌ Error: --mode requires: token-saving or opus" >&2
        exit 1
      fi
      case "$2" in
        token-saving|opus) MODE="$2" ;;
        *)
          echo "❌ Error: --mode must be token-saving or opus (got: $2)" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    *)
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

PROMPT="${PROMPT_PARTS[*]:-}"

if [[ -z "$PROMPT" ]]; then
  echo "❌ Error: No prompt provided" >&2
  echo "" >&2
  echo "   Examples:" >&2
  echo "     /angry-ralph Build a REST API --max-iterations 10" >&2
  echo "     /angry-ralph Fix the auth bug --stop-when spotless" >&2
  echo "" >&2
  echo "   For all options: /angry-ralph --help" >&2
  exit 1
fi

if echo "$PROMPT" | grep -qE '^\-\-\-[[:space:]]*$'; then
  echo "❌ Error: Prompt cannot contain a line that is exactly '---' (conflicts with state file format)" >&2
  exit 1
fi

if [[ -z "${CLAUDE_CODE_SESSION_ID:-}" ]]; then
  echo "⚠️  Warning: CLAUDE_CODE_SESSION_ID not set — concurrent sessions may interfere" >&2
fi

# Track tag for cleanup on failure
_CREATED_TAG=""
_cleanup_on_failure() {
  if [[ -n "$_CREATED_TAG" ]] && git rev-parse --is-inside-work-tree &>/dev/null; then
    git tag -d "$_CREATED_TAG" &>/dev/null || true
  fi
}
trap '_cleanup_on_failure' EXIT

BASELINE_REF=""
if [[ "$SCOPE" == "cumulative" ]]; then
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    _TS=$(date +%s%N 2>/dev/null)
    [[ "$_TS" =~ ^[0-9]+$ ]] || _TS=$(date +%s 2>/dev/null || echo "0")
    TIMESTAMP="${_TS}-$$-${RANDOM}"
    BASELINE_REF="angry-ralph-baseline-${TIMESTAMP}"
    git tag "$BASELINE_REF" HEAD
    _CREATED_TAG="$BASELINE_REF"
  else
    echo "⚠️  Not a git repo — falling back to --scope=latest" >&2
    SCOPE="latest"
  fi
fi

mkdir -p .claude

{
  printf '%s\n' '---'
  printf 'active: true\n'
  printf 'iteration: 1\n'
  printf 'session_id: %s\n' "${CLAUDE_CODE_SESSION_ID:-}"
  printf 'max_iterations: %s\n' "$MAX_ITERATIONS"
  printf 'stop_when: %s\n' "$STOP_WHEN"
  printf 'scope: %s\n' "$SCOPE"
  printf 'baseline_ref: %s\n' "$BASELINE_REF"
  printf 'mode: %s\n' "$MODE"
  printf 'started_at: "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '%s\n' '---'
  printf '\n'
  printf '%s\n' "$PROMPT"
} > .claude/angry-ralph.local.md

if [[ ! -s .claude/angry-ralph.local.md ]]; then
  echo "❌ Error: Failed to create state file" >&2
  _cleanup_on_failure
  exit 1
fi

cat <<EOF
🔥 Angry Ralph activated!

Iteration: 1
Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)
Stop when: $STOP_WHEN
Scope: $SCOPE
Mode: $MODE
$(if [[ -n "$BASELINE_REF" ]]; then echo "Baseline: $BASELINE_REF"; fi)

The angry reviewer will check your work after each pass.
Loop continues until the review comes back clean (or max iterations hit).

To cancel: /cancel-angry-ralph
To monitor: grep '^iteration:' .claude/angry-ralph.local.md

🔥
EOF

trap - EXIT

echo ""
echo "$PROMPT"
