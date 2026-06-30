'use strict';
const crypto = require('crypto');

const TS_WINDOW_MS = 30 * 1000;

// Vercel sets req.body = {} for GET/DELETE with no real payload — treat that the same as no body.
function getBodyString(body) {
  if (!body) return 'empty';
  if (typeof body === 'object' && Object.keys(body).length === 0) return 'empty';
  const str = typeof body === 'string' ? body : JSON.stringify(body);
  return (str === '' || str === '{}') ? 'empty' : str;
}

function hmacHex(keyHex, message) {
  return crypto.createHmac('sha256', keyHex).update(message).digest('hex');
}

function timingSafeEqualHex(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  const bufA = Buffer.from(a, 'hex');
  const bufB = Buffer.from(b, 'hex');
  if (bufA.length !== bufB.length) return false;
  return crypto.timingSafeEqual(bufA, bufB);
}

// Verifies the HMAC signature on a request. session_token comes from the
// Authorization Bearer header for logged-in sessions, or X-Key-ID for guests.
async function verifySignedRequest(req, supabase) {
  const token = req.headers['x-request-token'];
  const ts = req.headers['x-request-ts'];
  const keyIdHeader = req.headers['x-key-id'];
  const authHeader = req.headers['authorization'] || '';
  const bearerToken = authHeader.replace(/^Bearer\s+/i, '').trim();
  const sessionToken = bearerToken || keyIdHeader;

  if (!token || !ts || !sessionToken) return { valid: false, reason: 'missing signing headers' };

  const tsNum = Number(ts);
  if (!Number.isFinite(tsNum) || Math.abs(Date.now() - tsNum) > TS_WINDOW_MS) {
    return { valid: false, reason: 'stale or invalid timestamp' };
  }

  const { data: keyRow, error: keyError } = await supabase
    .from('uwu_signing_keys')
    .select('signing_key, expires_at')
    .eq('session_token', sessionToken)
    .maybeSingle();

  if (keyError || !keyRow) return { valid: false, reason: 'signing key not found' };
  if (new Date(keyRow.expires_at) < new Date()) return { valid: false, reason: 'signing key expired' };

  const method = (req.method || 'GET').toUpperCase();
  const path = (req.url || '').split('?')[0];
  const bodyStr = getBodyString(req.body);
  const bodyHash = hmacHex(keyRow.signing_key, bodyStr);
  const message = `${ts}:${method}:${path}:${bodyHash}`;
  const expectedToken = hmacHex(keyRow.signing_key, message);

  if (!timingSafeEqualHex(expectedToken, token)) return { valid: false, reason: 'invalid signature' };

  const { data: usedRow } = await supabase
    .from('uwu_used_request_tokens')
    .select('token')
    .eq('token', token)
    .maybeSingle();
  if (usedRow) return { valid: false, reason: 'replay detected' };

  await supabase.from('uwu_used_request_tokens').insert({ token, session_token: sessionToken });

  return { valid: true, reason: 'ok' };
}

module.exports = { verifySignedRequest, getBodyString, hmacHex };
