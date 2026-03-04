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
# No tool_input -> history stores just the tool name (no fingerprint suffix).
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

# Invoke the guard with tool_input (as a JSON object) for fingerprint tests.
# Usage: guard_with_input SESSION_ID TOOL_NAME TOOL_INPUT_JSON [ENV_VAR=val ...]
# TOOL_INPUT_JSON is raw JSON, e.g. '{"command":"ls"}' or '{"file_path":"/tmp/a.txt"}'
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
  # Without tool_input, fingerprint is just the tool name
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
  [[ -n "$(read_state "$TEST_SID" '.started')" ]]
}

@test "C1b: first call with tool_input stores human-readable fingerprint" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"ls -la"}'
  [[ "$(read_state "$TEST_SID" '.count')" -eq 1 ]]
  [[ "$(read_state "$TEST_SID" '.history | length')" -eq 1 ]]
  # With tool_input, history stores "Bash:ls -la"
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash:ls -la" ]]
}

@test "C1c: Read tool stores file_path in fingerprint" {
  guard_with_input "$TEST_SID" "Read" '{"file_path":"/tmp/test.txt"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Read:/tmp/test.txt" ]]
}

@test "C1d: Grep tool stores pattern in fingerprint" {
  guard_with_input "$TEST_SID" "Grep" '{"pattern":"TODO"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Grep:TODO" ]]
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

@test "D2: history records each tool name in order (no tool_input)" {
  guard "$TEST_SID" "Bash"
  guard "$TEST_SID" "Edit"
  guard "$TEST_SID" "Read"
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
  [[ "$(read_state "$TEST_SID" '.history[1]')" == "Edit" ]]
  [[ "$(read_state "$TEST_SID" '.history[2]')" == "Read" ]]
}

@test "D2b: history records fingerprints when tool_input provided" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"ls"}'
  guard_with_input "$TEST_SID" "Read" '{"file_path":"/tmp/a.txt"}'
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash:ls" ]]
  [[ "$(read_state "$TEST_SID" '.history[1]')" == "Read:/tmp/a.txt" ]]
}

@test "D2c: same tool with different inputs produces different fingerprints" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"ls"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"pwd"}'
  local fp0 fp1
  fp0="$(read_state "$TEST_SID" '.history[0]')"
  fp1="$(read_state "$TEST_SID" '.history[1]')"
  [[ "$fp0" == "Bash:ls" ]]
  [[ "$fp1" == "Bash:pwd" ]]
  [[ "$fp0" != "$fp1" ]]
}

