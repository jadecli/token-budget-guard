# Claude Ecosystem Reference

> DRAFT — scraped 2026-03-06 from claude-plugins-official repo + claude.ai/customize

---

## Claude Plugins Official — Complete Inventory

**Total: 40 plugins** (11 LSP + 14 dev workflow + 2 output style + 13 external integrations)

### LSP Analyzers (11)

| Plugin | Language | Extensions | Server | Install |
|--------|----------|-----------|--------|---------|
| typescript-lsp | TypeScript/JS | .ts .tsx .js .jsx .mts .cts .mjs .cjs | typescript-language-server | `npm i -g typescript-language-server typescript` |
| pyright-lsp | Python | .py .pyi | Pyright | `npm i -g pyright` or `pip install pyright` |
| rust-analyzer-lsp | Rust | .rs | rust-analyzer | `rustup component add rust-analyzer` |
| gopls-lsp | Go | .go | gopls | `go install golang.org/x/tools/gopls@latest` |
| clangd-lsp | C/C++ | .c .h .cpp .cc .cxx .hpp .hxx | clangd | `brew install llvm` |
| jdtls-lsp | Java | .java | Eclipse JDT.LS | `brew install jdtls` |
| kotlin-lsp | Kotlin | .kt .kts | kotlin-lsp | `brew install JetBrains/utils/kotlin-lsp` |
| swift-lsp | Swift | .swift | SourceKit-LSP | Included with Xcode / `brew install swift` |
| csharp-lsp | C# | .cs | csharp-ls | `dotnet tool install --global csharp-ls` |
| php-lsp | PHP | .php | Intelephense | `npm i -g intelephense` |
| lua-lsp | Lua | .lua | lua-language-server | `brew install lua-language-server` |

### Development Workflow Plugins (14)

| Plugin | Description |
|--------|-------------|
| plugin-dev | Plugin development toolkit — create commands, agents, skills, hooks, MCP integrations |
| feature-dev | Full feature dev workflow — codebase exploration, architecture design, quality review agents |
| code-review | Automated PR review with multiple specialized agents + confidence scoring |
| code-simplifier | Agent that simplifies/refines code for clarity while preserving functionality |
| commit-commands | Git workflow commands — commit, push, create PRs |
| pr-review-toolkit | PR review agents for comments, tests, error handling, type design, code quality |
| claude-code-setup | Analyzes codebases and recommends tailored hooks, skills, MCP servers, subagents |
| claude-md-management | Audit CLAUDE.md quality, capture session learnings, keep project memory current |
| security-guidance | PreToolUse hook that warns about command injection, XSS, unsafe patterns |
| hookify | Create hooks to prevent unwanted behaviors by analyzing conversation patterns |
| skill-creator | Create/improve/eval skills + benchmark performance with variance analysis |
| agent-sdk-dev | Claude Agent SDK development plugin |
| playground | Creates interactive HTML playgrounds — single-file explorers with live preview |
| ralph-loop | Continuous self-referential AI loops (Ralph Wiggum technique) for iterative dev |

### Output Style Plugins (2)

| Plugin | Description |
|--------|-------------|
| explanatory-output-style | Adds educational insights about implementation choices (mimics deprecated Explanatory style) |
| learning-output-style | Interactive learning mode requesting meaningful code contributions at decision points |

### External/Third-Party Integrations (13)

| Plugin | Description |
|--------|-------------|
| github | Official GitHub MCP — issues, PRs, code review, repo search |
| gitlab | GitLab MCP — repos, merge requests, CI/CD, issues, wikis |
| context7 | Upstash Context7 — version-specific docs lookup from source repos |
| stripe | Stripe development plugin |
| supabase | Supabase MCP — DB, auth, storage, realtime |
| firebase | Google Firebase MCP — Firestore, auth, functions, hosting |
| slack | Slack workspace — search messages, channels, threads |
| linear | Linear issue tracking — issues, projects, statuses |
| asana | Asana project management — tasks, projects, assignments |
| playwright | Microsoft browser automation — screenshots, forms, E2E testing |
| greptile | AI code review agent for GitHub/GitLab PRs |
| serena | Semantic code analysis via LSP — refactoring, navigation |
| laravel-boost | Laravel dev toolkit — Artisan, Eloquent, routing, migrations |

---

## Neon pgvector Embedding Router (Architecture Proposal)

### Schema

```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgrag;  -- needs SET neon.allow_unstable_extensions='true'

CREATE TABLE tool_registry (
  id          serial PRIMARY KEY,
  kind        text NOT NULL,  -- 'tool' | 'skill' | 'plugin' | 'lsp'
  source      text NOT NULL,  -- e.g. 'claude-plugins-official/github'
  name        text NOT NULL,
  description text NOT NULL,
  schema_json jsonb,          -- tool input schema (for tool_use injection)
  embedding   vector(384),    -- bge-small-en-v1.5 = 384 dims
  enabled     boolean DEFAULT true,
  created_at  timestamptz DEFAULT now()
);

CREATE INDEX ON tool_registry USING hnsw (embedding vector_cosine_ops);
```

### Embed in-database (no external API)

```sql
-- pgrag provides rag_bge_small_en_v15.embedding_for_passage()
UPDATE tool_registry
SET embedding = rag_bge_small_en_v15.embedding_for_passage(
  name || ': ' || description
)
WHERE embedding IS NULL;
```

### Search (single SQL call)

