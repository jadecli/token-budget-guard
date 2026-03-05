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
# No tool_input -> fingerprint = bare tool name.
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

# Invoke the guard with tool_input for fingerprint tests.
# Usage: guard_with_input SESSION_ID TOOL_NAME TOOL_INPUT_JSON [ENV_VAR=val ...]
# tool_input is passed as a parsed JSON object.
guard_with_input() {
  local sid="$1" tool="$2" tool_input="$3"
  shift 3
  local input
  input="$(jq -n --arg sid "$sid" --arg tool "$tool" --argjson ti "$tool_input" \
    '{session_id: $sid, tool_name: $tool, tool_input: $ti}')"
  if [[ $# -gt 0 ]]; then
    run --separate-stderr env "$@" bash "$GUARD" <<< "$input"
  else
    run --separate-stderr bash "$GUARD" <<< "$input"
  fi
}

setup() {
  TEST_SID="${SID_PREFIX}-${BATS_TEST_NUMBER}"
  # Isolate from user's env -- tests must use script defaults
  unset BUDGET_LIMIT BUDGET_WARN LOOP_WINDOW LOOP_THRESHOLD TOOL_REPEAT_THRESHOLD 2>/dev/null || true
}

teardown() {
  rm -f /tmp/claude-budget-guard-${SID_PREFIX}-*.json
}

# A. Dependency Check

@test "A1: missing jq allows the call and warns on stderr" {
  local empty_dir
  empty_dir="$(mktemp -d)"
  cp "$(command -v bash)" "$empty_dir/bash"
  run --separate-stderr env PATH="$empty_dir" "$empty_dir/bash" "$GUARD" \
    <<< '{"session_id":"x","tool_name":"Bash"}'
  rm -rf "$empty_dir"
  [[ "$status" -eq 0 ]]
  [[ "$stderr" == *"jq is required"* ]]
}

# B. Input Parsing

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
  ls /tmp/claude-budget-guard-pid-*.json &>/dev/null
  rm -f /tmp/claude-budget-guard-pid-*.json
}

@test "B5: valid input creates state file with count 1" {
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
  [[ -f "$(state_file "$TEST_SID")" ]]
  [[ "$(read_state "$TEST_SID" '.count')" -eq 1 ]]
}

# C. State Initialization

@test "C1: first call initializes state with correct defaults" {
  guard "$TEST_SID" "Bash"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 1 ]]
  [[ "$(read_state "$TEST_SID" '.limit')" -eq 200 ]]
  [[ "$(read_state "$TEST_SID" '.warn_at')" -eq 140 ]]
  [[ "$(read_state "$TEST_SID" '.history | length')" -eq 1 ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
  [[ -n "$(read_state "$TEST_SID" '.started')" ]]
}

@test "C1b: first call with tool_input stores readable fingerprint" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"git status"}'
  [[ "$(read_state "$TEST_SID" '.count')" -eq 1 ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash:git status" ]]
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

@test "C5: state persists between calls" {
  guard "$TEST_SID" "Bash"
  guard "$TEST_SID" "Edit"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 2 ]]
}

# D. Count & History

@test "D1: count increments by 1 on each call" {
  guard "$TEST_SID" "Bash"
  guard "$TEST_SID" "Edit"
  guard "$TEST_SID" "Read"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 3 ]]
}

@test "D2: history records each tool name in order (no tool_input)" {
  guard "$TEST_SID" "Bash"
  guard "$TEST_SID" "Edit"
  guard "$TEST_SID" "Read"
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
  [[ "$(read_state "$TEST_SID" '.history[1]')" == "Edit" ]]
  [[ "$(read_state "$TEST_SID" '.history[2]')" == "Read" ]]
}

@test "D2b: history records readable fingerprints when tool_input provided" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"ls -la"}'
  guard_with_input "$TEST_SID" "Read" '{"file_path":"/tmp/a.txt"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash:ls -la" ]]
  [[ "$(read_state "$TEST_SID" '.history[1]')" == "Read:/tmp/a.txt" ]]
}

@test "D2c: same tool with different inputs produces different fingerprints" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"git status"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"git diff"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash:git status" ]]
  [[ "$(read_state "$TEST_SID" '.history[1]')" == "Bash:git diff" ]]
}

@test "D2d: same tool with same input produces identical fingerprints" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"npm test"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"npm test"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "$(read_state "$TEST_SID" '.history[1]')" ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash:npm test" ]]
}

@test "D2e: Grep fingerprint uses pattern" {
  guard_with_input "$TEST_SID" "Grep" '{"pattern":"TODO","path":"/src"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Grep:TODO" ]]
}

