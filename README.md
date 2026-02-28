# token-budget-guard

Stops runaway Claude Code sessions before they burn your budget. Pure bash + jq.

## Quick start

```bash
# 1. Install jq (if you don't have it)
brew install jq          # macOS
# apt install jq         # Linux

# 2. Install the guard
curl -fsSL https://raw.githubusercontent.com/jadecli/token-budget-guard/main/install.sh | bash

# 3. Done — starts working on your next Claude Code session
```

## What it does

Runs on every tool call. Three checks, in order:

1. **Hard limit** — 200 tool calls per session → blocks (exit 2)
2. **Loop detection** — same tool 8+ times in last 10 calls → blocks (exit 2)
3. **Warning** — at 70% of limit → injects a heads-up into context (exit 0)

## Configure

Add to `~/.claude/settings.json`:

```json
{ "env": { "BUDGET_LIMIT": "300", "BUDGET_WARN": "210" } }
```

| Variable | Default | What |
|----------|---------|------|
| `BUDGET_LIMIT` | `200` | Max tool calls per session |
| `BUDGET_WARN` | 70% of limit | When to start warning |
| `LOOP_WINDOW` | `10` | How many recent calls to check |
| `LOOP_THRESHOLD` | `8` | How many repeats = loop |

## Commands

| Command | What |
|---------|------|
| `/token-budget-guard:status` | Call count, remaining budget, loop risk |
| `/token-budget-guard:reset` | Reset counter (escape hatch) |
| `/token-budget-guard:help` | Quick reference |

## Uninstall

```bash
~/.claude/plugins/token-budget-guard/uninstall.sh
```

## Run tests

```bash
bats tests/
```

## License

MIT
