#!/usr/bin/env bash
# token-budget-guard — deterministic tool call budgets, loop detection, circuit breaking
# PreToolUse hook for Claude Code. Zero dependencies beyond bash + jq.
set -euo pipefail

# ── Configuration (env vars with defaults) ────────────────────────────────────
BUDGET_LIMIT="${BUDGET_LIMIT:-500}"
BUDGET_WARN="${BUDGET_WARN:-$(( BUDGET_LIMIT * 70 / 100 ))}"
LOOP_WINDOW="${LOOP_WINDOW:-10}"
LOOP_THRESHOLD="${LOOP_THRESHOLD:-5}"               # identical fingerprints in window
TOOL_REPEAT_THRESHOLD="${TOOL_REPEAT_THRESHOLD:-9}"  # same tool name in window (warning only)

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

# ── Build human-readable fingerprint for loop detection ──────────────────────
# "Bash:git status" instead of opaque "Bash:a1b2c3d4" —
# shows WHAT is looping in /token-budget-guard:status output.
# Falls back to bare tool name when tool_input is absent.
FINGERPRINT="$TOOL_NAME"
case "$TOOL_NAME" in
  Bash)
    _CMD="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || true
    [[ -n "$_CMD" ]] && FINGERPRINT="Bash:${_CMD:0:80}"
    ;;
  Read|Write|Edit)
    _FP="$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)" || true
    [[ -n "$_FP" ]] && FINGERPRINT="${TOOL_NAME}:${_FP}"
    ;;
  Grep)
    _PAT="$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null)" || true
    [[ -n "$_PAT" ]] && FINGERPRINT="Grep:${_PAT:0:40}"
    ;;
  Glob)
    _PAT="$(echo "$INPUT" | jq -r '.tool_input.pattern // empty' 2>/dev/null)" || true
    [[ -n "$_PAT" ]] && FINGERPRINT="Glob:${_PAT:0:40}"
    ;;
esac

# ── CHECK 0: Reset bypass ───────────────────────────────────────────────────
# The /token-budget-guard:reset skill runs a Bash command that modifies state
# files. Allow it through even when blocked — otherwise reset is a dead letter.
if [[ "$TOOL_NAME" == "Bash" ]]; then
  _RESET_CMD="$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)" || true
  if [[ "$_RESET_CMD" == *"claude-budget-guard"* && "$_RESET_CMD" == *".json"* ]]; then
    # Allow the reset command, but still count it
    STATE_FILE="/tmp/claude-budget-guard-${SESSION_ID}.json"
    if [[ -f "$STATE_FILE" ]]; then
      STATE="$(cat "$STATE_FILE")"
    else
      STATE="$(jq -n --argjson limit "$BUDGET_LIMIT" --argjson warn "$BUDGET_WARN" \
        '{count: 0, limit: $limit, warn_at: $warn, history: [], started: (now | todate)}')"
    fi
    COUNT="$(echo "$STATE" | jq '.count')"
    COUNT=$((COUNT + 1))
    STATE="$(echo "$STATE" | jq --argjson count "$COUNT" '.count = $count')"
    echo "$STATE" > "$STATE_FILE"
    exit 0
  fi
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
COUNT=$((COUNT + 1))

# Sync limit/warn from env vars into state — env always wins over stale state.
# This lets users adjust BUDGET_LIMIT mid-session without a full reset.
LIMIT="$BUDGET_LIMIT"
WARN_AT="$BUDGET_WARN"
STATE="$(echo "$STATE" | jq --argjson l "$LIMIT" --argjson w "$WARN_AT" '.limit = $l | .warn_at = $w')"

# Append fingerprint to history, keep only last LOOP_WINDOW entries
STATE="$(echo "$STATE" | jq \
  --arg fp "$FINGERPRINT" \
  --argjson window "$LOOP_WINDOW" \
  --argjson count "$COUNT" \
  '.count = $count | .history = (.history + [$fp] | .[-$window:])'
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

# ── CHECK 2a: Exact loop detection (same fingerprint repeated) ───────────────
LOOP_FP="$(echo "$STATE" | jq -r \
  --argjson threshold "$LOOP_THRESHOLD" \
  '[.history[] | {fp: .}] | group_by(.fp) | map({fp: .[0].fp, n: length}) | map(select(.n >= $threshold)) | .[0].fp // empty'
)"

if [[ -n "$LOOP_FP" ]]; then
  LOOP_TOOL="${LOOP_FP%%:*}"
  LOOP_COUNT="$(echo "$STATE" | jq --arg fp "$LOOP_FP" '[.history[] | select(. == $fp)] | length')"
  DISPLAY="${LOOP_FP:0:60}"
  echo "$STATE" > "$STATE_FILE"
  cat >&2 <<EOF
LOOP DETECTED: ${DISPLAY} called ${LOOP_COUNT} times with identical input in last ${LOOP_WINDOW} calls.
This looks like an infinite loop. Blocked to prevent token waste.
Run /token-budget-guard:reset to clear, or try a different approach.
EOF
  exit 2
fi

# ── CHECK 2b: Tool name repetition warning (different inputs, same tool) ────
# Non-blocking — warns when one tool dominates the window even with varied inputs.
# Combine with budget warning if both apply.
WARN_MSG=""

REPEAT_TOOL="$(echo "$STATE" | jq -r \
  --argjson threshold "$TOOL_REPEAT_THRESHOLD" \
  '[.history[] | split(":")[0]] | group_by(.) | map({tool: .[0], n: length}) | map(select(.n >= $threshold)) | .[0].tool // empty'
)"

if [[ -n "$REPEAT_TOOL" ]]; then
  REPEAT_COUNT="$(echo "$STATE" | jq --arg tool "$REPEAT_TOOL" '[.history[] | select(split(":")[0] == $tool)] | length')"
  WARN_MSG="TOOL REPEAT: ${REPEAT_TOOL} used ${REPEAT_COUNT}/${LOOP_WINDOW} times (varied inputs, not blocked)."
fi

# ── CHECK 3: Warning threshold ───────────────────────────────────────────────
if (( COUNT >= WARN_AT )); then
  REMAINING=$((LIMIT - COUNT))
  PERCENT=$(( COUNT * 100 / LIMIT ))
  BUDGET_MSG="TOKEN BUDGET WARNING: ${COUNT}/${LIMIT} tool calls used (${PERCENT}%). ${REMAINING} calls remaining."
  # Combine budget + repeat warnings if both apply
  if [[ -n "$WARN_MSG" ]]; then
    COMBINED="${BUDGET_MSG} ${WARN_MSG}"
  else
    COMBINED="$BUDGET_MSG"
  fi
  echo "$STATE" > "$STATE_FILE"
  jq -n --arg msg "$COMBINED" '{hookSpecificOutput: {additionalContext: $msg}}'
  exit 0
fi

# ── Emit tool repeat warning alone (below budget threshold) ──────────────────
if [[ -n "$WARN_MSG" ]]; then
  echo "$STATE" > "$STATE_FILE"
  jq -n --arg msg "$WARN_MSG" '{hookSpecificOutput: {additionalContext: $msg}}'
  exit 0
fi

# ── All clear — allow silently ────────────────────────────────────────────────
echo "$STATE" > "$STATE_FILE"
exit 0
