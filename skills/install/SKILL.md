# /token-budget-guard:install

Install the token budget guard into Claude Code settings.

## Instructions

Walk the user through installation. Run the following steps:

### Step 1: Check for jq

```bash
command -v jq && echo "OK: jq found at $(command -v jq)" || echo "MISSING: install jq first — brew install jq (macOS) or apt install jq (Linux)"
```

If jq is missing, tell the user to install it and stop. Don't continue without jq.

### Step 2: Find the plugin directory

Determine where the token-budget-guard repo lives. Check in order:
1. Current working directory (if it contains `hooks/budget-guard.sh`)
2. `~/.claude/plugins/token-budget-guard/` (if it exists)
3. Otherwise, ask the user if they'd like to clone it

If cloning is needed:
```bash
mkdir -p ~/.claude/plugins && git clone https://github.com/jadecli/token-budget-guard.git ~/.claude/plugins/token-budget-guard
```

### Step 3: Add hook to settings

Read the user's `~/.claude/settings.json`. If it doesn't exist, create it. Add the PreToolUse hook entry.

```bash
GUARD_DIR="<resolved path to token-budget-guard>"
SETTINGS="$HOME/.claude/settings.json"

# Create settings.json if it doesn't exist
if [[ ! -f "$SETTINGS" ]]; then
  echo '{}' > "$SETTINGS"
fi

# Check if hook is already installed
if jq -e '.hooks.PreToolUse' "$SETTINGS" 2>/dev/null | grep -q "budget-guard"; then
  echo "Already installed! budget-guard hook found in $SETTINGS"
else
  # Add the hook using jq
  jq --arg cmd "$GUARD_DIR/hooks/budget-guard.sh" \
    '.hooks.PreToolUse = (.hooks.PreToolUse // []) + [{"hooks": [{"type": "command", "command": $cmd}]}]' \
    "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
  echo "Installed! Hook added to $SETTINGS"
fi
```

### Step 4: Verify

```bash
jq '.hooks.PreToolUse' "$HOME/.claude/settings.json"
```

### Step 5: Confirm to the user

Tell the user:

> **Installed.** The budget guard will activate on your next Claude Code session.
>
> Defaults: 200 call limit, warning at 140, loop detection at 8/10.
>
> To customize, add to your `.claude/settings.json`:
> ```json
> { "env": { "BUDGET_LIMIT": "300" } }
> ```
>
> Run `/token-budget-guard:status` to check it's working.
