#!/usr/bin/env node
/**
 * TeammateIdle hook — fires when a teammate is about to go idle.
 *
 * Checks the team contract. If budget remains and tasks are incomplete,
 * exits 2 with feedback to keep the teammate working.
 *
 * Exit 0 = allow idle
 * Exit 2 = send feedback to keep working (stderr message)
 */

import { readFileSync, readdirSync, existsSync } from 'fs';
import { aggregateTeamUsage } from '../lib/team-budget.js';

const chunks = [];
process.stdin.on('data', c => chunks.push(c));
process.stdin.on('end', () => {
  try {
    const input = JSON.parse(Buffer.concat(chunks).toString());
    const sessionId = input.session_id || '';

    // Check if there's an active contract
    const contractDir = '/tmp/claude-contracts';
    if (!existsSync(contractDir)) {
      process.exit(0); // No contracts, allow idle
    }

    const contractFiles = readdirSync(contractDir).filter(f => f.endsWith('.json'));
    if (contractFiles.length === 0) {
      process.exit(0);
    }

    // Check the most recent contract
    const contractPath = `${contractDir}/${contractFiles[contractFiles.length - 1]}`;
    const contract = JSON.parse(readFileSync(contractPath, 'utf-8'));

    if (contract.status === 'exceeded') {
      process.exit(0); // Budget exhausted, allow idle
    }

    const aggregate = aggregateTeamUsage();
    const remaining = (contract.limits.tool_calls || Infinity) - aggregate.total_calls;

    if (remaining > 0 && contract.status === 'active') {
      // Budget remains — nudge to keep working
      process.stderr.write(
        `Budget contract "${contract.name}" has ${remaining} tool calls remaining. ` +
        `Check for unclaimed tasks before going idle.`
      );
      process.exit(2);
    }

    process.exit(0);
  } catch {
    process.exit(0); // Fail open
  }
});
