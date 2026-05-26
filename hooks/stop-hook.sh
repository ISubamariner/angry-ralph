#!/bin/bash
set -euo pipefail

HOOK_INPUT=$(cat)

RALPH_STATE_FILE=".claude/angry-ralph.local.md"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Strip \r and parse frontmatter (|| true on grep to prevent pipefail crash on missing keys)
FRONTMATTER=$(tr -d '\r' "$RALPH_STATE_FILE" | sed -n '/^---$/,/^---$/{ /^---$/d; p; }')
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//' || true)
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' || true)
STOP_WHEN=$(echo "$FRONTMATTER" | grep '^stop_when:' | sed 's/stop_when: *//' || true)
SCOPE=$(echo "$FRONTMATTER" | grep '^scope:' | sed 's/scope: *//' || true)
BASELINE_REF=$(echo "$FRONTMATTER" | grep '^baseline_ref:' | sed 's/baseline_ref: *//' || true)
MODE=$(echo "$FRONTMATTER" | grep '^mode:' | sed 's/mode: *//' || true)
MODE="${MODE:-token-saving}"
if [[ "$MODE" != "token-saving" ]] && [[ "$MODE" != "opus" ]]; then
  MODE="token-saving"
fi
STARTED_AT=$(echo "$FRONTMATTER" | grep '^started_at:' | sed 's/started_at: *//' || true)

if [[ "$MODE" == "opus" ]]; then
  AGENT_MODEL="opus"
else
  AGENT_MODEL="sonnet"
fi

cleanup() {
  if [[ -n "${BASELINE_REF:-}" ]] && git rev-parse --is-inside-work-tree &>/dev/null; then
    git rev-parse --verify "refs/tags/$BASELINE_REF" &>/dev/null && git tag -d "$BASELINE_REF" &>/dev/null || true
  fi
  rm -f "$RALPH_STATE_FILE"
}

parse_findings_tally() {
  local text="$1"
  local critical=0 important=0 nitpick=0
  local section=""
  while IFS= read -r line; do
    case "$line" in
      "## CRITICAL"*) section="critical" ;;
      "## IMPORTANT"*) section="important" ;;
      "## NITPICK"*) section="nitpick" ;;
      [0-9]*". "*)
        case "$section" in
          critical) critical=$((critical + 1)) ;;
          important) important=$((important + 1)) ;;
          nitpick) nitpick=$((nitpick + 1)) ;;
        esac
        ;;
    esac
  done <<< "$text"
  echo "${critical},${important},${nitpick}"
}

