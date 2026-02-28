#!/usr/bin/env bash
# token-budget-guard installer
# Usage: curl -fsSL https://raw.githubusercontent.com/jadecli/token-budget-guard/main/install.sh | bash
set -euo pipefail

PLUGIN_DIR="$HOME/.claude/plugins/token-budget-guard"
SETTINGS="$HOME/.claude/settings.json"

echo "token-budget-guard installer"
echo "──────────────────────────────"

# 1. Check jq
if ! command -v jq &>/dev/null; then
  echo ""
  echo "jq is required but not installed."
  echo ""
  if [[ "$(uname)" == "Darwin" ]]; then
    echo "  brew install jq"
  else
    echo "  sudo apt install jq    # Debian/Ubuntu"
    echo "  sudo dnf install jq    # Fedora"
  fi
  echo ""
  echo "Then re-run this installer."
  exit 1
fi
echo "[1/4] jq found at $(command -v jq)"

# 2. Clone or update
if [[ -d "$PLUGIN_DIR/.git" ]]; then
  git -C "$PLUGIN_DIR" pull --quiet
  echo "[2/4] Updated $PLUGIN_DIR"
else
  mkdir -p "$(dirname "$PLUGIN_DIR")"
  git clone --quiet https://github.com/jadecli/token-budget-guard.git "$PLUGIN_DIR"
  echo "[2/4] Cloned to $PLUGIN_DIR"
fi

# 3. Add hook to settings
mkdir -p "$(dirname "$SETTINGS")"
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

if jq -e '.hooks.PreToolUse' "$SETTINGS" 2>/dev/null | grep -q "budget-guard"; then
  echo "[3/4] Hook already installed — skipping"
else
  jq --arg cmd "$PLUGIN_DIR/hooks/budget-guard.sh" \
    '.hooks.PreToolUse = (.hooks.PreToolUse // []) + [{"hooks": [{"type": "command", "command": $cmd}]}]' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "[3/4] Hook added to $SETTINGS"
fi

# 4. Verify
echo "[4/4] Verifying..."
if jq -e '.hooks.PreToolUse[] | select(.hooks[].command | contains("budget-guard"))' "$SETTINGS" &>/dev/null; then
  echo ""
  echo "Installed! Budget guard will activate on your next Claude Code session."
  echo ""
  echo "  Defaults: 200 call limit, warning at 140, loop detection 8/10"
  echo "  Status:   /token-budget-guard:status"
  echo "  Reset:    /token-budget-guard:reset"
  echo "  Help:     /token-budget-guard:help"
  echo ""
  echo "  To customize, add to .claude/settings.json:"
  echo '  { "env": { "BUDGET_LIMIT": "300" } }'
else
  echo ""
  echo "Something went wrong — hook not found in $SETTINGS"
  echo "Try manual install: https://github.com/jadecli/token-budget-guard#install"
  exit 1
fi
