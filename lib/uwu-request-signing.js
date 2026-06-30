'use strict';

const SK_STORAGE_KEY = 'uwu_signing_key';
const SK_STORAGE_ID = 'uwu_signing_key_id';

function storeSigningKey(signingKey, keyId) {
  sessionStorage.setItem(SK_STORAGE_KEY, signingKey);
  sessionStorage.setItem(SK_STORAGE_ID, keyId);
}

function clearSigningKey() {
  sessionStorage.removeItem(SK_STORAGE_KEY);
  sessionStorage.removeItem(SK_STORAGE_ID);
}

// For persistent ("remember me") sessions: the session token survives in localStorage
// across tabs/restarts, but sessionStorage (and thus the signing key) does not. Call this
// on boot when a saved session exists — it exchanges the still-valid session token for a
// fresh signing key via /api/auth/refresh-key. No-ops if a key is already stored.
async function restoreSigningKeyForSession(sessionToken) {
  if (sessionStorage.getItem(SK_STORAGE_KEY)) return;
  const res = await fetch('/api/auth/refresh-key', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${sessionToken}` },
  });
  if (!res.ok) throw new Error('Failed to refresh signing key');
  const data = await res.json();
  storeSigningKey(data.signing_key, data.key_id);
}

// Fetches a short-lived guest signing key for anonymous visitors. No-ops if a key is already stored.
async function initGuestKey(appId) {
  if (sessionStorage.getItem(SK_STORAGE_KEY)) return;
  const res = await fetch(`/api/auth/guest-key?app=${encodeURIComponent(appId)}`);
  if (!res.ok) throw new Error('Failed to obtain guest signing key');
  const data = await res.json();
  storeSigningKey(data.signing_key, data.key_id);
}

// Must match getBodyString() in uwu-request-signing-server.js exactly.
function getBodyString(body) {
  if (!body) return 'empty';
  const str = typeof body === 'string' ? body : JSON.stringify(body);
  return (str === '' || str === '{}') ? 'empty' : str;
}

async function hmacHex(keyHex, message) {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    'raw', enc.encode(keyHex), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', cryptoKey, enc.encode(message));
  return Array.from(new Uint8Array(sig)).map(b => b.toString(16).padStart(2, '0')).join('');
}

// Drop-in replacement for fetch() that signs the request. Throws if no signing key is stored —
// never silently falls back to an unsigned fetch.
async function signedFetch(url, options = {}) {
  const signingKey = sessionStorage.getItem(SK_STORAGE_KEY);
  const keyId = sessionStorage.getItem(SK_STORAGE_ID);
  if (!signingKey || !keyId) {
    throw new Error('signedFetch: no signing key present — call storeSigningKey() or initGuestKey() first');
  }

  const method = (options.method || 'GET').toUpperCase();
  const path = new URL(url, location.origin).pathname;
  const ts = Date.now().toString();

  const bodyStr = getBodyString(options.body);
  const bodyHash = await hmacHex(signingKey, bodyStr);
  const message = `${ts}:${method}:${path}:${bodyHash}`;
  const token = await hmacHex(signingKey, message);

  const headers = new Headers(options.headers || {});
  headers.set('X-Request-Token', token);
  headers.set('X-Request-TS', ts);
  headers.set('X-Key-ID', keyId);

  return fetch(url, { ...options, headers });
}
