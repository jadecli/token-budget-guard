# /token-budget-guard:reset

Reset the token budget guard counter for the current session.

## Instructions

This is an escape hatch. The user intentionally wants to continue past the budget limit.

1. Find the state file at `/tmp/claude-budget-guard-*.json` matching the current session
2. Reset the counter to 0 and clear the history
3. Confirm the reset to the user

Run this bash command to reset:

```bash
for f in /tmp/claude-budget-guard-*.json; do
  if [[ -f "$f" ]]; then
    jq '.count = 0 | .history = [] | .reset_at = (now | todate)' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
    echo "Budget reset: $(basename "$f")"
    jq '{count: .count, limit: .limit, reset_at: .reset_at}' "$f"
  fi
done
```

If no state files exist, tell the user: "No active budget guard sessions found. The guard will start tracking on the next tool call."

After resetting, confirm: "Budget counter reset to 0/{limit}. The guard will continue tracking from here."
