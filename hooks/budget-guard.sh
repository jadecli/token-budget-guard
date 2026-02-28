#!/usr/bin/env bash
# token-budget-guard — deterministic tool call budgets, loop detection, circuit breaking
# PreToolUse hook for Claude Code. Zero dependencies beyond bash + jq.
set -euo pipefail

# ── Configuration (env vars with defaults) ────────────────────────────────────
BUDGET_LIMIT="${BUDGET_LIMIT:-200}"
BUDGET_WARN="${BUDGET_WARN:-$(( BUDGET_LIMIT * 70 / 100 ))}"
LOOP_WINDOW="${LOOP_WINDOW:-10}"
LOOP_THRESHOLD="${LOOP_THRESHOLD:-8}"

# ── Dependency check ──────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "token-budget-guard: jq is required but not found. Install with: brew install jq" >&2
  exit 0  # allow — don't block the user over a missing dependency
fi

# ── Read stdin ────────────────────────────────────────────────────────────────
INPUT="$(cat)"

SESSION_ID="$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)" || true
TOOL_NAME="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" || true

# Fallback: if no session_id, use parent PID for isolation
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="pid-$$"
fi

if [[ -z "$TOOL_NAME" ]]; then
  exit 0  # malformed input — allow silently
fi

# ── State file ────────────────────────────────────────────────────────────────
STATE_FILE="/tmp/claude-budget-guard-${SESSION_ID}.json"

if [[ -f "$STATE_FILE" ]]; then
  STATE="$(cat "$STATE_FILE")"
else
  STATE="$(jq -n \
    --argjson limit "$BUDGET_LIMIT" \
    --argjson warn "$BUDGET_WARN" \
    '{count: 0, limit: $limit, warn_at: $warn, history: [], started: (now | todate)}'
  )"
fi

# ── Update state ──────────────────────────────────────────────────────────────
COUNT="$(echo "$STATE" | jq '.count')"
LIMIT="$(echo "$STATE" | jq '.limit')"
WARN_AT="$(echo "$STATE" | jq '.warn_at')"
COUNT=$((COUNT + 1))

# Append tool name to history, keep only last LOOP_WINDOW entries
STATE="$(echo "$STATE" | jq \
  --arg tool "$TOOL_NAME" \
  --argjson window "$LOOP_WINDOW" \
  --argjson count "$COUNT" \
  '.count = $count | .history = (.history + [$tool] | .[-$window:])'
)"

# ── CHECK 1: Hard limit ──────────────────────────────────────────────────────
if (( COUNT > LIMIT )); then
  echo "$STATE" > "$STATE_FILE"
  cat >&2 <<EOF
BUDGET EXCEEDED: ${COUNT}/${LIMIT} tool calls used. Session budget exhausted.
Run /token-budget-guard:reset to continue, or start a new session.
EOF
  exit 2
fi

# ── CHECK 2: Loop detection ──────────────────────────────────────────────────
# Count occurrences of each tool in the sliding window
LOOP_TOOL="$(echo "$STATE" | jq -r \
  --argjson threshold "$LOOP_THRESHOLD" \
  '[.history[] | {tool: .}] | group_by(.tool) | map({tool: .[0].tool, n: length}) | map(select(.n >= $threshold)) | .[0].tool // empty'
)"

if [[ -n "$LOOP_TOOL" ]]; then
  LOOP_COUNT="$(echo "$STATE" | jq \
    --arg tool "$LOOP_TOOL" \
    '[.history[] | select(. == $tool)] | length'
  )"
  echo "$STATE" > "$STATE_FILE"
  cat >&2 <<EOF
LOOP DETECTED: ${LOOP_TOOL} called ${LOOP_COUNT} times in last ${LOOP_WINDOW} calls.
This looks like an infinite loop. Blocked to prevent token waste.
Run /token-budget-guard:reset to clear, or try a different approach.
EOF
  exit 2
fi

# ── CHECK 3: Warning threshold ───────────────────────────────────────────────
if (( COUNT >= WARN_AT )); then
  REMAINING=$((LIMIT - COUNT))
  PERCENT=$(( COUNT * 100 / LIMIT ))
  echo "$STATE" > "$STATE_FILE"
  jq -n \
    --arg msg "TOKEN BUDGET WARNING: ${COUNT}/${LIMIT} tool calls used (${PERCENT}%). ${REMAINING} calls remaining." \
    '{hookSpecificOutput: {additionalContext: $msg}}'
  exit 0
fi

# ── All clear — allow silently ────────────────────────────────────────────────
echo "$STATE" > "$STATE_FILE"
exit 0
