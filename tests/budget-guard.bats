#!/usr/bin/env bats
#
# token-budget-guard test suite
#
# These tests ARE the spec. The script is the implementation.
# If you refactor budget-guard.sh, these tests tell you if you broke the contract.
#
# Run: bats tests/budget-guard.bats
#

bats_require_minimum_version 1.5.0

GUARD="$BATS_TEST_DIRNAME/../hooks/budget-guard.sh"
SID_PREFIX="bats-$$-${RANDOM}"

# ── Helpers ────────────────────────────────────────────────────────────────────

state_file() { echo "/tmp/claude-budget-guard-${1}.json"; }

read_state() { jq -r "$2" "$(state_file "$1")"; }

seed_state() { echo "$2" > "$(state_file "$1")"; }

# Invoke the guard with optional env overrides.
# Usage: guard SESSION_ID TOOL_NAME [ENV_VAR=val ...]
guard() {
  local sid="$1" tool="$2"
  shift 2
  local input
  input="$(jq -n --arg sid "$sid" --arg tool "$tool" '{session_id: $sid, tool_name: $tool}')"
  if [[ $# -gt 0 ]]; then
    run --separate-stderr env "$@" bash "$GUARD" <<< "$input"
  else
    run --separate-stderr bash "$GUARD" <<< "$input"
  fi
}

setup() {
  TEST_SID="${SID_PREFIX}-${BATS_TEST_NUMBER}"
}

teardown() {
  rm -f /tmp/claude-budget-guard-${SID_PREFIX}-*.json
}

# ══════════════════════════════════════════════════════════════════════════════
# A. Dependency Check
# ══════════════════════════════════════════════════════════════════════════════

@test "A1: missing jq allows the call and warns on stderr" {
  # Use an empty temp dir as PATH so jq is guaranteed absent
  local empty_dir
  empty_dir="$(mktemp -d)"
  # Copy just bash so the script can run
  cp "$(command -v bash)" "$empty_dir/bash"
  run --separate-stderr env PATH="$empty_dir" "$empty_dir/bash" "$GUARD" \
    <<< '{"session_id":"x","tool_name":"Bash"}'
  rm -rf "$empty_dir"
  [[ "$status" -eq 0 ]]
  [[ "$stderr" == *"jq is required"* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# B. Input Parsing — malformed input must never block the user
# ══════════════════════════════════════════════════════════════════════════════

@test "B1: empty stdin exits 0" {
  run --separate-stderr bash "$GUARD" <<< ""
  [[ "$status" -eq 0 ]]
}

@test "B2: malformed JSON exits 0" {
  run --separate-stderr bash "$GUARD" <<< "not json at all"
  [[ "$status" -eq 0 ]]
}

@test "B3: missing tool_name exits 0 and creates no state file" {
  run --separate-stderr bash "$GUARD" <<< '{"session_id":"test-no-tool"}'
  [[ "$status" -eq 0 ]]
  [[ ! -f "/tmp/claude-budget-guard-test-no-tool.json" ]]
}

@test "B4: missing session_id falls back to pid-based state" {
  run --separate-stderr bash "$GUARD" <<< '{"tool_name":"Bash"}'
  [[ "$status" -eq 0 ]]
  # State file created with pid- prefix
  ls /tmp/claude-budget-guard-pid-*.json &>/dev/null
  rm -f /tmp/claude-budget-guard-pid-*.json
}

@test "B5: valid input creates state file with count 1" {
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
  [[ -f "$(state_file "$TEST_SID")" ]]
  [[ "$(read_state "$TEST_SID" '.count')" -eq 1 ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# C. State Initialization — defaults and env var overrides
# ══════════════════════════════════════════════════════════════════════════════

@test "C1: first call initializes state with correct defaults" {
  guard "$TEST_SID" "Bash"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 1 ]]
  [[ "$(read_state "$TEST_SID" '.limit')" -eq 200 ]]
  [[ "$(read_state "$TEST_SID" '.warn_at')" -eq 140 ]]
  [[ "$(read_state "$TEST_SID" '.history | length')" -eq 1 ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
  [[ -n "$(read_state "$TEST_SID" '.started')" ]]
}

@test "C2: BUDGET_LIMIT overrides default limit" {
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=50
  [[ "$(read_state "$TEST_SID" '.limit')" -eq 50 ]]
}

@test "C3: BUDGET_WARN defaults to 70% of BUDGET_LIMIT" {
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=100
  [[ "$(read_state "$TEST_SID" '.warn_at')" -eq 70 ]]
}

@test "C4: BUDGET_WARN can be overridden independently" {
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=100 BUDGET_WARN=90
  [[ "$(read_state "$TEST_SID" '.warn_at')" -eq 90 ]]
}

@test "C5: state persists between calls — count increments" {
  guard "$TEST_SID" "Bash"
  guard "$TEST_SID" "Edit"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 2 ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# D. Count & History — increments, recording, trimming
# ══════════════════════════════════════════════════════════════════════════════

@test "D1: count increments by 1 on each call" {
  guard "$TEST_SID" "Bash"
  guard "$TEST_SID" "Edit"
  guard "$TEST_SID" "Read"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 3 ]]
}

@test "D2: history records each tool name in order" {
  guard "$TEST_SID" "Bash"
  guard "$TEST_SID" "Edit"
  guard "$TEST_SID" "Read"
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
  [[ "$(read_state "$TEST_SID" '.history[1]')" == "Edit" ]]
  [[ "$(read_state "$TEST_SID" '.history[2]')" == "Read" ]]
}

@test "D3: history trimmed to LOOP_WINDOW size" {
  seed_state "$TEST_SID" '{"count":4,"limit":200,"warn_at":140,"history":["A","B","C","D"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "E" LOOP_WINDOW=3
  # After appending E and trimming to window of 3: [C, D, E]
  [[ "$(read_state "$TEST_SID" '.history | length')" -eq 3 ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "C" ]]
  [[ "$(read_state "$TEST_SID" '.history[2]')" == "E" ]]
}

@test "D4: count keeps growing even after history is trimmed" {
  seed_state "$TEST_SID" '{"count":4,"limit":200,"warn_at":140,"history":["A","B","C","D"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "E" LOOP_WINDOW=3
  [[ "$(read_state "$TEST_SID" '.count')" -eq 5 ]]
  [[ "$(read_state "$TEST_SID" '.history | length')" -eq 3 ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# E. Hard Limit — the budget ceiling
# ══════════════════════════════════════════════════════════════════════════════

@test "E1: call at exactly the limit is allowed" {
  # count=199 → next call makes 200. 200 > 200 is false → allowed.
  seed_state "$TEST_SID" '{"count":199,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
  [[ "$(read_state "$TEST_SID" '.count')" -eq 200 ]]
}

@test "E2: call exceeding the limit exits 2" {
  # count=200 → next call makes 201. 201 > 200 → blocked.
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"BUDGET EXCEEDED"* ]]
}

@test "E3: exceeded message includes count and limit" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$stderr" == *"201/200"* ]]
}

@test "E4: state file is saved even when blocked" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 201 ]]
}

@test "E5: custom BUDGET_LIMIT=5 blocks at call 6" {
  seed_state "$TEST_SID" '{"count":5,"limit":5,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"BUDGET EXCEEDED"* ]]
}

@test "E6: hard limit fires before loop detection when both conditions met" {
  # count=200 (will exceed) AND history is all "Bash" (would loop).
  # Hard limit check comes first → message says BUDGET EXCEEDED, not LOOP DETECTED.
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"BUDGET EXCEEDED"* ]]
  [[ "$stderr" != *"LOOP DETECTED"* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# F. Loop Detection — sliding window analysis
# ══════════════════════════════════════════════════════════════════════════════

@test "F1: below threshold is allowed (7 of same tool in window of 10)" {
  # 6 Bash + 3 Edit in history, next call is Bash → 7 Bash in window. Below 8 threshold.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Edit","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
}

@test "F2: at threshold triggers loop block (8 of same tool in window of 10)" {
  # 7 Bash + 2 Edit in history, next call is Bash → window trims to 10, has 8 Bash.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "F3: loop message includes tool name and count" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Read","Read","Read","Read","Read","Read","Read","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Read"
  [[ "$stderr" == *"Read"* ]]
  [[ "$stderr" == *"8 times"* ]]
}

@test "F4: mixed tools below threshold are allowed" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Edit","Read","Bash","Edit","Read","Bash","Edit","Read"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
}

@test "F5: LOOP_THRESHOLD override is respected" {
  # threshold=3, window has 2 Bash + 1 Edit, next is Bash → 3 Bash in window → block.
  seed_state "$TEST_SID" '{"count":3,"limit":200,"warn_at":999,"history":["Bash","Bash","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=3 LOOP_WINDOW=4
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "F6: LOOP_WINDOW override is respected" {
  # Window=5 with threshold=4. History has 5 entries: 3 Bash + 2 Edit.
  # Next call is Bash → window trims to last 5: [Bash, Bash, Edit, Edit, Bash] → 3 Bash. Below 4.
  # But if we seed with 4 Bash in last 5 positions...
  seed_state "$TEST_SID" '{"count":5,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Edit","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=4 LOOP_WINDOW=5
  # Window after: [Bash, Bash, Edit, Bash, Bash] → 4 Bash ≥ 4 → block
  [[ "$status" -eq 2 ]]
}

@test "F7: loop clears when window slides past repeated calls" {
  # History: 7 Bash + 3 Edit. Next call is Edit.
  # Window after: last 10 of [Bash*7, Edit*3, Edit] = [Bash*7, Edit*3, Edit][-10:] = [Bash*6, Edit*3, Edit] → 6 Bash < 8
  seed_state "$TEST_SID" '{"count":10,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Edit","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Edit"
  [[ "$status" -eq 0 ]]
}

@test "F8: state file is saved even when loop blocks" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ -f "$(state_file "$TEST_SID")" ]]
  [[ "$(read_state "$TEST_SID" '.count')" -eq 10 ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# G. Warning Threshold — non-blocking context injection
# ══════════════════════════════════════════════════════════════════════════════

@test "G1: below warning threshold produces no stdout" {
  seed_state "$TEST_SID" '{"count":138,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  # count=139 < warn_at=140 → no output
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "G2: at warning threshold emits JSON on stdout" {
  seed_state "$TEST_SID" '{"count":139,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

@test "G3: warning JSON has correct structure" {
  seed_state "$TEST_SID" '{"count":139,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  local ctx
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"TOKEN BUDGET WARNING"* ]]
}

@test "G4: warning message includes count, limit, percent, remaining" {
  seed_state "$TEST_SID" '{"count":139,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  local ctx
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"140/200"* ]]
  [[ "$ctx" == *"70%"* ]]
  [[ "$ctx" == *"60 calls remaining"* ]]
}

@test "G5: warning fires on every call after threshold" {
  seed_state "$TEST_SID" '{"count":139,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ -n "$output" ]]
  guard "$TEST_SID" "Edit"
  [[ -n "$output" ]]
  guard "$TEST_SID" "Read"
  [[ -n "$output" ]]
}

@test "G6: hard limit takes precedence over warning when both apply" {
  # count=200, warn_at=140. Next call: count=201 > limit=200 → hard limit fires.
  # Warning check is never reached.
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"BUDGET EXCEEDED"* ]]
  [[ -z "$output" ]]
}

@test "G7: state file reflects count after warning" {
  seed_state "$TEST_SID" '{"count":139,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 140 ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# H. Configuration — env var defaults and derivation
# ══════════════════════════════════════════════════════════════════════════════

@test "H1: default BUDGET_LIMIT is 200" {
  guard "$TEST_SID" "Bash"
  [[ "$(read_state "$TEST_SID" '.limit')" -eq 200 ]]
}

@test "H2: default BUDGET_WARN is 70% of BUDGET_LIMIT" {
  guard "$TEST_SID" "Bash"
  [[ "$(read_state "$TEST_SID" '.warn_at')" -eq 140 ]]
}

@test "H3: BUDGET_WARN derived from custom BUDGET_LIMIT" {
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=100
  [[ "$(read_state "$TEST_SID" '.warn_at')" -eq 70 ]]
}

@test "H4: BUDGET_WARN=1 warns on first call" {
  guard "$TEST_SID" "Bash" BUDGET_WARN=1
  [[ "$status" -eq 0 ]]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

# ══════════════════════════════════════════════════════════════════════════════
# I. State Isolation — sessions don't interfere
# ══════════════════════════════════════════════════════════════════════════════

@test "I1: different session_ids get independent state files" {
  local sid_a="${TEST_SID}-a"
  local sid_b="${TEST_SID}-b"
  guard "$sid_a" "Bash"
  guard "$sid_a" "Bash"
  guard "$sid_b" "Edit"
  [[ "$(read_state "$sid_a" '.count')" -eq 2 ]]
  [[ "$(read_state "$sid_b" '.count')" -eq 1 ]]
  rm -f "$(state_file "$sid_a")" "$(state_file "$sid_b")"
}

@test "I2: pre-seeded count is respected and incremented" {
  seed_state "$TEST_SID" '{"count":50,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 51 ]]
}

@test "I3: existing state file limit used — env var ignored mid-session" {
  # State file says limit=100. Even with BUDGET_LIMIT=200 in env,
  # the state file's limit is canonical.
  seed_state "$TEST_SID" '{"count":99,"limit":100,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=200
  # count=100, limit from state=100. 100 > 100 is false → allowed.
  [[ "$status" -eq 0 ]]
  # Next call: count=101 > 100 → blocked.
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=200
  [[ "$status" -eq 2 ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# J. Edge Cases — boundary conditions, extremes
# ══════════════════════════════════════════════════════════════════════════════

@test "J1: tool_name with special characters is handled" {
  guard "$TEST_SID" "Bash (subprocess)"
  [[ "$status" -eq 0 ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash (subprocess)" ]]
}

@test "J2: BUDGET_LIMIT=1 blocks on second call" {
  seed_state "$TEST_SID" '{"count":0,"limit":1,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
  guard "$TEST_SID" "Edit"
  [[ "$status" -eq 2 ]]
}

@test "J3: LOOP_THRESHOLD=1 blocks on first call — any single tool triggers" {
  # With threshold=1, ANY tool appearing ≥ 1 time in the window is a "loop".
  # This is an extreme config. The first call itself triggers because after
  # appending, history=["Bash"] and 1 >= 1 is true.
  seed_state "$TEST_SID" '{"count":0,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=1 LOOP_WINDOW=2
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "J4: block message includes reset instructions" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$stderr" == *"/token-budget-guard:reset"* ]]
}

@test "J5: loop block message includes reset instructions" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$stderr" == *"/token-budget-guard:reset"* ]]
}
