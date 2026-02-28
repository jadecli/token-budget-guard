#!/usr/bin/env bash
# token-budget-guard uninstaller
set -euo pipefail

PLUGIN_DIR="$HOME/.claude/plugins/token-budget-guard"
SETTINGS="$HOME/.claude/settings.json"

echo "token-budget-guard uninstaller"
echo "────────────────────────────────"

# 1. Remove hook from settings
if [[ -f "$SETTINGS" ]] && command -v jq &>/dev/null; then
  if jq -e '.hooks.PreToolUse' "$SETTINGS" 2>/dev/null | grep -q "budget-guard"; then
    jq '.hooks.PreToolUse = [.hooks.PreToolUse[] | select(.hooks | tostring | contains("budget-guard") | not)]' \
      "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    jq 'if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end | if .hooks == {} then del(.hooks) else . end' \
      "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "[1/3] Removed hook from $SETTINGS"
  else
    echo "[1/3] No hook found — skipping"
  fi
else
  echo "[1/3] No settings file — skipping"
fi

# 2. Clean up state files
rm -f /tmp/claude-budget-guard-*.json
echo "[2/3] Cleaned up state files"

# 3. Remove plugin directory
if [[ -d "$PLUGIN_DIR" ]]; then
  read -rp "Remove $PLUGIN_DIR? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -rf "$PLUGIN_DIR"
    echo "[3/3] Removed $PLUGIN_DIR"
  else
    echo "[3/3] Kept $PLUGIN_DIR"
  fi
else
  echo "[3/3] No plugin directory — skipping"
fi

echo ""
echo "Uninstalled. To reinstall: /token-budget-guard:install"