format_duration() {
  local start_iso="$1"
  start_iso="${start_iso%\"}"
  start_iso="${start_iso#\"}"
  local start_epoch end_epoch
  start_epoch=$(date -d "$start_iso" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$start_iso" +%s 2>/dev/null || echo "")
  if [[ -z "$start_epoch" ]]; then
    echo ""
    return
  fi
  end_epoch=$(date +%s)
  local elapsed=$((end_epoch - start_epoch))
  if [[ $elapsed -lt 60 ]]; then
    echo "${elapsed}s"
  elif [[ $elapsed -lt 3600 ]]; then
    echo "$((elapsed / 60))m $((elapsed % 60))s"
  else
    echo "$((elapsed / 3600))h $((elapsed % 3600 / 60))m"
  fi
}

# Session isolation
STATE_SESSION=$(echo "$FRONTMATTER" | grep '^session_id:' | sed 's/session_id: *//' || true)
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# Validate iteration
if [[ ! "$ITERATION" =~ ^[1-9][0-9]*$ ]]; then
  echo "⚠️  Angry Ralph: State file corrupted (iteration: '$ITERATION')" >&2
  cleanup
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "⚠️  Angry Ralph: State file corrupted (max_iterations: '$MAX_ITERATIONS')" >&2
  cleanup
  exit 0
fi

if [[ "$STOP_WHEN" != "clean" ]] && [[ "$STOP_WHEN" != "spotless" ]] && [[ "$STOP_WHEN" != "manual" ]]; then
  echo "⚠️  Angry Ralph: State file corrupted (stop_when: '$STOP_WHEN')" >&2
  cleanup
  exit 0
fi

if [[ "$SCOPE" != "cumulative" ]] && [[ "$SCOPE" != "latest" ]]; then
  echo "⚠️  Angry Ralph: State file corrupted (scope: '$SCOPE')" >&2
  cleanup
  exit 0
fi

# Check max iterations
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  DURATION=$(format_duration "${STARTED_AT:-}")
  echo "" >&2
  echo "── angry-ralph complete ──" >&2
  echo "  Iterations: $ITERATION" >&2
  if [[ -n "$DURATION" ]]; then
    echo "  Duration: $DURATION" >&2
  fi
  echo "  Result: MAX ITERATIONS REACHED ($MAX_ITERATIONS)" >&2
  echo "" >&2
  cleanup
  exit 0
fi

# Read transcript
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ "$TRANSCRIPT_PATH" == "null" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  Angry Ralph: Transcript not found, will retry next hook" >&2
  exit 0
fi

set +e
LAST_OUTPUT=$(jq -rs '[.[] | select(.role == "assistant") | .message.content[]? | select(.type == "text") | .text] | last // ""' "$TRANSCRIPT_PATH" 2>/dev/null)
JQ_EXIT=$?
set -e

if [[ $JQ_EXIT -ne 0 ]]; then
  echo "⚠️  Angry Ralph: Failed to parse transcript" >&2
  cleanup
  exit 0
fi

if [[ -z "$LAST_OUTPUT" ]]; then
  echo "⚠️  Angry Ralph: Empty transcript output, will retry next hook" >&2
  exit 0
fi

# Check for review-result tags
HAS_CLEAN=$(echo "$LAST_OUTPUT" | grep -c '<review-result>CLEAN</review-result>' || true)
HAS_SPOTLESS=$(echo "$LAST_OUTPUT" | grep -c '<review-result>SPOTLESS</review-result>' || true)

if (( ITERATION % 2 == 0 )); then
  TALLY=$(parse_findings_tally "$LAST_OUTPUT")
  IFS=',' read -r T_CRIT T_IMP T_NIT <<< "$TALLY"
  if [[ $((T_CRIT + T_IMP + T_NIT)) -gt 0 ]] || [[ $HAS_CLEAN -gt 0 ]] || [[ $HAS_SPOTLESS -gt 0 ]]; then
    echo "Found: ${T_CRIT} CRITICAL, ${T_IMP} IMPORTANT, ${T_NIT} NITPICK" >&2
  fi
fi

SHOULD_STOP=false
case "$STOP_WHEN" in
  clean)
    if [[ $HAS_CLEAN -gt 0 ]] || [[ $HAS_SPOTLESS -gt 0 ]]; then
      SHOULD_STOP=true
    fi
    ;;
  spotless)
    if [[ $HAS_SPOTLESS -gt 0 ]]; then
      SHOULD_STOP=true
    fi
    ;;
  manual)
    ;;
esac

if [[ "$SHOULD_STOP" == "true" ]]; then
  DURATION=$(format_duration "${STARTED_AT:-}")
  TALLY=$(parse_findings_tally "$LAST_OUTPUT")
  IFS=',' read -r T_CRIT T_IMP T_NIT <<< "$TALLY"
  echo "" >&2
  echo "── angry-ralph complete ──" >&2
  echo "  Iterations: $ITERATION" >&2
  if [[ -n "$DURATION" ]]; then
    echo "  Duration: $DURATION" >&2
  fi
  echo "  Result: $(echo "$STOP_WHEN" | tr '[:lower:]' '[:upper:]') (${T_CRIT} critical, ${T_IMP} important, ${T_NIT} nitpick)" >&2
  echo "" >&2
  cleanup
  exit 0
fi

# Not complete — continue loop
NEXT_ITERATION=$((ITERATION + 1))

# Build diff instruction
DIFF_CMD=""
if [[ "$SCOPE" == "cumulative" ]] && [[ -n "$BASELINE_REF" ]]; then
  if [[ "$BASELINE_REF" =~ ^angry-ralph-baseline-[0-9]+-[0-9]+$ ]]; then
    DIFF_CMD="Run: git diff \"$BASELINE_REF\""
  else
    DIFF_CMD="Review the files you modified in your last pass"
  fi
else
  DIFF_CMD="Review the files you modified in your last pass"
fi

# Build review threshold / tag
REVIEW_THRESHOLD=""
RESULT_TAG=""
case "$STOP_WHEN" in
  clean)
    REVIEW_THRESHOLD="no CRITICAL or IMPORTANT issues"
    RESULT_TAG="CLEAN"
    ;;
  spotless)
    REVIEW_THRESHOLD="no issues of ANY severity"
    RESULT_TAG="SPOTLESS"
    ;;
  manual)
    REVIEW_THRESHOLD="no CRITICAL or IMPORTANT issues (but loop continues regardless)"
    RESULT_TAG="CLEAN"
    ;;
