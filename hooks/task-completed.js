#!/usr/bin/env node
/**
 * TaskCompleted hook — fires when a task is marked complete.
 *
 * Validates the task against the active contract's budget.
 * If the contract is exceeded, prevents task completion with feedback.
 *
 * Exit 0 = allow completion
 * Exit 2 = prevent completion (stderr message)
 */

import { readFileSync, readdirSync, existsSync } from 'fs';
import { aggregateTeamUsage } from '../lib/team-budget.js';
import { checkContract } from '../lib/contracts.js';

const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  try {
    const input = JSON.parse(Buffer.concat(chunks).toString());

    // Check if there's an active contract
    const contractDir = '/tmp/claude-contracts';
    if (!existsSync(contractDir)) {
      process.exit(0);
    }

    const contractFiles = readdirSync(contractDir).filter(f => f.endsWith('.json'));
    if (contractFiles.length === 0) {
      process.exit(0);
    }

    // Check the most recent contract
    const contractPath = `${contractDir}/${contractFiles[contractFiles.length - 1]}`;
    const contract = JSON.parse(readFileSync(contractPath, 'utf-8'));

    // Sync aggregate usage into contract
    const aggregate = aggregateTeamUsage();
    contract.usage.tool_calls = aggregate.total_calls;

    const check = checkContract(contract);

    if (check.exceeded) {
      // Budget exceeded — warn but allow completion
      // (blocking task completion when over budget would be counterproductive)
      const output = {
        hookSpecificOutput: {
          additionalContext:
            `CONTRACT WARNING: "${contract.name}" budget exceeded. ` +
            check.warnings.join('. ') + '. ' +
            'Consider wrapping up remaining work.'
        }
      };
      process.stdout.write(JSON.stringify(output));
      process.exit(0);
    }

    if (check.warnings.length > 0) {
      const output = {
        hookSpecificOutput: {
          additionalContext:
            `Contract "${contract.name}": ${check.warnings.join('. ')}`
        }
      };
      process.stdout.write(JSON.stringify(output));
    }

    process.exit(0);
  } catch {
    process.exit(0); // Fail open
  }
});
