import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  createContract,
  estimateCost,
  checkContract,
  recordUsage,
  getModelPricing,
} from '../lib/contracts.js';

describe('createContract', () => {
  it('creates contract with defaults', () => {
    const c = createContract('test-task');
    assert.equal(c.name, 'test-task');
    assert.equal(c.limits.tool_calls, 500);
    assert.equal(c.limits.input_tokens, null);
    assert.equal(c.limits.total_tokens, null);
    assert.equal(c.limits.cost_usd, null);
    assert.equal(c.limits.model, 'claude-sonnet-4-6');
    assert.equal(c.usage.tool_calls, 0);
    assert.equal(c.usage.input_tokens, 0);
    assert.equal(c.status, 'active');
    assert.ok(c.created_at);
  });

  it('accepts custom limits', () => {
    const c = createContract('big-task', {
      tool_calls: 1000,
      total_tokens: 500_000,
      cost_usd: 5.00,
      model: 'claude-opus-4-6',
    });
    assert.equal(c.limits.tool_calls, 1000);
    assert.equal(c.limits.total_tokens, 500_000);
    assert.equal(c.limits.cost_usd, 5.00);
    assert.equal(c.limits.model, 'claude-opus-4-6');
  });
});

describe('estimateCost', () => {
  it('calculates cost for sonnet', () => {
    // 1M input + 1M output = $3 + $15 = $18
    const cost = estimateCost(1_000_000, 1_000_000, 'claude-sonnet-4-6');
    assert.equal(cost, 18.0);
  });

  it('calculates cost for opus', () => {
    // 1M input + 1M output = $15 + $75 = $90
    const cost = estimateCost(1_000_000, 1_000_000, 'claude-opus-4-6');
    assert.equal(cost, 90.0);
  });

  it('calculates cost for haiku', () => {
    // 1M input + 1M output = $0.80 + $4.00 = $4.80
    const cost = estimateCost(1_000_000, 1_000_000, 'claude-haiku-4-5');
    assert.equal(cost, 4.80);
  });

  it('handles small token counts', () => {
    // 1000 input + 500 output on sonnet = $0.003 + $0.0075 = $0.0105
    const cost = estimateCost(1000, 500, 'claude-sonnet-4-6');
    assert.ok(Math.abs(cost - 0.0105) < 0.0001);
  });

  it('returns 0 for unknown model', () => {
    assert.equal(estimateCost(1000, 500, 'unknown-model'), 0);
  });

  it('batch pricing is 50% discount', () => {
    const regular = estimateCost(1_000_000, 1_000_000, 'claude-sonnet-4-6');
    const batch = estimateCost(1_000_000, 1_000_000, 'claude-sonnet-4-6:batch');
    assert.equal(batch, regular / 2);
  });
});

describe('checkContract', () => {
  it('returns no warnings when under limits', () => {
    const c = createContract('test', { tool_calls: 100 });
    c.usage.tool_calls = 50;
    const result = checkContract(c);
    assert.equal(result.exceeded, false);
    assert.equal(result.warnings.length, 0);
  });

  it('warns at 70% of tool_calls', () => {
    const c = createContract('test', { tool_calls: 100 });
    c.usage.tool_calls = 70;
    const result = checkContract(c);
    assert.equal(result.exceeded, false);
    assert.equal(result.warnings.length, 1);
    assert.match(result.warnings[0], /70\/100/);
  });

  it('exceeds when over tool_calls', () => {
    const c = createContract('test', { tool_calls: 100 });
    c.usage.tool_calls = 101;
    const result = checkContract(c);
    assert.equal(result.exceeded, true);
  });

  it('exceeds when over cost_usd', () => {
    const c = createContract('test', { cost_usd: 1.00 });
    c.usage.cost_usd = 1.01;
    const result = checkContract(c);
    assert.equal(result.exceeded, true);
    assert.match(result.warnings[0], /Cost/);
  });

  it('ignores null limits', () => {
    const c = createContract('test', {
      tool_calls: null,
      total_tokens: null,
      cost_usd: null,
    });
    c.usage.tool_calls = 99999;
    c.usage.input_tokens = 99999999;
    const result = checkContract(c);
    assert.equal(result.exceeded, false);
    assert.equal(result.warnings.length, 0);
  });

  it('checks total_tokens (input + output)', () => {
    const c = createContract('test', { total_tokens: 1000 });
    c.usage.input_tokens = 600;
    c.usage.output_tokens = 500;
    const result = checkContract(c);
    assert.equal(result.exceeded, true);
    assert.match(result.warnings[0], /1100\/1000/);
  });

  it('provides details for all dimensions', () => {
    const c = createContract('test', { tool_calls: 100, cost_usd: 5.0 });
    c.usage.tool_calls = 50;
    c.usage.cost_usd = 2.0;
    const result = checkContract(c);
    assert.equal(result.details.tool_calls.used, 50);
    assert.equal(result.details.tool_calls.limit, 100);
    assert.equal(result.details.cost_usd.used, 2.0);
    assert.equal(result.details.cost_usd.limit, 5.0);
  });
});

describe('recordUsage', () => {
  it('increments tool_calls', () => {
    const c = createContract('test', { tool_calls: 100 });
    recordUsage(c, { tool_calls: 1 });
    assert.equal(c.usage.tool_calls, 1);
    recordUsage(c, { tool_calls: 1 });
    assert.equal(c.usage.tool_calls, 2);
  });

  it('accumulates tokens', () => {
    const c = createContract('test', { total_tokens: 10000 });
    recordUsage(c, { input_tokens: 100, output_tokens: 50 });
    assert.equal(c.usage.input_tokens, 100);
    assert.equal(c.usage.output_tokens, 50);
    recordUsage(c, { input_tokens: 200, output_tokens: 100 });
    assert.equal(c.usage.input_tokens, 300);
    assert.equal(c.usage.output_tokens, 150);
  });

  it('recalculates cost after recording', () => {
    const c = createContract('test', { model: 'claude-sonnet-4-6' });
    recordUsage(c, { input_tokens: 1_000_000, output_tokens: 0 });
    // 1M input tokens on sonnet = $3.00
    assert.equal(c.usage.cost_usd, 3.0);
  });

  it('updates status to warning at 70%', () => {
    const c = createContract('test', { tool_calls: 100 });
    recordUsage(c, { tool_calls: 70 });
    assert.equal(c.status, 'warning');
  });

  it('updates status to exceeded when over', () => {
    const c = createContract('test', { tool_calls: 10 });
    recordUsage(c, { tool_calls: 11 });
    assert.equal(c.status, 'exceeded');
  });

  it('handles partial deltas', () => {
    const c = createContract('test');
    recordUsage(c, { tool_calls: 1 });
    assert.equal(c.usage.tool_calls, 1);
    assert.equal(c.usage.input_tokens, 0);
  });
});

describe('getModelPricing', () => {
  it('returns pricing table', () => {
    const pricing = getModelPricing();
    assert.ok(pricing['claude-sonnet-4-6']);
    assert.equal(pricing['claude-sonnet-4-6'].input, 3.0);
    assert.equal(pricing['claude-sonnet-4-6'].output, 15.0);
  });

  it('returns a copy (not mutable)', () => {
    const pricing = getModelPricing();
    pricing['claude-sonnet-4-6'].input = 999;
    const fresh = getModelPricing();
    assert.equal(fresh['claude-sonnet-4-6'].input, 3.0);
  });
});
