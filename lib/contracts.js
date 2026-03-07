/**
 * Contracts — definitions of done with token and/or cost budgets.
 *
 * A contract defines a task's budget in three dimensions:
 *   - tool_calls: max number of tool invocations (legacy, always enforced)
 *   - tokens: max input+output tokens (requires SDK, estimated via countTokens)
 *   - cost_usd: max estimated cost in USD (derived from tokens + model pricing)
 *
 * Contracts are stored as JSON files in .claude/contracts/ and referenced
 * by the budget guard hook to enforce limits per-task instead of per-session.
 */

// Model pricing (per million tokens) — must be updated manually.
// Source: https://docs.anthropic.com/en/docs/about-claude/pricing
const MODEL_PRICING = {
  'claude-haiku-4-5': { input: 0.80, output: 4.00 },
  'claude-haiku-4-5-20251001': { input: 0.80, output: 4.00 },
  'claude-sonnet-4-6': { input: 3.00, output: 15.00 },
  'claude-opus-4-6': { input: 15.00, output: 75.00 },
  // Batch API: 50% discount
  'claude-sonnet-4-6:batch': { input: 1.50, output: 7.50 },
  'claude-opus-4-6:batch': { input: 7.50, output: 37.50 },
};

/**
 * @typedef {Object} Contract
 * @property {string} name - Human-readable contract name
 * @property {string} [description] - What this contract covers
 * @property {Object} limits
 * @property {number} [limits.tool_calls] - Max tool invocations
 * @property {number} [limits.input_tokens] - Max input tokens
 * @property {number} [limits.output_tokens] - Max output tokens
 * @property {number} [limits.total_tokens] - Max input+output tokens
 * @property {number} [limits.cost_usd] - Max estimated cost in USD
 * @property {string} [limits.model] - Model to use for cost estimation
 * @property {Object} usage - Current usage (mutated by guard)
 * @property {number} usage.tool_calls
 * @property {number} usage.input_tokens
 * @property {number} usage.output_tokens
 * @property {number} usage.cost_usd
 * @property {string} status - 'active' | 'warning' | 'exceeded'
 * @property {string} created_at - ISO timestamp
 */

/**
 * Create a new contract with the given limits.
 * @param {string} name
 * @param {Object} limits
 * @returns {Contract}
 */
export function createContract(name, limits = {}) {
  return {
    name,
    limits: {
      tool_calls: 'tool_calls' in limits ? limits.tool_calls : 500,
      input_tokens: limits.input_tokens ?? null,
      output_tokens: limits.output_tokens ?? null,
      total_tokens: limits.total_tokens ?? null,
      cost_usd: limits.cost_usd ?? null,
      model: limits.model ?? 'claude-sonnet-4-6',
    },
    usage: {
      tool_calls: 0,
      input_tokens: 0,
      output_tokens: 0,
      cost_usd: 0,
    },
    status: 'active',
    created_at: new Date().toISOString(),
  };
}

/**
 * Estimate cost from token counts and model.
 * @param {number} inputTokens
 * @param {number} outputTokens
 * @param {string} model
 * @returns {number} cost in USD
 */
export function estimateCost(inputTokens, outputTokens, model) {
  const pricing = MODEL_PRICING[model];
  if (!pricing) return 0;
  return (inputTokens * pricing.input + outputTokens * pricing.output) / 1_000_000;
}

/**
 * Check a contract against its limits. Returns the check result.
 * @param {Contract} contract
 * @returns {{ exceeded: boolean, warnings: string[], details: Object }}
 */
export function checkContract(contract) {
  const { limits, usage } = contract;
  const warnings = [];
  let exceeded = false;

  // Tool calls
  if (limits.tool_calls != null && usage.tool_calls > limits.tool_calls) {
    exceeded = true;
    warnings.push(`Tool calls: ${usage.tool_calls}/${limits.tool_calls}`);
  } else if (limits.tool_calls != null && usage.tool_calls >= limits.tool_calls * 0.7) {
    warnings.push(`Tool calls: ${usage.tool_calls}/${limits.tool_calls} (${Math.round(usage.tool_calls / limits.tool_calls * 100)}%)`);
  }

  // Input tokens
  if (limits.input_tokens != null && usage.input_tokens > limits.input_tokens) {
    exceeded = true;
    warnings.push(`Input tokens: ${usage.input_tokens}/${limits.input_tokens}`);
  }

  // Output tokens
  if (limits.output_tokens != null && usage.output_tokens > limits.output_tokens) {
    exceeded = true;
    warnings.push(`Output tokens: ${usage.output_tokens}/${limits.output_tokens}`);
  }

  // Total tokens
  const totalTokens = usage.input_tokens + usage.output_tokens;
  if (limits.total_tokens != null && totalTokens > limits.total_tokens) {
    exceeded = true;
    warnings.push(`Total tokens: ${totalTokens}/${limits.total_tokens}`);
  } else if (limits.total_tokens != null && totalTokens >= limits.total_tokens * 0.7) {
    warnings.push(`Total tokens: ${totalTokens}/${limits.total_tokens} (${Math.round(totalTokens / limits.total_tokens * 100)}%)`);
  }

  // Cost
  if (limits.cost_usd != null && usage.cost_usd > limits.cost_usd) {
    exceeded = true;
    warnings.push(`Cost: $${usage.cost_usd.toFixed(4)}/$${limits.cost_usd.toFixed(2)}`);
  } else if (limits.cost_usd != null && usage.cost_usd >= limits.cost_usd * 0.7) {
    warnings.push(`Cost: $${usage.cost_usd.toFixed(4)}/$${limits.cost_usd.toFixed(2)} (${Math.round(usage.cost_usd / limits.cost_usd * 100)}%)`);
  }

  return {
    exceeded,
    warnings,
    details: {
      tool_calls: { used: usage.tool_calls, limit: limits.tool_calls },
      input_tokens: { used: usage.input_tokens, limit: limits.input_tokens },
      output_tokens: { used: usage.output_tokens, limit: limits.output_tokens },
      total_tokens: { used: totalTokens, limit: limits.total_tokens },
      cost_usd: { used: usage.cost_usd, limit: limits.cost_usd },
    },
  };
}

/**
 * Record usage against a contract. Mutates the contract.
 * @param {Contract} contract
 * @param {{ tool_calls?: number, input_tokens?: number, output_tokens?: number }} delta
 * @returns {Contract}
 */
export function recordUsage(contract, delta) {
  if (delta.tool_calls) contract.usage.tool_calls += delta.tool_calls;
  if (delta.input_tokens) contract.usage.input_tokens += delta.input_tokens;
  if (delta.output_tokens) contract.usage.output_tokens += delta.output_tokens;

  // Recalculate cost
  contract.usage.cost_usd = estimateCost(
    contract.usage.input_tokens,
    contract.usage.output_tokens,
    contract.limits.model,
  );

  // Update status
  const check = checkContract(contract);
  contract.status = check.exceeded ? 'exceeded' : check.warnings.length > 0 ? 'warning' : 'active';

  return contract;
}

/**
 * Get the pricing table. Useful for status display.
 */
export function getModelPricing() {
  return JSON.parse(JSON.stringify(MODEL_PRICING));
}
