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

# ── Read & parse stdin in a single jq call ────────────────────────────────────
INPUT="$(cat)"

# Extract all needed fields at once (single jq fork).
# Uses \x1f (unit separator) as delimiter — NOT @tsv, because bash read
# treats tab as IFS whitespace and collapses consecutive/leading tabs.
IFS=$'\x1f' read -r SESSION_ID TOOL_NAME _CMD _FP _PAT _OLD < <(
  echo "$INPUT" | jq -rj '[
    (.session_id // ""),
    (.tool_name // ""),
    (.tool_input.command // ""),
    (.tool_input.file_path // ""),
    (.tool_input.pattern // ""),
    (if .tool_name == "Edit" then (.tool_input.old_string // "")[0:40] else "" end)
  ] | join("\u001f")' 2>/dev/null
  echo  # ensure trailing newline for read
) || true

# Fallback: if no session_id, use parent PID for isolation
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID="pid-$$"
fi

# Sanitize session_id — strip slashes and special chars to prevent path traversal
SESSION_ID="${SESSION_ID//[\/\\:]/_}"

if [[ -z "$TOOL_NAME" ]]; then
  exit 0  # malformed input — allow silently
fi

# ── Build human-readable fingerprint for loop detection ──────────────────────
FINGERPRINT="$TOOL_NAME"
case "$TOOL_NAME" in
  Bash)
    [[ -n "$_CMD" ]] && FINGERPRINT="Bash:${_CMD:0:80}"
    ;;
  Read|Write)
    [[ -n "$_FP" ]] && FINGERPRINT="${TOOL_NAME}:${_FP}"
    ;;
  Edit)
    if [[ -n "$_FP" && -n "$_OLD" ]]; then
      FINGERPRINT="Edit:${_FP}#${_OLD:0:40}"
    elif [[ -n "$_FP" ]]; then
      FINGERPRINT="Edit:${_FP}"
    fi
    ;;
  Grep)
    [[ -n "$_PAT" ]] && FINGERPRINT="Grep:${_PAT:0:40}"
    ;;
  Glob)
    [[ -n "$_PAT" ]] && FINGERPRINT="Glob:${_PAT:0:40}"
    ;;
esac

# ── State file ────────────────────────────────────────────────────────────────
STATE_FILE="/tmp/claude-budget-guard-${SESSION_ID}.json"

_new_state() {
  jq -n --argjson limit "$BUDGET_LIMIT" --argjson warn "$BUDGET_WARN" \
    '{count: 0, limit: $limit, warn_at: $warn, history: [], started: (now | todate)}'
}

# ── CHECK 0: Reset bypass ───────────────────────────────────────────────────
# The /token-budget-guard:reset skill runs a specific Bash command.
# Allow it through even when blocked — otherwise reset is a dead letter.
if [[ "$TOOL_NAME" == "Bash" && "$_CMD" =~ ^for\ f\ in\ /tmp/claude-budget-guard-.*\.json ]]; then
  if [[ -f "$STATE_FILE" ]]; then
    STATE="$(cat "$STATE_FILE")"
    if ! echo "$STATE" | jq -e 'type == "object" and (.count | type == "number")' &>/dev/null; then
      STATE="$(_new_state)"
    fi
  else
    STATE="$(_new_state)"
  fi
  STATE="$(echo "$STATE" | jq '.count += 1')"
  echo "$STATE" > "$STATE_FILE"
  exit 0
fi

# ── Load or initialize state ─────────────────────────────────────────────────
if [[ -f "$STATE_FILE" ]]; then
  STATE="$(cat "$STATE_FILE")"
  # Validate: must be a JSON object with numeric count and array history
  if ! echo "$STATE" | jq -e 'type == "object" and (.count | type == "number") and (.history | type == "array")' &>/dev/null; then
    STATE="$(_new_state)"
  fi
else
  STATE="$(_new_state)"
fi

# ── Update state (single jq call) ────────────────────────────────────────────
# Increment count, sync limit/warn from env, append fingerprint, trim history
COUNT="$(echo "$STATE" | jq '.count')"
COUNT=$((COUNT + 1))
LIMIT="$BUDGET_LIMIT"
WARN_AT="$BUDGET_WARN"

STATE="$(echo "$STATE" | jq \
  --argjson count "$COUNT" \
  --argjson limit "$LIMIT" \
  --argjson warn "$WARN_AT" \
  --arg fp "$FINGERPRINT" \
  --argjson window "$LOOP_WINDOW" \
  '.count = $count | .limit = $limit | .warn_at = $warn | .history = (.history + [$fp] | .[-$window:])'
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

# ── CHECK 2: Loop + repeat detection (single jq call) ────────────────────────
# Returns unit-separator-delimited values: loop_fp and repeat_tool
IFS=$'\x1f' read -r LOOP_FP REPEAT_TOOL < <(
  echo "$STATE" | jq -rj \
    --argjson lt "$LOOP_THRESHOLD" \
    --argjson rt "$TOOL_REPEAT_THRESHOLD" \
    '[ ( [.history[] | {fp: .}] | group_by(.fp) | map({fp: .[0].fp, n: length}) | map(select(.n >= $lt)) | .[0].fp // "" ),
       ( [.history[] | split(":")[0]] | group_by(.) | map({tool: .[0], n: length}) | map(select(.n >= $rt)) | .[0].tool // "" )
    ] | join("\u001f")'
  echo
) || true

# CHECK 2a: Exact loop detection
if [[ -n "$LOOP_FP" ]]; then
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

# CHECK 2b: Tool repeat warning (non-blocking)
WARN_MSG=""
if [[ -n "$REPEAT_TOOL" ]]; then
  REPEAT_COUNT="$(echo "$STATE" | jq --arg tool "$REPEAT_TOOL" '[.history[] | select(split(":")[0] == $tool)] | length')"
  WARN_MSG="TOOL REPEAT: ${REPEAT_TOOL} used ${REPEAT_COUNT}/${LOOP_WINDOW} times (varied inputs, not blocked)."
fi

# ── CHECK 3: Warning threshold ───────────────────────────────────────────────
if (( COUNT >= WARN_AT )); then
  REMAINING=$((LIMIT - COUNT))
  PERCENT=$(( COUNT * 100 / LIMIT ))
  BUDGET_MSG="TOKEN BUDGET WARNING: ${COUNT}/${LIMIT} tool calls used (${PERCENT}%). ${REMAINING} calls remaining."
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