esac

REVIEW_AGENT_PROMPT="$DIFF_CMD to see all changes, then review them.

Check for: nil pointer/null reference crashes, data leaks (passwords, tokens, PII in responses or logs), missing input validation at system boundaries, error handling gaps, XSS/SQL injection/command injection/OWASP top 10, wrong HTTP status codes, race conditions and concurrency bugs, missing or inadequate test coverage, inconsistency with existing codebase patterns, resource leaks (unclosed connections, file handles, goroutines), hardcoded secrets or configuration.

Categorize each finding as CRITICAL, IMPORTANT, or NITPICK using the standard format.

If there are ${REVIEW_THRESHOLD}, output <review-result>${RESULT_TAG}</review-result>.
ONLY output that tag if the statement is genuinely true. Do NOT lie to exit the loop."

# Determine if this was a work pass (odd) or review pass (even)
if (( ITERATION % 2 == 1 )); then
  # Last was work pass (odd) → next is review pass
  # Orchestrator dispatches angry-reviewer agent
  NEXT_PROMPT="Dispatch the angry-ralph:angry-reviewer agent to review the code changes.

Use the Agent tool with these parameters:
- description: \"Angry Ralph review pass\"
- subagent_type: \"angry-ralph:angry-reviewer\"
- model: \"${AGENT_MODEL}\"
- prompt: (the review instructions below)

Review instructions to pass as the agent prompt:
---
${REVIEW_AGENT_PROMPT}
---

After the agent returns its report, relay the findings to the conversation. Then, if the agent found ${REVIEW_THRESHOLD}, output <review-result>${RESULT_TAG}</review-result>. ONLY output that tag if the agent's review genuinely supports it."
else
  # Last was review pass (even) → next is work/fix pass
  ORIGINAL_PROMPT=$(tr -d '\r' "$RALPH_STATE_FILE" | awk '/^---$/{i++; next} i>=2')

  WORK_AGENT_PROMPT="Fix ALL CRITICAL and IMPORTANT issues from the review above. Then continue working on the original task:

${ORIGINAL_PROMPT}"

  NEXT_PROMPT="Dispatch a general-purpose agent to fix the issues found in the review and continue working on the task.

Use the Agent tool with these parameters:
- description: \"Angry Ralph work pass\"
- subagent_type: \"general-purpose\"
- model: \"${AGENT_MODEL}\"
- prompt: (the work instructions below)

Work instructions to pass as the agent prompt:
---
${WORK_AGENT_PROMPT}
---

After the agent completes, summarize what was fixed and any remaining work."
fi

# Update iteration
TEMP_FILE=$(mktemp "${RALPH_STATE_FILE}.XXXXXX")
trap 'rm -f "$TEMP_FILE"' EXIT INT TERM
sed "s/^iteration: .*/iteration: $NEXT_ITERATION/" "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE" || exit 1
trap - EXIT INT TERM

SYSTEM_MSG="🔥 Angry Ralph iteration $NEXT_ITERATION ($(if (( NEXT_ITERATION % 2 == 0 )); then echo 'REVIEW pass'; else echo 'WORK pass'; fi)) | stop-when: $STOP_WHEN | mode: $MODE (agent model: $AGENT_MODEL)"

# Progress banner
FILE_COUNT=""
if git rev-parse --is-inside-work-tree &>/dev/null; then
  if [[ "$SCOPE" == "cumulative" ]] && [[ -n "$BASELINE_REF" ]]; then
    FILE_COUNT=$(git diff --stat "$BASELINE_REF" 2>/dev/null | tail -1 | grep -oE '[0-9]+ files?' | grep -oE '[0-9]+' || echo "")
  else
    FILE_COUNT=$(git diff --stat HEAD~1 2>/dev/null | tail -1 | grep -oE '[0-9]+ files?' | grep -oE '[0-9]+' || echo "")
  fi
fi

PASS_TYPE=$(if (( NEXT_ITERATION % 2 == 0 )); then echo "review"; else echo "work"; fi)
BANNER="── angry-ralph ── iteration ${NEXT_ITERATION} (${PASS_TYPE})"
if [[ -n "$FILE_COUNT" ]]; then
  BANNER="${BANNER} ── ${FILE_COUNT} files changed"
fi
BANNER="${BANNER} ── stop-when: ${STOP_WHEN} ──"

echo "$BANNER" >&2

jq -n \
  --arg prompt "$NEXT_PROMPT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