@test "D2f: Glob fingerprint uses pattern" {
  guard_with_input "$TEST_SID" "Glob" '{"pattern":"**/*.ts"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Glob:**/*.ts" ]]
}

@test "D2g: Edit fingerprint uses file_path" {
  guard_with_input "$TEST_SID" "Edit" '{"file_path":"/src/index.ts"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Edit:/src/index.ts" ]]
}

@test "D2h: Bash fingerprint truncated at 80 chars" {
  local long_cmd
  long_cmd="$(printf 'x%.0s' {1..100})"
  guard_with_input "$TEST_SID" "Bash" "{\"command\":\"${long_cmd}\"}"
  local fp
  fp="$(read_state "$TEST_SID" '.history[0]')"
  [[ "${#fp}" -le 85 ]]
  [[ "$fp" == Bash:* ]]
}

@test "D3: history trimmed to LOOP_WINDOW size" {
  seed_state "$TEST_SID" '{"count":4,"limit":200,"warn_at":140,"history":["A","B","C","D"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "E" LOOP_WINDOW=3
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

# E. Hard Limit

@test "E1: call at exactly the limit is allowed" {
  seed_state "$TEST_SID" '{"count":199,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
  [[ "$(read_state "$TEST_SID" '.count')" -eq 200 ]]
}

@test "E2: call exceeding the limit exits 2" {
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
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"BUDGET EXCEEDED"* ]]
  [[ "$stderr" != *"LOOP DETECTED"* ]]
}

# F. Loop Detection -- exact fingerprint matching (CHECK 2a)

@test "F1: below threshold is allowed (4 identical fingerprints)" {
  # 4 Bash + 3 Edit + 2 Grep. Add Grep -> Bash=4, Edit=3, Grep=3. All < 5.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Edit","Edit","Grep","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Grep"
  [[ "$status" -eq 0 ]]
}

@test "F2: at threshold triggers loop block (5 identical fingerprints)" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Edit","Edit","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "F3: loop message includes tool name and count" {
  # 4 Read + 3 Edit + 2 Grep. Add Read -> 5 Read >= 5. Edit=3, Grep=2. Only Read triggers.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Read","Read","Read","Read","Edit","Edit","Edit","Grep","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Read"
  [[ "$stderr" == *"Read"* ]]
  [[ "$stderr" == *"5 times"* ]]
}

@test "F4: mixed tools below threshold are allowed" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Edit","Read","Bash","Edit","Read","Bash","Edit","Read"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 0 ]]
}

@test "F5: LOOP_THRESHOLD override is respected" {
  seed_state "$TEST_SID" '{"count":3,"limit":200,"warn_at":999,"history":["Bash","Bash","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=3 LOOP_WINDOW=4
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "F6: LOOP_WINDOW override is respected" {
  seed_state "$TEST_SID" '{"count":5,"limit":200,"warn_at":999,"history":["Bash","Bash","Edit","Edit","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=3 LOOP_WINDOW=5
  [[ "$status" -eq 2 ]]
}

@test "F7: loop clears when window slides past repeated calls" {
  # 4 Bash + 3 Edit + 3 Grep. Add Grep -> trim to 10: [Bash x3, Edit x3, Grep x3, Grep].
  # Bash=3, Edit=3, Grep=4. All < 5.
  seed_state "$TEST_SID" '{"count":10,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Edit","Edit","Grep","Grep","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Grep"
  [[ "$status" -eq 0 ]]
}

@test "F8: state file is saved even when loop blocks" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Edit","Edit","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ -f "$(state_file "$TEST_SID")" ]]
  [[ "$(read_state "$TEST_SID" '.count')" -eq 10 ]]
}

@test "F9: same tool with different inputs does NOT trigger exact loop" {
  seed_state "$TEST_SID" '{"count":8,"limit":200,"warn_at":999,"history":["Bash:git status","Bash:git diff","Bash:git log","Bash:npm test","Bash:npm run build","Bash:vercel deploy","Bash:gh pr list","Bash:ls"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"unique_cmd"}'
  [[ "$status" -eq 0 ]]
  [[ "$stderr" != *"LOOP DETECTED"* ]]
}

@test "F10: exact same fingerprint repeated hits threshold" {
  # 5x "Read:/stuck.ts" + 2 Edit + 2 Grep. Add Grep -> Read=5 >= 5. Edit=2, Grep=3. Only Read triggers.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Read:/stuck.ts","Read:/stuck.ts","Read:/stuck.ts","Read:/stuck.ts","Read:/stuck.ts","Edit","Edit","Grep","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Grep"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
  [[ "$stderr" == *"Read"* ]]
}

@test "F11: readable Bash fingerprints in loop message" {
  seed_state "$TEST_SID" '{"count":4,"limit":200,"warn_at":999,"history":["Bash:npm test","Bash:npm test","Bash:npm test","Bash:npm test"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"npm test"}'
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"npm test"* ]]
}