@test "D2d: same tool with same input produces identical fingerprints" {
  guard_with_input "$TEST_SID" "Bash" '{"command":"ls"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"ls"}'
  local fp0 fp1
  fp0="$(read_state "$TEST_SID" '.history[0]')"
  fp1="$(read_state "$TEST_SID" '.history[1]')"
  [[ "$fp0" == "$fp1" ]]
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
  # count=200 (will exceed) AND history is all identical (would loop).
  # Hard limit check comes first -> message says BUDGET EXCEEDED, not LOOP DETECTED.
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":["Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:ls"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"BUDGET EXCEEDED"* ]]
  [[ "$stderr" != *"LOOP DETECTED"* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# F. Loop Detection — exact fingerprint matching (CHECK 2a)
# ══════════════════════════════════════════════════════════════════════════════

@test "F1: below threshold is allowed (4 identical fingerprints in window, threshold 5)" {
  # 4 identical fingerprints + varied filler, next call is different -> 4 < 5
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash:ls","Bash:ls","Bash:ls","Bash:ls","Edit","Read","Glob","Write","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Edit" LOOP_THRESHOLD=5
  [[ "$status" -eq 0 ]]
}

@test "F2: different fingerprint for same tool does not trigger loop" {
  # 4 "Bash:ls" + 5 varied. Next call is Bash with different command -> different fingerprint.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash:ls","Bash:ls","Bash:ls","Bash:ls","Edit","Read","Glob","Write","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"pwd"}' LOOP_THRESHOLD=5
  # "Bash:pwd" != "Bash:ls" -> no exact match loop
  [[ "$status" -eq 0 ]]
}

@test "F2b: identical fingerprints at threshold triggers loop block" {
  # 4 identical fingerprints + varied filler, add a 5th identical fingerprint.
  # Without tool_input, fingerprint = just "Bash". Seed 4 "Bash" entries.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Read","Glob","Write","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=5
  # Window: [Bash*4, Edit, Read, Glob, Write, Grep, Bash] -> 5 "Bash" >= 5
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "F3: loop message includes tool name and count" {
  # 4 Read + varied filler. Next Read -> 5 Read >= 5 -> block.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Read","Read","Read","Read","Edit","Glob","Write","Grep","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Read" LOOP_THRESHOLD=5
  [[ "$stderr" == *"Read"* ]]
  [[ "$stderr" == *"5 times"* ]]
}

@test "F4: mixed tools below threshold are allowed" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Edit","Read","Bash","Edit","Read","Bash","Edit","Read"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=5
  # 4 Bash < 5 threshold
  [[ "$status" -eq 0 ]]
}

@test "F5: LOOP_THRESHOLD override is respected" {
  # threshold=3, window has 2 Bash + 1 Edit, next is Bash -> 3 Bash in window -> block.
  seed_state "$TEST_SID" '{"count":3,"limit":200,"warn_at":999,"history":["Bash","Bash","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=3 LOOP_WINDOW=4
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "F6: LOOP_WINDOW override is respected" {
  # Window=5 with threshold=3. History: [Bash, Bash, Edit, Edit, Bash].
  # Next call Bash -> window: [Bash, Edit, Edit, Bash, Bash] -> 3 Bash >= 3 -> block
  seed_state "$TEST_SID" '{"count":5,"limit":200,"warn_at":999,"history":["Bash","Bash","Edit","Edit","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=3 LOOP_WINDOW=5
  [[ "$status" -eq 2 ]]
}

@test "F7: loop clears when window slides past repeated calls" {
  # 4 Bash + varied filler. Next call is something new.
  seed_state "$TEST_SID" '{"count":10,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Read","Glob","Write","Grep","WebSearch"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Edit" LOOP_THRESHOLD=5
  # Window: [Bash*3, Edit, Read, Glob, Write, Grep, WebSearch, Edit] -> 3 Bash < 5
  [[ "$status" -eq 0 ]]
}

@test "F8: state file is saved even when loop blocks" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Read","Glob","Write","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=5
  [[ "$status" -eq 2 ]]
  [[ -f "$(state_file "$TEST_SID")" ]]
  [[ "$(read_state "$TEST_SID" '.count')" -eq 10 ]]
}

@test "F9: same tool with different inputs does NOT trigger exact loop" {
  # 8 Bash calls with different commands — all unique fingerprints.
  seed_state "$TEST_SID" '{"count":8,"limit":200,"warn_at":999,"history":["Bash:ls","Bash:pwd","Bash:date","Bash:whoami","Bash:uname","Bash:env","Bash:cat /tmp/a","Bash:cat /tmp/b"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"echo hello"}' LOOP_THRESHOLD=5 TOOL_REPEAT_THRESHOLD=9
  # No identical fingerprint >= 5 -> no loop block.
  [[ "$status" -eq 0 ]]
  [[ "$stderr" != *"LOOP DETECTED"* ]]
}

@test "F10: exact same fingerprint repeated hits threshold" {
  # 5 identical fingerprints + varied filler -> block.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Read:/tmp/test.txt","Read:/tmp/test.txt","Read:/tmp/test.txt","Read:/tmp/test.txt","Read:/tmp/test.txt","Edit","Glob","Write","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=5
  # Window still has 5x "Read:/tmp/test.txt" -> block
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
  [[ "$stderr" == *"Read"* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# Fb. Tool Repeat Warning — same tool, varied inputs (CHECK 2b)
# ══════════════════════════════════════════════════════════════════════════════

@test "Fb1: tool repeat warning fires at TOOL_REPEAT_THRESHOLD" {
  # 8 Bash calls with different commands in history. Next Bash -> 9 Bash tool names.
  seed_state "$TEST_SID" '{"count":8,"limit":200,"warn_at":999,"history":["Bash:ls","Bash:pwd","Bash:date","Bash:whoami","Bash:uname","Bash:env","Bash:cat /tmp/a","Bash:cat /tmp/b"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"echo hello"}' LOOP_THRESHOLD=5 TOOL_REPEAT_THRESHOLD=9
  # 9 Bash tool names >= 9 -> warning (not block)
  [[ "$status" -eq 0 ]]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
  local ctx
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"TOOL REPEAT"* ]]
  [[ "$ctx" == *"Bash"* ]]
}

@test "Fb2: tool repeat warning is not a hard block — exit 0" {
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash:a","Bash:b","Bash:c","Bash:d","Bash:e","Bash:f","Bash:g","Bash:h","Bash:i"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"another"}' LOOP_THRESHOLD=5 TOOL_REPEAT_THRESHOLD=9
  [[ "$status" -eq 0 ]]
  [[ "$stderr" != *"LOOP DETECTED"* ]]
}

@test "Fb3: below TOOL_REPEAT_THRESHOLD produces no warning" {
  # 7 Bash + 1 Edit in history. Next Bash -> 8 Bash < 9 threshold.
  seed_state "$TEST_SID" '{"count":8,"limit":200,"warn_at":999,"history":["Bash:a","Bash:b","Bash:c","Bash:d","Bash:e","Bash:f","Bash:g","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"something"}' LOOP_THRESHOLD=5 TOOL_REPEAT_THRESHOLD=9
  [[ "$status" -eq 0 ]]
  # No warning output
  [[ -z "$output" ]]
}

@test "Fb4: TOOL_REPEAT_THRESHOLD override is respected" {
  # threshold=3, 2 Bash + 1 Edit. Next Bash -> 3 Bash >= 3 -> warning.
  seed_state "$TEST_SID" '{"count":3,"limit":200,"warn_at":999,"history":["Bash:aaa","Bash:bbb","Edit"],"started":"2026-01-01T00:00:00Z"}'
  guard_with_input "$TEST_SID" "Bash" '{"command":"x"}' LOOP_THRESHOLD=5 TOOL_REPEAT_THRESHOLD=3 LOOP_WINDOW=4
  [[ "$status" -eq 0 ]]
  local ctx
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"TOOL REPEAT"* ]]
}

@test "Fb5: exact loop takes precedence over tool repeat warning" {
  # 5 identical fingerprints AND 9 same-tool fingerprints. Exact loop fires first.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:ls","Bash:pwd","Bash:date","Bash:whoami","Bash:env"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Edit" LOOP_THRESHOLD=5 TOOL_REPEAT_THRESHOLD=9
  # After adding Edit: window has 5x "Bash:ls" -> loop fires (exit 2).
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# G. Warning Threshold — non-blocking context injection
# ══════════════════════════════════════════════════════════════════════════════

@test "G1: below warning threshold produces no stdout" {
  seed_state "$TEST_SID" '{"count":138,"limit":200,"warn_at":140,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash"
  # count=139 < warn_at=140 -> no output
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
  seed_state "$TEST_SID" '{"count":99,"limit":100,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" BUDGET_LIMIT=200
  [[ "$status" -eq 0 ]]
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

@test "J3: LOOP_THRESHOLD=1 blocks on first call — any single identical call triggers" {
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
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Edit","Read","Glob","Write","Grep"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Bash" LOOP_THRESHOLD=5
  [[ "$stderr" == *"/token-budget-guard:reset"* ]]
}

@test "J6: old-format history entries (no colon) work with tool-repeat check" {
  # Backward compatibility: old state files have bare tool names like "Bash".
  # The split(":")[0] in the tool-repeat check handles them correctly.
  seed_state "$TEST_SID" '{"count":9,"limit":200,"warn_at":999,"history":["Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash","Bash"],"started":"2026-01-01T00:00:00Z"}'
  guard "$TEST_SID" "Edit" LOOP_THRESHOLD=5
  # 9 "Bash" entries (no colon) -> exact loop: 9 >= 5 -> LOOP DETECTED
  [[ "$status" -eq 2 ]]
  [[ "$stderr" == *"LOOP DETECTED"* ]]
}

@test "J7: tool_input with empty string produces no fingerprint suffix" {
  # Empty tool_input -> fingerprint is just the tool name
  local input
  input='{"session_id":"'"$TEST_SID"'","tool_name":"Bash","tool_input":{}}'
  run --separate-stderr bash "$GUARD" <<< "$input"
  [[ "$status" -eq 0 ]]
  [[ "$(read_state "$TEST_SID" '.history[0]')" == "Bash" ]]
}

@test "J8: Bash command fingerprint is truncated at 80 chars" {
  local long_cmd
  long_cmd="$(printf 'a%.0s' {1..100})"  # 100-char string
  guard_with_input "$TEST_SID" "Bash" "{\"command\":\"$long_cmd\"}"
  local fp
  fp="$(read_state "$TEST_SID" '.history[0]')"
  # "Bash:" + 80 chars = 85 chars max
  [[ ${#fp} -le 85 ]]
  [[ "$fp" == Bash:* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# K. Reset Bypass — /token-budget-guard:reset can always execute
# ══════════════════════════════════════════════════════════════════════════════

@test "K1: reset command bypasses budget limit" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  # Simulate the reset command that the skill would run
  local input
  input="$(jq -n --arg sid "$TEST_SID" '{session_id: $sid, tool_name: "Bash", tool_input: {command: "jq .count /tmp/claude-budget-guard-test.json"}}')"
  run --separate-stderr bash "$GUARD" <<< "$input"
  # Budget is exceeded (count=201 > 200) but reset commands are allowed
  [[ "$status" -eq 0 ]]
}

@test "K2: reset bypass still increments the counter" {
  seed_state "$TEST_SID" '{"count":200,"limit":200,"warn_at":999,"history":[],"started":"2026-01-01T00:00:00Z"}'
  local input
  input="$(jq -n --arg sid "$TEST_SID" '{session_id: $sid, tool_name: "Bash", tool_input: {command: "jq .count /tmp/claude-budget-guard-test.json"}}')"
  run --separate-stderr bash "$GUARD" <<< "$input"
  [[ "$(read_state "$TEST_SID" '.count')" -eq 201 ]]
}
