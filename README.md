# token-budget-guard

Deterministic tool call budgets, loop detection, and circuit breaking for Claude Code.

**Problem**: Claude Code has no built-in prevention for runaway loops or token budget overruns. Real users report infinite loops consuming 7GB RAM, $22K/month overages, and sessions stuck for 20+ minutes.

**Solution**: A PreToolUse hook that counts every tool call, detects loops via sliding window, and circuit-breaks at configurable thresholds. Zero tokens consumed — pure bash + jq.

## Install

```bash
git clone https://github.com/jadecli/token-budget-guard.git
claude --plugin-dir ./token-budget-guard
```

Or add to your Claude Code settings:

```json
{
  "plugins": ["./path/to/token-budget-guard"]
}
```

## How it works

The guard runs as a PreToolUse hook on **every** tool call (Bash, Edit, Write, Read, Glob, Grep, Agent, etc.).

```
Tool call → budget-guard.sh
              ├── CHECK 1: Hard limit exceeded?     → BLOCK (exit 2)
              ├── CHECK 2: Loop detected?            → BLOCK (exit 2)
              ├── CHECK 3: Warning threshold?        → WARN  (exit 0 + context)
              └── All clear                          → ALLOW (exit 0)
```

### Three checks

| Check | What | Default | Action |
|-------|------|---------|--------|
| Hard limit | Total tool calls per session | 200 | Blocks the tool call |
| Loop detection | Same tool N times in last M calls | 8 of 10 | Blocks the tool call |
| Warning | Approaching the limit | 70% (140) | Injects warning into context |

### Loop detection

Uses a sliding window of the last 10 tool names. If any single tool appears 8+ times, it's flagged as a loop. Catches:

- Reading the same file repeatedly (compaction loops)
- Bash retrying the same failing command
- Explore agents re-searching endlessly

## Configuration

Set via environment variables in `.claude/settings.json`:

```json
{
  "env": {
    "BUDGET_LIMIT": "200",
    "BUDGET_WARN": "140",
    "LOOP_WINDOW": "10",
    "LOOP_THRESHOLD": "8"
  }
}
```

| Variable | Default | Description |
|----------|---------|-------------|
| `BUDGET_LIMIT` | `200` | Hard stop — max tool calls per session |
| `BUDGET_WARN` | `140` (70% of limit) | Warning threshold — injects context |
| `LOOP_WINDOW` | `10` | Sliding window size for loop detection |
| `LOOP_THRESHOLD` | `8` | Max same-tool calls in window before block |

## Skills

| Skill | Description |
|-------|-------------|
| `/token-budget-guard:status` | Show current call count, remaining budget, top tools, loop risk |
| `/token-budget-guard:reset` | Reset the counter (escape hatch for intentional long sessions) |

## State

State is stored per-session at `/tmp/claude-budget-guard-{session_id}.json`:

```json
{
  "count": 42,
  "limit": 200,
  "warn_at": 140,
  "history": ["Bash", "Edit", "Read", "Read"],
  "started": "2026-02-28T15:00:00Z"
}
```

State files are in `/tmp` and cleaned up on reboot. No persistent storage needed.

## Requirements

- bash 4+
- [jq](https://jqlang.github.io/jq/) (`brew install jq` / `apt install jq`)

## License

MIT
