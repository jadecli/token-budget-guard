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
Claude: [tool call 500] Read tests/auth.test.ts       ← you've mass-burned tokens
                                                         20 minutes wasted
                                                         nothing fixed
```

**With budget-guard:**

```
You: "Fix the failing test"

Claude: [tool call 1]   Read tests/auth.test.ts
Claude: [tool call 2]   Bash npm test
Claude: [tool call 3]   Read tests/auth.test.ts       ← same file, same input
Claude: [tool call 4]   Read tests/auth.test.ts       ← identical again
Claude: [tool call 5]   Read tests/auth.test.ts       ← identical again
                         ↑
                         LOOP DETECTED: Read called 5 times with identical input
                         in last 10 calls. Blocked to prevent token waste.

Claude: "I notice I'm stuck in a loop reading the same file.
         Let me try a different approach..."
```

5 identical calls instead of 200. The guard caught the loop and Claude self-corrected.

Reading 8 _different_ files? That's fine -- varied inputs are not a loop. The guard only blocks when the same tool is called with the exact same arguments repeatedly.

---

## How it works

A single bash script runs before every tool call. Four checks, in order:

```
Tool call comes in
  │
  ├─ 1. Over budget?          → BLOCK   "500/500 calls used. Session halted."
  │
  ├─ 2a. Identical call loop? → BLOCK   "Read called 5x with identical input."
  │                                       (same tool + same arguments = real loop)
  │
  ├─ 2b. Same tool repeated?  → WARN    "Bash used 9x with varied inputs."
  │                                       (same tool, different args = not a loop)
  │
  ├─ 3. Getting close?        → WARN    "350/500 calls used (70%). 150 remaining."
  │
  └─ All clear                → ALLOW   (silent, zero overhead)
```

Loop detection uses **fingerprints** -- human-readable signatures built from tool name + key input parameters (e.g. `Bash:git status`, `Read:/src/main.ts`). Reading 8 different files is fine. Reading the same file 5 times is a loop. No tokens consumed. No API calls. Just a counter and a sliding window.

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
{ "env": { "BUDGET_LIMIT": "800" } }
```

Changes take effect immediately -- no need to reset or restart. The env var always overrides any value stored in the state file.

| Variable | Default | What |
|----------|---------|------|
| `BUDGET_LIMIT` | `500` | Max tool calls before hard stop |
| `BUDGET_WARN` | 70% of limit | When to inject a warning |
| `LOOP_WINDOW` | `10` | How many recent calls to watch |
| `LOOP_THRESHOLD` | `5` | Identical calls (same tool+input) before hard block |
| `TOOL_REPEAT_THRESHOLD` | `9` | Same tool name (any input) before soft warning |

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
bats tests/    # 86 tests
```

## License

MIT