# Fb. Tool Repeat Warning -- same tool, varied inputs (CHECK 2b)

@test "Fb1: tool repeat warning fires at TOOL_REPEAT_THRESHOLD (default 9)" {
  seed_state "$TEST_SID" '{"count":8,"limit":200,"warn_at":999,"history":["Bash:git status","Bash:git diff","Bash:git log","Bash:npm test","Bash:npm build","Bash:vercel deploy","Bash:gh pr list","Bash:ls"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"another_unique"}'
  [[ "$status" -eq 0 ]]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
  local ctx
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"TOOL REPEAT"* ]]
  [[ "$ctx" == *"Bash"* ]]
}

@test "Fb2: tool repeat warning is not a hard block" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash:a","Bash:b","Bash:c","Bash:d","Bash:e","Bash:f","Bash:g","Bash:h","Bash:i"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"yet_another"}'
  [[ "$status" -eq 0 ]]
  [[ "$stderr" != *"LOOP DETECTED"* ]]
}

@test "Fb3: below TOOL_REPEAT_THRESHOLD produces no warning" {
  seed_state "$TEST_SID" '{"count":8,"limit":200,"warn_at":999,"history":["Bash:a","Bash:b","Bash:c","Bash:d","Bash:e","Bash:f","Bash:g","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"something"}'
  [[ "$status" -eq 0 ]]
  [[ -z "$output" ]]
}

@test "Fb4: TOOL_REPEAT_THRESHOLD override is respected" {
  seed_state "$TEST_SID" '{"count":3,"limit":200,"warn_at":999,"history":["Bash:aaa","Bash:bbb","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"x"}' TOOL_REPEAT_THRESHOLD=3 LOOP_WINDOW=4
  [[ "$status" -eq 0 ]]
  local ctx
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"TOOL REPEAT"* ]]
}

@test "Fb5: exact loop takes precedence over tool repeat warning" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash:abc","Bash:abc","Bash:abc","Bash:abc","Bash:abc","Bash:def","Bash:ghi","Bash:jkl","Bash:mno"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Edit"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "Fb6: budget warning combined with tool repeat warning" {
  seed_state "$TEST_SID" '{"count":139,"limit":200,"warn_at":140,"history":["Bash:a","Bash:b","Bash:c","Bash:d","Bash:e","Bash:f","Bash:g","Bash:h","Bash:i"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"j"}'
  [[ "$status" -eq 0 ]]
  local ctx
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"TOKEN BUDGET WARNING"* ]]
  [[ "$ctx" == *"TOOL REPEAT"* ]]
}

# G. Warning Threshold

@test "G1: below warning threshold produces no stdout" {
  seed_state "$TEST_SID" '{"count":138,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
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

# H. Configuration

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

# I. State Isolation

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

@test "I3: existing state file limit used -- env var ignored mid-session" {
  seed_state "$TEST_SID" '{"count":99,"limit":100,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=200
  [[ "$status" -eq 0 ]]
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=200
  [[ "$status" -eq 2 ]]
}

# J. Edge Cases

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

@test "J3: LOOP_THRESHOLD=1 blocks on first call" {
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
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Edit","Edit","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$stderr" == *"/token-budget-guard:reset"* ]]
}

@test "J6: old-format history entries work with loop detection" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Edit"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "J7: tool_input with empty object produces no fingerprint suffix" {
  local input
  input='{"session_id":"'"$TEST_SID"'","tool_name":"Bash","tool_input":{}}'
  run --separate-stderr bash "$GUARD" <<< "$input"
  [[ "$status" -eq 0 ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
}

# K. Reset Bypass -- reset command must work even when blocked

@test "K1: reset command bypasses hard limit" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"for f in /tmp/claude-budget-guard-*.json; do jq . \"$f\"; done"}'
  [[ "$status" -eq 0 ]]
}

@test "K2: reset command bypasses loop detection" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Edit","Edit","Edit","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"jq \".count = 0\" /tmp/claude-budget-guard-abc.json"}'
  [[ "$status" -eq 0 ]]
}

@test "K3: non-reset Bash still blocked at hard limit" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"npm test"}'
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"BUDGET EXCEEDED"* ]]
}

@test "K4: reset command still increments counter" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"for f in /tmp/claude-budget-guard-*.json; do jq . \"$f\"; done"}'
  [[ "$(read_state "$TEST_SID" '.count')" -eq 201 ]]
}

@test "K5: non-Bash tool not eligible for reset bypass" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Read" '{"file_path":"/tmp/claude-budget-guard-x.json"}'
  [[ "$status" -eq 2 ]]
}