```sql
SELECT name, description, schema_json, kind, source,
       1 - (embedding <=> rag_bge_small_en_v15.embedding_for_query($1)) AS score
FROM tool_registry
WHERE enabled = true
ORDER BY embedding <=> rag_bge_small_en_v15.embedding_for_query($1)
LIMIT 5;
```

### What gets indexed

| Kind | Source | Count | Examples |
|------|--------|-------|----------|
| tool | Built-in | 9 | Read, Write, Edit, Bash, Glob, Grep, WebSearch, WebFetch, AskUserQuestion |
| tool | MCP tools | ~50+ | mcp__neon__run_sql, mcp__github__create_issue |
| plugin | claude-plugins-official | 40 | github, stripe, context7, typescript-lsp, code-review |
| skill | Plugin skills | ~20+ | neon-drizzle, neon-auth, stripe-checkout, superpowers |
| lsp | LSP analyzers | 11 | typescript, pyright, rust-analyzer, gopls, clangd |

### Agent SDK integration

```typescript
import { query } from "@anthropic-ai/claude-agent-sdk";
import { neon } from "@neondatabase/serverless";

const sql = neon(process.env.DATABASE_URL!);

// tool_search: the only tool Claude starts with
async function toolSearch(userQuery: string) {
  const rows = await sql`
    SELECT name, description, schema_json, kind, source,
           1 - (embedding <=> rag_bge_small_en_v15.embedding_for_query(${userQuery})) AS score
    FROM tool_registry
    WHERE enabled = true
    ORDER BY embedding <=> rag_bge_small_en_v15.embedding_for_query(${userQuery})
    LIMIT 5
  `;
  return rows;
}

// Agent starts with just tool_search + base tools
for await (const message of query({
  prompt: taskDescription,
  options: {
    allowedTools: ["Read", "Glob", "Grep", "Bash", "tool_search"],
    mcpServers: {
      neon: { command: "npx", args: ["-y", "@neondatabase/mcp-server-neon"] }
    }
  }
})) {
  // tool_search results inject discovered tool definitions
  // Claude can then use them immediately
}
```

### Neon vs In-Memory comparison

| Dimension | In-memory (cookbook) | Neon pgvector |
|-----------|-------------------|---------------|
| Embedding model | Local all-MiniLM-L6-v2 (86MB download) | rag_bge_small_en_v15 (preloaded, zero setup) |
| Startup cost | Load model + embed on every session | Already indexed, instant query |
| Persistence | Rebuilt every session | Persists across sessions/agents |
| Reranking | None | rag_jina_reranker_v1_tiny_en available |
| Multi-agent | Each agent re-embeds | Shared index, all agents query same table |
| Index type | Brute-force cosine | HNSW approximate NN (sub-ms at scale) |
| Dependencies | @xenova/transformers (heavy) | @neondatabase/serverless (already installed) |
| Token counting | Separate | pg_tiktoken extension available |

### Cost

- Embedding compute: $0 (runs inside Neon, no external API)
- Storage: ~130 tools x 384 dims x 4 bytes = ~200KB (negligible)
- Query: single SQL round-trip per tool_search call (~5ms on Neon serverless)
- Agent execution: API key per-token pricing (but ~90% fewer tool-definition tokens)

---

## claude.ai/customize — Connected Services

> Scraped 2026-03-06

### Skills (Enabled)

| Skill | Description |
|-------|-------------|
| mcp-builder | Guide for creating high-quality MCP servers (Python FastMCP / Node MCP SDK) |
| skill-creator | Create/modify/eval skills, benchmark performance with variance analysis |
| web-artifacts-builder | Multi-component HTML artifacts using React, Tailwind, shadcn/ui |

### Skills (Available, Disabled)

| Skill | Description |
|-------|-------------|
| algorithmic-art | p5.js generative art with seeded randomness, interactive parameters |
| brand-guidelines | Anthropic brand colors and typography |
| canvas-design | Static visual art in .png/.pdf using design philosophy |
| doc-coauthoring | 3-stage workflow: Context Gathering, Refinement, Reader Testing |
| internal-comms | Status reports, leadership updates, 3P updates, newsletters, FAQs |
| slack-gif-creator | Animated GIFs optimized for Slack (128x128 emoji, 480x480 message) |
| theme-factory | 10 preset themes for slides, docs, reportings, HTML pages |

### Connectors

| Connector | Connected | Permission Model |
|-----------|-----------|-----------------|
| Context7 | No | Read-only: auto-allow (query-docs, resolve-library-id) |
| GitHub | Yes | — |
| Gmail | Yes | Read: auto-allow (6 tools), Write: needs-approval (Create Draft) |
| Google Calendar | Yes | Read: auto-allow (5 tools), Write: custom (4 tools) |
| Google Drive | Yes | — |
| Linear | Yes | Read: custom (21 tools) |
| Sentry | Yes | Read: custom (15 tools) |
| Slack | Yes | Interactive: auto-allow (Draft message), Read: auto-allow (8 tools), Write: needs-approval (Send, Schedule, Create canvas) |
| Vercel | Yes | Read: auto-allow (11 tools) |

### Connector Tool Counts

| Connector | Interactive | Read-only | Write | Total |
|-----------|------------|-----------|-------|-------|
| Context7 | 0 | 2 | 0 | 2 |
| Gmail | 0 | 6 | 1 | 7 |
| Google Calendar | 0 | 5 | 4 | 9 |
| Linear | 0 | 21 | 0 | 21 |
| Sentry | 0 | 15 | 0 | 15 |
| Slack | 1 | 8 | 3 | 12 |
| Vercel | 0 | 11 | 0 | 11 |
