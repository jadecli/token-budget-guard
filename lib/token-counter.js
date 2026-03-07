/**
 * Token counter — wraps @anthropic-ai/sdk countTokens endpoint.
 *
 * Falls back gracefully when ANTHROPIC_API_KEY is not set:
 * returns null instead of crashing. The guard can still
 * track tool_calls without token data.
 */

import Anthropic from '@anthropic-ai/sdk';

let _client = null;

function getClient() {
  if (_client) return _client;
  if (!process.env.ANTHROPIC_API_KEY) return null;
  _client = new Anthropic();
  return _client;
}

/**
 * Count input tokens for a message payload.
 * @param {Object} params - Same shape as messages.create() minus max_tokens
 * @param {string} params.model
 * @param {Array} params.messages
 * @param {string} [params.system]
 * @param {Array} [params.tools]
 * @returns {Promise<number|null>} input token count, or null if unavailable
 */
export async function countInputTokens(params) {
  const client = getClient();
  if (!client) return null;

  try {
    const result = await client.messages.countTokens({
      model: params.model,
      messages: params.messages,
      ...(params.system && { system: params.system }),
      ...(params.tools && { tools: params.tools }),
    });
    return result.input_tokens;
  } catch {
    return null;
  }
}

/**
 * Extract usage from a messages.create() response.
 * @param {Object} response - API response with usage field
 * @returns {{ input_tokens: number, output_tokens: number } | null}
 */
export function extractUsage(response) {
  if (!response?.usage) return null;
  return {
    input_tokens: response.usage.input_tokens ?? 0,
    output_tokens: response.usage.output_tokens ?? 0,
  };
}

/**
 * Check if the token counter is available (API key is set).
 */
export function isAvailable() {
  return !!process.env.ANTHROPIC_API_KEY;
}
