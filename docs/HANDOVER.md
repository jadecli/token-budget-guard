# Handover: Claude Ecosystem Integration

> For the next agent picking up this work.

## What this PR contains

| File | Purpose |
|------|---------|
| `claude-ecosystem-reference.md` | 40 official plugins catalog + Neon pgvector embedding router architecture + connector summary tables |
| `claude-customize-scrape.py` | Structured scrape of claude.ai/customize — tool permissions, skill content summaries, org metadata |
| `jadecli-integration-analysis.json` | 4-layer integration model across 4 jadecli repos + connector coverage + skills overlap |

## The 4-layer stack

```
L3  knowledge-teams-plugins   S-team orchestration (10 C-suite agents, WebMCP)
L2  knowledge-work-plugins    Role-based business knowledge (11 plugins, 36+ connectors)
L1  jadecli-plugins            Engineering methodology (adaptive-agent, devtools)
L0  token-budget-guard         Safety net (PreToolUse hook, every tool call)
```

Cross-cutting: Claude.ai org skills (creative/design, web UI) + connectors (9 connected, runtime tool access).

## Connector gap

9 connectors connected in Claude.ai org. 36+ declared by KWP plugins but not connected. See `jadecli-integration-analysis.json` → `connector_coverage_map.declared_in_kwp_but_not_connected`.

## Decisions needed

1. **pgvector router**: Build as Claude Code plugin with Neon schema + seed script for all 40 official plugins? Architecture is in `claude-ecosystem-reference.md`.
2. **Connector gap**: Which of the 36+ missing connectors to prioritize? Slack covers 9/11 KWP plugins. Notion + Jira + Asana would unlock 6 more.
3. **S-team WebMCP**: jadecli.app and jadecli.com tool stubs need backing services. Build as Vercel serverless or standalone?
4. **Test count**: token-budget-guard is at 140 tests (updated from 86 in the analysis JSON). The analysis JSON still says 86 — next agent should reconcile.

## How to read this

- Start with `jadecli-integration-analysis.json` → `integration_analysis.layer_model` for the big picture
- Cross-reference connector names against `claude-customize-scrape.py` → `connector_details` for exact tool permissions
- Use `claude-ecosystem-reference.md` for the full plugin inventory when deciding what to enable per-project
