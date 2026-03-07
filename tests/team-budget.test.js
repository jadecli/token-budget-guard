import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync, mkdirSync, rmSync, existsSync } from 'fs';
import { join } from 'path';
import { createContract } from '../lib/contracts.js';
import { checkTeamContract } from '../lib/team-budget.js';

describe('checkTeamContract', () => {
  it('marks contract exceeded when aggregate calls exceed limit', () => {
    const contract = createContract('team-task', { tool_calls: 100 });
    const result = checkTeamContract(contract, {
      total_calls: 150,
      sessions: 3,
    });
    assert.equal(result.exceeded, true);
    assert.equal(result.aggregate.total_calls, 150);
    assert.equal(result.aggregate.sessions, 3);
  });

  it('passes when aggregate calls under limit', () => {
    const contract = createContract('team-task', { tool_calls: 500 });
    const result = checkTeamContract(contract, {
      total_calls: 200,
      sessions: 4,
    });
    assert.equal(result.exceeded, false);
  });

  it('warns at 70% of limit', () => {
    const contract = createContract('team-task', { tool_calls: 100 });
    const result = checkTeamContract(contract, {
      total_calls: 75,
      sessions: 3,
    });
    assert.equal(result.exceeded, false);
    assert.ok(result.warnings.length > 0);
    assert.match(result.warnings[0], /75\/100/);
  });

  it('syncs aggregate tool calls into contract usage', () => {
    const contract = createContract('team-task', { tool_calls: 100 });
    checkTeamContract(contract, { total_calls: 42, sessions: 2 });
    assert.equal(contract.usage.tool_calls, 42);
  });

  it('handles null tool_calls limit (no enforcement)', () => {
    const contract = createContract('unlimited', { tool_calls: null });
    const result = checkTeamContract(contract, {
      total_calls: 99999,
      sessions: 10,
    });
    assert.equal(result.exceeded, false);
    assert.equal(result.warnings.length, 0);
  });
});

describe('TeammateIdle hook', () => {
  const contractDir = '/tmp/claude-contracts';
  const contractFile = join(contractDir, 'test-idle.json');

  beforeEach(() => {
    mkdirSync(contractDir, { recursive: true });
  });

  afterEach(() => {
    if (existsSync(contractFile)) rmSync(contractFile);
  });

  it('exits 0 when no contracts exist', async () => {
    if (existsSync(contractFile)) rmSync(contractFile);
    const { execSync } = await import('child_process');
    try {
      execSync(
        'echo \'{"session_id":"test"}\' | node hooks/teammate-idle.js',
        { cwd: process.cwd(), stdio: 'pipe' }
      );
    } catch (e) {
      // Should not throw (exit 0)
      assert.fail(`Hook exited with non-zero: ${e.status}`);
    }
  });

  it('exits 2 when budget remains on active contract', async () => {
    const contract = createContract('test-idle-task', { tool_calls: 1000 });
    writeFileSync(contractFile, JSON.stringify(contract));

    const { execSync } = await import('child_process');
    try {
      execSync(
        'echo \'{"session_id":"test"}\' | node hooks/teammate-idle.js',
        { cwd: process.cwd(), stdio: 'pipe' }
      );
      assert.fail('Expected exit 2');
    } catch (e) {
      assert.equal(e.status, 2);
      assert.match(e.stderr.toString(), /tool calls remaining/);
    }
  });

  it('exits 0 when contract is exceeded', async () => {
    const contract = createContract('test-idle-exceeded', { tool_calls: 10 });
    contract.status = 'exceeded';
    writeFileSync(contractFile, JSON.stringify(contract));

    const { execSync } = await import('child_process');
    try {
      execSync(
        'echo \'{"session_id":"test"}\' | node hooks/teammate-idle.js',
        { cwd: process.cwd(), stdio: 'pipe' }
      );
    } catch (e) {
      assert.fail(`Hook should exit 0 when exceeded, got: ${e.status}`);
    }
  });
});

describe('TaskCompleted hook', () => {
  const contractDir = '/tmp/claude-contracts';
  const contractFile = join(contractDir, 'test-complete.json');

  beforeEach(() => {
    mkdirSync(contractDir, { recursive: true });
  });

  afterEach(() => {
    if (existsSync(contractFile)) rmSync(contractFile);
  });

  it('exits 0 when no contracts exist', async () => {
    if (existsSync(contractFile)) rmSync(contractFile);
    const { execSync } = await import('child_process');
    try {
      execSync(
        'echo \'{"session_id":"test"}\' | node hooks/task-completed.js',
        { cwd: process.cwd(), stdio: 'pipe' }
      );
    } catch (e) {
      assert.fail(`Hook exited with non-zero: ${e.status}`);
    }
  });

  it('exits 0 with warning when contract has warnings', async () => {
    const contract = createContract('test-warn', { tool_calls: 100 });
    contract.usage.tool_calls = 75;
    writeFileSync(contractFile, JSON.stringify(contract));

    const { execSync } = await import('child_process');
    const result = execSync(
      'echo \'{"session_id":"test"}\' | node hooks/task-completed.js',
      { cwd: process.cwd(), stdio: 'pipe' }
    );
    const output = result.toString();
    if (output) {
      const parsed = JSON.parse(output);
      assert.ok(parsed.hookSpecificOutput.additionalContext);
    }
  });
});
