# /token-budget-guard:uninstall

Remove the token budget guard from Claude Code settings.

## Instructions

### Step 1: Remove hook from settings

```bash
SETTINGS="$HOME/.claude/settings.json"

if [[ ! -f "$SETTINGS" ]]; then
  echo "No settings file found at $SETTINGS — nothing to uninstall."
else
  if jq -e '.hooks.PreToolUse' "$SETTINGS" 2>/dev/null | grep -q "budget-guard"; then
    jq '.hooks.PreToolUse = [.hooks.PreToolUse[] | select(.hooks | tostring | contains("budget-guard") | not)]' \
      "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    # Clean up empty PreToolUse array
    jq 'if .hooks.PreToolUse == [] then del(.hooks.PreToolUse) else . end | if .hooks == {} then del(.hooks) else . end' \
      "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
    echo "Removed budget-guard hook from $SETTINGS"
  else
    echo "No budget-guard hook found in $SETTINGS — nothing to remove."
  fi
fi
```

### Step 2: Clean up state files

```bash
rm -f /tmp/claude-budget-guard-*.json && echo "Cleaned up state files."
```

### Step 3: Ask about plugin directory

Ask the user: "Do you also want to remove the plugin directory at `~/.claude/plugins/token-budget-guard/`?"

Only remove it if the user confirms.

### Step 4: Confirm

Tell the user:

> **Uninstalled.** The budget guard will no longer run on tool calls.
> State files have been cleaned up. To reinstall, run `/token-budget-guard:install`.
