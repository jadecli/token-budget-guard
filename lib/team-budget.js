/**
 * Team budget — aggregates budget state across agent team members.
 *
 * Each teammate runs its own PreToolUse budget guard (budget-guard.sh),
 * which creates per-session state files at /tmp/claude-budget-guard-{session_id}.json.
 *
 * This module:
 *   1. Discovers team members from ~/.claude/teams/{team}/config.json
 *   2. Reads each member's budget state file
 *   3. Aggregates usage into a team-wide view
 *   4. Checks team contracts for budget compliance
 */

import { readFileSync, readdirSync, existsSync } from 'fs';
import { join } from 'path';
import { checkContract } from './contracts.js';

const TEAMS_DIR = join(process.env.HOME || '', '.claude', 'teams');
const STATE_DIR = '/tmp';

/**
 * Discover active teams.
 * @returns {string[]} team names
 */
export function listTeams() {
  if (!existsSync(TEAMS_DIR)) return [];
  try {
    return readdirSync(TEAMS_DIR, { withFileTypes: true })
      .filter(d => d.isDirectory())
      .map(d => d.name);
  } catch {
    return [];
  }
}

/**
 * Read team config for a given team name.
 * @param {string} teamName
 * @returns {{ members: Array<{ name: string, agentId: string, agentType: string }> } | null}
 */
export function getTeamConfig(teamName) {
  const configPath = join(TEAMS_DIR, teamName, 'config.json');
  if (!existsSync(configPath)) return null;
  try {
    return JSON.parse(readFileSync(configPath, 'utf-8'));
  } catch {
    return null;
  }
}

/**
 * Read a teammate's budget guard state file.
 * @param {string} sessionId
 * @returns {Object|null} parsed state or null
 */
export function getTeammateState(sessionId) {
  const stateFile = join(STATE_DIR, `claude-budget-guard-${sessionId}.json`);
  if (!existsSync(stateFile)) return null;
  try {
    return JSON.parse(readFileSync(stateFile, 'utf-8'));
  } catch {
    return null;
  }
}

/**
 * Find all budget guard state files (for when team config isn't available).
 * @returns {Array<{ sessionId: string, state: Object }>}
 */
export function getAllBudgetStates() {
  try {
    const files = readdirSync(STATE_DIR)
      .filter(f => f.startsWith('claude-budget-guard-') && f.endsWith('.json'));
    return files.map(f => {
      const sessionId = f.replace('claude-budget-guard-', '').replace('.json', '');
      try {
        const state = JSON.parse(readFileSync(join(STATE_DIR, f), 'utf-8'));
        return { sessionId, state };
      } catch {
        return null;
      }
    }).filter(Boolean);
  } catch {
    return [];
  }
}

/**
 * Aggregate budget usage across all active sessions.
 * @returns {{ total_calls: number, sessions: number, per_session: Object[] }}
 */
export function aggregateTeamUsage() {
  const states = getAllBudgetStates();
  let totalCalls = 0;
  const perSession = [];

  for (const { sessionId, state } of states) {
    totalCalls += state.count || 0;
    perSession.push({
      sessionId,
      count: state.count || 0,
      limit: state.limit || 0,
      history_size: (state.history || []).length,
      started: state.started || null,
    });
  }

  return {
    total_calls: totalCalls,
    sessions: states.length,
    per_session: perSession,
  };
}

/**
 * Check if a team contract is exceeded based on aggregate usage.
 * @param {import('./contracts.js').Contract} contract
 * @param {Object} [aggregateOverride] - override aggregate data (for testing)
 * @returns {{ exceeded: boolean, warnings: string[], aggregate: Object }}
 */
export function checkTeamContract(contract, aggregateOverride) {
  const aggregate = aggregateOverride || aggregateTeamUsage();

  // Sync aggregate tool calls into contract usage
  contract.usage.tool_calls = aggregate.total_calls;

  const check = checkContract(contract);
  return {
    ...check,
    aggregate: {
      total_calls: aggregate.total_calls,
      sessions: aggregate.sessions,
    },
  };
}
