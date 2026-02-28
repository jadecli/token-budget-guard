#!/usr/bin/env bats
#
# Install/uninstall script tests
#
# These tests use a sandboxed HOME so they never touch real user settings.
# Run: bats tests/install.bats
#

bats_require_minimum_version 1.5.0

REPO_DIR="$BATS_TEST_DIRNAME/.."
INSTALL="$REPO_DIR/install.sh"
UNINSTALL="$REPO_DIR/uninstall.sh"

setup() {
  # Sandbox: each test gets its own fake HOME
  export REAL_HOME="$HOME"
  export HOME="$(mktemp -d)"
  mkdir -p "$HOME/.claude/plugins"
}

teardown() {
  rm -rf "$HOME"
  export HOME="$REAL_HOME"
}

# ══════════════════════════════════════════════════════════════════════════════
# Install
# ══════════════════════════════════════════════════════════════════════════════

@test "install: creates settings.json when none exists" {
  run --separate-stderr bash "$INSTALL"
  [[ "$status" -eq 0 ]]
  [[ -f "$HOME/.claude/settings.json" ]]
}

@test "install: settings.json contains budget-guard hook" {
  run --separate-stderr bash "$INSTALL"
  jq -e '.hooks.PreToolUse[] | select(.hooks[].command | contains("budget-guard"))' \
    "$HOME/.claude/settings.json"
}

@test "install: clones repo to plugins directory" {
  run --separate-stderr bash "$INSTALL"
  [[ -f "$HOME/.claude/plugins/token-budget-guard/hooks/budget-guard.sh" ]]
}

@test "install: is idempotent — running twice doesn't duplicate hook" {
  bash "$INSTALL" &>/dev/null
  bash "$INSTALL" &>/dev/null
  local count
  count="$(jq '[.hooks.PreToolUse[] | select(.hooks[].command | contains("budget-guard"))] | length' \
    "$HOME/.claude/settings.json")"
  [[ "$count" -eq 1 ]]
}

@test "install: preserves existing settings" {
  mkdir -p "$HOME/.claude"
  echo '{"theme": "dark", "hooks": {}}' > "$HOME/.claude/settings.json"
  bash "$INSTALL" &>/dev/null
  jq -e '.theme == "dark"' "$HOME/.claude/settings.json"
  jq -e '.hooks.PreToolUse' "$HOME/.claude/settings.json"
}

@test "install: preserves existing PreToolUse hooks" {
  mkdir -p "$HOME/.claude"
  echo '{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "other-hook.sh"}]}]}}' \
    > "$HOME/.claude/settings.json"
  bash "$INSTALL" &>/dev/null
  local count
  count="$(jq '.hooks.PreToolUse | length' "$HOME/.claude/settings.json")"
  [[ "$count" -eq 2 ]]
  jq -e '.hooks.PreToolUse[] | select(.hooks[].command == "other-hook.sh")' "$HOME/.claude/settings.json"
}

@test "install: output mentions success" {
  run --separate-stderr bash "$INSTALL"
  [[ "$output" == *"Installed"* ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# Uninstall
# ══════════════════════════════════════════════════════════════════════════════

@test "uninstall: removes budget-guard hook from settings" {
  bash "$INSTALL" &>/dev/null
  # Verify it's there first
  jq -e '.hooks.PreToolUse' "$HOME/.claude/settings.json" >/dev/null
  # Uninstall (pipe 'n' to skip directory removal prompt)
  echo "n" | bash "$UNINSTALL" &>/dev/null
  # Hook should be gone
  local result
  result="$(jq '.hooks.PreToolUse // empty' "$HOME/.claude/settings.json")"
  [[ -z "$result" || "$result" == "null" ]]
}

@test "uninstall: preserves other hooks" {
  mkdir -p "$HOME/.claude"
  echo '{"hooks": {"PreToolUse": [{"hooks": [{"type": "command", "command": "other-hook.sh"}]}]}}' \
    > "$HOME/.claude/settings.json"
  bash "$INSTALL" &>/dev/null
  echo "n" | bash "$UNINSTALL" &>/dev/null
  jq -e '.hooks.PreToolUse[] | select(.hooks[].command == "other-hook.sh")' "$HOME/.claude/settings.json"
}

@test "uninstall: cleans up state files" {
  # Create some fake state files
  echo '{"count":5}' > /tmp/claude-budget-guard-test-uninstall-1.json
  echo '{"count":3}' > /tmp/claude-budget-guard-test-uninstall-2.json
  echo "n" | bash "$UNINSTALL" &>/dev/null
  [[ ! -f /tmp/claude-budget-guard-test-uninstall-1.json ]]
  [[ ! -f /tmp/claude-budget-guard-test-uninstall-2.json ]]
}

@test "uninstall: handles missing settings gracefully" {
  # No settings file at all
  run --separate-stderr bash "$UNINSTALL" <<< "n"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"skipping"* ]]
}

@test "uninstall: removes plugin dir when user confirms" {
  bash "$INSTALL" &>/dev/null
  [[ -d "$HOME/.claude/plugins/token-budget-guard" ]]
  echo "y" | bash "$UNINSTALL" &>/dev/null
  [[ ! -d "$HOME/.claude/plugins/token-budget-guard" ]]
}

@test "uninstall: keeps plugin dir when user declines" {
  bash "$INSTALL" &>/dev/null
  echo "n" | bash "$UNINSTALL" &>/dev/null
  [[ -d "$HOME/.claude/plugins/token-budget-guard" ]]
}

# ══════════════════════════════════════════════════════════════════════════════
# Round-trip
# ══════════════════════════════════════════════════════════════════════════════

@test "round-trip: install then uninstall leaves clean settings" {
  bash "$INSTALL" &>/dev/null
  echo "y" | bash "$UNINSTALL" &>/dev/null
  # Settings should have no hooks key (cleaned up)
  local hooks
  hooks="$(jq '.hooks // empty' "$HOME/.claude/settings.json")"
  [[ -z "$hooks" || "$hooks" == "null" ]]
}
