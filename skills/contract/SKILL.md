# /token-budget-guard:contract

Create or view a budget contract for the current task.

## Instructions

A contract is a definition of done with token and/or cost limits. It replaces the flat session-wide budget with task-specific budgets.

### Create a contract

When the user says "set a budget of X for this task", create a contract:

```bash
node -e "
import { createContract } from '$(dirname "$0")/../../lib/contracts.js';
import { writeFileSync, mkdirSync } from 'fs';

const contract = createContract('$(echo "$1" | sed "s/'/\\\\'/g")', {
  tool_calls: ${TOOL_CALLS:-500},
  total_tokens: ${TOTAL_TOKENS:-null},
  cost_usd: ${COST_USD:-null},
  model: '${MODEL:-claude-sonnet-4-6}'
});

mkdirSync('/tmp/claude-contracts', { recursive: true });
const file = '/tmp/claude-contracts/' + contract.name.replace(/[^a-z0-9]/gi, '-').toLowerCase() + '.json';
writeFileSync(file, JSON.stringify(contract, null, 2));
console.log('Contract created:', file);
console.log(JSON.stringify(contract, null, 2));
"
```

### View contracts

```bash
for f in /tmp/claude-contracts/*.json; do
  if [[ -f "$f" ]]; then
    echo "=== $(basename "$f") ==="
    node -e "
      import { readFileSync } from 'fs';
      import { checkContract } from '$(dirname "$0")/../../lib/contracts.js';
      const c = JSON.parse(readFileSync('$f'));
      const check = checkContract(c);
      console.log(JSON.stringify({
        name: c.name,
        status: c.status,
        usage: c.usage,
        limits: c.limits,
        exceeded: check.exceeded,
        warnings: check.warnings
      }, null, 2));
    "
  fi
done
```

### Contract presets

| Preset | tool_calls | total_tokens | cost_usd | Use case |
|--------|-----------|-------------|----------|----------|
| quick  | 50        | 100,000     | $0.50    | Small bug fix, config change |
| medium | 200       | 500,000     | $2.00    | Feature implementation |
| large  | 500       | 2,000,000   | $10.00   | Multi-file refactor |
| unlimited | null   | null        | null     | No limits (tracking only) |
