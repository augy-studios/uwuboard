// Limits for the public endpoints that anyone can call without an account (api/bug-report.js).
//
// rateLimited(key, limit): more than `limit` calls with `key` in a minute, counted in this
// instance's memory. Vercel runs several instances and starts new ones, so it's a nicety that
// stops a burst, not a promise.
//
// With Redis set up (Vercel KV or Upstash: KV_REST_API_URL and KV_REST_API_TOKEN, or
// UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN), redis() runs one command on it, for
// limits that hold across instances. Without it, storeConfigured() is false and callers skip it.

// Vercel KV's names are used when they are set (not empty), otherwise Upstash's.
let REDIS_URL = process.env.KV_REST_API_URL;
if (!REDIS_URL) {
  REDIS_URL = process.env.UPSTASH_REDIS_REST_URL;
}
let REDIS_TOKEN = process.env.KV_REST_API_TOKEN;
if (!REDIS_TOKEN) {
  REDIS_TOKEN = process.env.UPSTASH_REDIS_REST_TOKEN;
}

const storeConfigured = () => {
  return Boolean(REDIS_URL && REDIS_TOKEN);
};

// Runs one Redis command through the REST API, e.g. redis('INCR', 'some-key'), and returns its result.

async function redis(...command) {
  const response = await fetch(REDIS_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${REDIS_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(command),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) {
    throw new Error(`Redis replied ${response.status}`);
  }
  const data = await response.json();
  if (data.error) {
    throw new Error(data.error);
  }
  return data.result;
}

const rates = new Map();

async function rateLimited(key, limit) {
  const now = Date.now();
  let rate = rates.get(key);
  if (!rate || rate.until <= now) {
    rate = { count: 0, until: now + 60 * 1000 };
    rates.set(key, rate);
  }
  rate.count = rate.count + 1;
  // Keep the map small: the ones whose minute is over go.
  if (rates.size > 5000) {
    for (const [rateKey, rateValue] of rates) {
      if (rateValue.until <= now) {
        rates.delete(rateKey);
      }
    }
  }
  return rate.count > limit;
}

module.exports = { storeConfigured, redis, rateLimited };
