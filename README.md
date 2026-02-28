```
 ____            _            _      ____                     _
| __ ) _   _  __| | __ _  ___| |_   / ___|_   _  __ _ _ __ __| |
|  _ \| | | |/ _` |/ _` |/ _ \ __| | |  _| | | |/ _` | '__/ _` |
| |_) | |_| | (_| | (_| |  __/ |_  | |_| | |_| | (_| | | | (_| |
|____/ \__,_|\__,_|\__, |\___|\__|  \____|\__,_|\__,_|_|  \__,_|
                   |___/
```

Stops runaway Claude Code sessions before they burn your budget. Pure bash + jq.

---

## The problem

You ask Claude to fix a test. Claude reads a file. Reads it again. Reads it again. Retries the same bash command. Re-reads the file. 200 tool calls later, you've burned tokens and gotten nowhere.

**Without budget-guard:**

```
You: "Fix the failing test"

Claude: [tool call 1]   Read tests/auth.test.ts
Claude: [tool call 2]   Bash npm test
Claude: [tool call 3]   Read tests/auth.test.ts       ← same file
Claude: [tool call 4]   Read tests/auth.test.ts       ← again
Claude: [tool call 5]   Bash npm test                  ← same command
Claude: [tool call 6]   Read tests/auth.test.ts       ← again
...
Claude: [tool call 47]  Read tests/auth.test.ts       ← still going
Claude: [tool call 48]  Bash npm test                  ← still failing
...
Claude: [tool call 200] Read tests/auth.test.ts       ← you've mass-burned tokens
                                                         20 minutes wasted
                                                         nothing fixed
```

**With budget-guard:**

```
You: "Fix the failing test"

Claude: [tool call 1]   Read tests/auth.test.ts
Claude: [tool call 2]   Bash npm test
Claude: [tool call 3]   Read tests/auth.test.ts
Claude: [tool call 4]   Read tests/auth.test.ts
Claude: [tool call 5]   Read tests/auth.test.ts
Claude: [tool call 6]   Read tests/auth.test.ts
Claude: [tool call 7]   Read tests/auth.test.ts
Claude: [tool call 8]   Read tests/auth.test.ts
                         ↑
                         LOOP DETECTED: Read called 8 times in last 10 calls.
                         Blocked to prevent token waste.

Claude: "I notice I'm stuck in a loop reading the same file.
         Let me try a different approach..."
```

8 calls instead of 200. The guard caught the loop and Claude self-corrected.

---

## How it works

A single bash script runs before every tool call. Three checks, in order:

```
Tool call comes in
  │
  ├─ 1. Over budget?        → BLOCK   "200/200 calls used. Session halted."
  │
  ├─ 2. Same tool looping?  → BLOCK   "Read called 8 times in last 10 calls."
  │
  ├─ 3. Getting close?      → WARN    "140/200 calls used (70%). 60 remaining."
  │
  └─ All clear              → ALLOW   (silent, zero overhead)
```

That's it. No tokens consumed. No API calls. Just a counter and a sliding window.

---

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jadecli/token-budget-guard/main/install.sh | bash
```

That's it. Next Claude Code session, the guard is active.

<details>
<summary>Manual install</summary>

```bash
# Clone
git clone https://github.com/jadecli/token-budget-guard.git ~/.claude/plugins/token-budget-guard

# Add hook to ~/.claude/settings.json
jq '.hooks.PreToolUse = [{"hooks": [{"type": "command", "command": "~/.claude/plugins/token-budget-guard/hooks/budget-guard.sh"}]}]' \
  ~/.claude/settings.json > /tmp/settings.tmp && mv /tmp/settings.tmp ~/.claude/settings.json
```

Requires: bash 4+, [jq](https://jqlang.github.io/jq/) (`brew install jq`)
</details>

## Configure

Defaults work for most people. To customize, add to `~/.claude/settings.json`:

```json
{ "env": { "BUDGET_LIMIT": "300" } }
```

| Variable | Default | What |
|----------|---------|------|
| `BUDGET_LIMIT` | `200` | Max tool calls before hard stop |
| `BUDGET_WARN` | 70% of limit | When to inject a warning |
| `LOOP_WINDOW` | `10` | How many recent calls to watch |
| `LOOP_THRESHOLD` | `8` | Repeated calls before blocking |

## Commands

```
/token-budget-guard:status    → where you are (call count, loop risk)
/token-budget-guard:reset     → reset the counter (escape hatch)
/token-budget-guard:help      → quick reference
```

## Uninstall

```bash
~/.claude/plugins/token-budget-guard/uninstall.sh
```

## Tests

```bash
bats tests/    # 62 tests
```

## License

MIT
