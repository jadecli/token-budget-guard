# token-budget-guard in jadecli

## Role: L0 safety net

token-budget-guard is the foundation layer (L0) of the jadecli plugin stack.
It runs on every tool call in every session across every repo. Nothing else
in the stack has this property.

```
L3  knowledge-teams-plugins   10 S-team agents, compose over L2, WebMCP stubs
L2  knowledge-work-plugins    11 role plugins (fork of anthropics upstream)
L1  jadecli-plugins            adaptive-agent v1.2.0 + devtools
L0  token-budget-guard         PreToolUse on every call. You are here.
```

L0 and L1 both fire PreToolUse hooks on every tool call. L0 prevents loops
and enforces budgets. L1 warns on destructive git ops. They coexist without
conflict because L0 blocks (exit 2) while L1 warns (exit 0 with output).

## What it enforces

### Per-session budget
Global `BUDGET_LIMIT` (default 500, set to 200 in jadecli). Hard stop when
exceeded. Prevents runaway sessions from burning tokens.

### Loop detection
Fingerprints each tool call (tool name + key input). When the same fingerprint
appears `LOOP_THRESHOLD` times (default 5, set to 8 in jadecli) in the last
`LOOP_WINDOW` calls, the call is blocked.

Fingerprinted tools:
- `Bash:command` (80 chars)
- `Read:/path`, `Write:/path`, `Edit:/path#old_string` (40 chars)
- `Grep:pattern` (40 chars), `Glob:pattern` (40 chars)
- `WebFetch:url` (60 chars), `WebSearch:query` (60 chars)
- `TaskCreate:subject` (60 chars), `TaskUpdate:subject` (60 chars)

### Per-contract budget (v2.0.0)
`lib/contracts.js` tracks tool_calls, input_tokens, output_tokens, total_tokens,
and cost_usd per contract. Warns at 70%, blocks at 100%. OP1 defines 42 contracts
(N-001 to N-042) with individual budgets. Total budget: 7850 tool calls.

### Agent team coordination
- `TeammateIdle` hook: keeps teammate working if contract has budget remaining
- `TaskCompleted` hook: aggregates usage, warns on overage
- `lib/team-budget.js`: sums usage across all teammates in a team

## How jadebot uses it

jadebot (jadecli/jadebot) is the compute layer. PR #15 defines the OP1 operating
plan with 42 contracts across 5 epics. PR #16 defines contract types, XML I/O,
and the agent runner. PR #25 defines an agent team that reviews PR #15 documents.

```
OP1 plan (PR #15)
  → 42 contracts with budgets
    → token-budget-guard contracts.js enforces per-contract limits
      → teammates get individual budgets (30, 20, etc. tool calls)
        → PreToolUse hook checks on every call
          → TeammateIdle keeps them working while budget remains
            → TaskCompleted aggregates and reports
```

The lead agent ("jade") orchestrates teammates. Each teammate gets a contract
with a budget. token-budget-guard enforces the budget without the teammate
needing to track it. The lead reads contract status from
`/tmp/claude-contracts/*.json` to know when teammates are done.

## How jade-agents-webmcp uses it

jade-agents-webmcp (jadecli/jade-agents-webmcp) is the state layer. It stores
contracts via `POST/GET/PATCH /api/contracts` on jadecli.app (Neon Postgres).
PR #90 adds the contracts API. PR #91 adds context management.

```
jade-agents-webmcp stores contracts (persistent, cloud)
  ↕ API calls
token-budget-guard enforces contracts (ephemeral, local)
  ↕ hooks
claude-code runs tools (session-scoped)
```

The contracts API persists state across sessions. token-budget-guard reads
contracts at session start and enforces them locally. When a session ends,
usage data can be posted back to the API for cross-session tracking.

## Repos that depend on L0

| Repo | Why |
|------|-----|
| `jadecli/jadebot` | Compute layer. Agent teams, contract execution. |
| `jadecli/jade-agents-webmcp` | State layer. Contracts API, PM service. |
| `jadecli/jadecli-plugins` | L1 plugin. Both PreToolUse hooks fire. |
| `jadecli/knowledge-work-plugins` | L2 plugins. Budget applies to role work. |
| `jadecli/knowledge-teams-plugins` | L3 S-team. Budget applies to team work. |
| `jadecli/teamctl` | Permissions CLI. Reads team budget state. |
| `jadecli/jade-rag` | MCP server. Budget applies to cache fetches. |

## Related repos (no direct dependency)

| Repo | Relationship |
|------|-------------|
| `jadecli/atlas-ts` | Metrics engine. Could consume budget telemetry. |
| `jadecli/spectator` | Metrics client (Netflix fork). Emits budget events. |
| `jadecli/ghostty` | Terminal fork. Displays budget in status line. |
| `jadecli/jade-research-webmcp` | Data explorer. No budget interaction. |
| `jadecli/oh-my-logo` | Branding. No budget interaction. |

## Installed state

```
Path:    ~/.claude/plugins/token-budget-guard/
Version: 2.0.0
Commit:  990395a (main) + PR #8 (fingerprint coverage)
SDK:     @anthropic-ai/sdk@0.78.0
Tests:   143 (96 bats + 14 install + 33 node)
```

Hooks registered in `~/.claude/settings.json`:
- `PreToolUse` → `hooks/budget-guard.sh`
- `TeammateIdle` → `hooks/teammate-idle.js`
- `TaskCompleted` → `hooks/task-completed.js`

Environment:
- `BUDGET_LIMIT=200`
- `LOOP_THRESHOLD=8`
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

## State files

- `/tmp/claude-budget-guard-{session_id}.json` — per-session budget state
- `/tmp/claude-contracts/*.json` — per-contract budget state
- `~/.claude/teams/{team-name}/config.json` — team member list (read by team-budget.js)
