# /token-budget-guard:help

Show help for the token budget guard plugin.

## Instructions

Display the following to the user exactly:

---

**token-budget-guard** — Prevents runaway loops and token budget overruns in Claude Code.

Runs a PreToolUse hook on every tool call. Three checks, in order:

| Check | Default | What happens |
|-------|---------|-------------|
| Reset bypass | Bash commands targeting state files | Always allowed (prevents deadlock) |
| Hard limit | 200 calls | Blocks the tool call (exit 2) |
| Exact loop | 5 identical calls in last 10 | Blocks the tool call (exit 2) |
| Tool repeat | 9 same-tool calls in last 10 | Injects a warning (non-blocking) |
| Budget warning | At 70% of limit | Injects a warning into context |

**Skills:**

| Command | What it does |
|---------|-------------|
| `/token-budget-guard:help` | This help message |
| `/token-budget-guard:status` | Show call count, remaining budget, loop risk |
| `/token-budget-guard:reset` | Reset counter (escape hatch) |
| `/token-budget-guard:install` | Install into your Claude Code settings |
| `/token-budget-guard:uninstall` | Remove from your Claude Code settings |

**Configuration** (env vars in `.claude/settings.json`):

| Variable | Default | |
|----------|---------|---|
| `BUDGET_LIMIT` | `200` | Max tool calls per session |
| `BUDGET_WARN` | 70% of limit | Warning threshold |
| `LOOP_WINDOW` | `10` | Sliding window size |
| `LOOP_THRESHOLD` | `5` | Identical fingerprints to trigger block |
| `TOOL_REPEAT_THRESHOLD` | `9` | Same-tool calls to trigger warning |

**Quick start:**
```
/token-budget-guard:install
```

**More info:** https://github.com/jadecli/token-budget-guard

---
