# Dependencies

## @anthropic-ai/sdk — v0.78.0

**Pinned**: `0.78.0` (2026-02-19)
**Source**: [Stainless-generated SDK](https://github.com/anthropics/anthropic-sdk-typescript)
**Changelog**: `node_modules/@anthropic-ai/sdk/CHANGELOG.md`

### Used APIs

| API | Method | Purpose |
|-----|--------|---------|
| `messages.countTokens()` | POST `/v1/messages/count_tokens` | Pre-flight token estimation for contracts |
| `response.usage` | (response field) | Post-call actual token counts |

### Key features at this version

- Top-level cache control (automatic caching) — v0.78.0
- claude-sonnet-4-6 model support — v0.75.0
- UserLocation + error code types — v0.77.0

### Upgrade protocol

1. `npm view @anthropic-ai/sdk version` — check latest
2. Read changelog diff: `npx stainless changelog @anthropic-ai/sdk 0.78.0..NEW`
3. Check for breaking changes in `messages.countTokens()` or `usage` response shape
4. Pin exact version in package.json (no caret)
5. Run `npm test && npm run test:contracts`
