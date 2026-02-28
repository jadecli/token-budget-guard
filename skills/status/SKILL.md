# /token-budget-guard:status

Show current token budget guard status for this session.

## Instructions

Read the budget guard state file for the current session and display the status to the user.

1. Find the state file at `/tmp/claude-budget-guard-*.json` matching the current session
2. If no state file exists, report that no budget tracking is active
3. Display the following information:

```
Token Budget Guard Status
─────────────────────────
Calls used:    {count} / {limit}
Remaining:     {remaining}
Warning at:    {warn_at}
Session start: {started}

Top tools:
  {tool_name}: {count} calls
  {tool_name}: {count} calls
  ...

Loop risk: {low|medium|high}
  (based on most frequent tool in last {window} calls)
```

Run this bash command to get the status:

```bash
for f in /tmp/claude-budget-guard-*.json; do
  if [[ -f "$f" ]]; then
    echo "=== $(basename "$f") ==="
    jq '{
      calls_used: .count,
      limit: .limit,
      remaining: (.limit - .count),
      warn_at: .warn_at,
      started: .started,
      top_tools: ([.history[] | {tool: .}] | group_by(.tool) | map({tool: .[0].tool, count: length}) | sort_by(-.count) | .[0:5]),
      loop_risk: (if ([.history[] | {tool: .}] | group_by(.tool) | map(length) | max // 0) >= 6 then "HIGH" elif ([.history[] | {tool: .}] | group_by(.tool) | map(length) | max // 0) >= 4 then "MEDIUM" else "LOW" end)
    }' "$f"
  fi
done
```

If multiple state files exist, show all of them — the user may have multiple sessions.
