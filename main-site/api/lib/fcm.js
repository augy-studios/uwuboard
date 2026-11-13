// Pushes to the Android app through Firebase Cloud Messaging's HTTP v1 API, for "a new version
// is out" (api/push/release.js), to a topic the app joins when "New versions of the app" is on
// in its Updates page (flutter/FIREBASE-SETUP.md).
//
// FIREBASE_SERVICE_ACCOUNT holds the service account's JSON key, as downloaded or base64'd. An
// OAuth token is made from it here with node:crypto, so there's no Google library, and kept
// until just before it runs out (an hour).

const { createSign } = require('crypto');

const TOKEN_URL = 'https://oauth2.googleapis.com/token';
const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const TOKEN_MARGIN_S = 300;

let account;
let token = null;
let tokenExpires = 0;

function serviceAccount() {
  if (account !== undefined) return account;
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT?.trim();
  account = null;
  if (!raw) return account;
  try {
    const json = raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8');
    const parsed = JSON.parse(json);
    if (parsed.project_id && parsed.client_email && parsed.private_key) account = parsed;
    else console.error('[fcm] FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key');
  } catch {
    console.error('[fcm] FIREBASE_SERVICE_ACCOUNT is not the service account JSON key');
  }
  return account;
}

const fcmConfigured = () => Boolean(serviceAccount());

const b64url = (v) => Buffer.from(typeof v === 'string' ? v : JSON.stringify(v)).toString('base64url');

async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (token && now < tokenExpires - TOKEN_MARGIN_S) return token;
  const sa = serviceAccount();
  const unsigned = `${b64url({ alg: 'RS256', typ: 'JWT' })}.${b64url({
    iss: sa.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600,
  })}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(sa.private_key).toString('base64url');
  const r = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
    cache: 'no-store',
  });
  const data = await r.json().catch(() => null);
  if (!r.ok || !data?.access_token) throw new Error(`Google token responded ${r.status}: ${data?.error_description || data?.error || ''}`);
  token = data.access_token;
  tokenExpires = now + (Number(data.expires_in) || 3600);
  return token;
}

class PushError extends Error {
  constructor(statusCode, body) {
    super(`FCM responded ${statusCode}`);
    this.statusCode = statusCode;
    this.body = body;
  }
}

async function post(message) {
  const send = async () => fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`, {
    method: 'POST',
    headers: { authorization: `Bearer ${await accessToken()}`, 'content-type': 'application/json' },
    body: JSON.stringify({ message }),
    cache: 'no-store',
  });
  let r = await send();
  // A token Google took back early: once more with a fresh one.
  if (r.status === 401) {
    token = null;
    r = await send();
  }
  if (r.ok) return;
  throw new PushError(r.status, await r.json().catch(() => null));
}

// To every phone that joined a topic. Topics are shared by every app in the UwU Apps Firebase
// project, hence the uwuboard- prefix on each. The notification goes on the app's own channel
// (Notifications.java); tapping it opens the Updates page (click_action, AndroidManifest.xml).
async function sendToTopic(topic, { title, body = '', data = {}, channel, tag, ttl = 24 * 3600 }) {
  if (!fcmConfigured()) throw new PushError(503, 'FIREBASE_SERVICE_ACCOUNT is not set');
  const strings = {};
  for (const [k, v] of Object.entries({ ...data, title, body })) if (v != null) strings[k] = String(v);
  await post({
    topic,
    data: strings,
    notification: { title, body },
    android: {
      // Not urgent: a phone dozing gets it when it next wakes, within the day.
      priority: 'NORMAL',
      ttl: `${ttl}s`,
      notification: {
        channel_id: channel,
        tag,
        icon: 'ic_notification',
        visibility: 'PUBLIC',
        click_action: 'org.uwuapps.board.OPEN_UPDATES',
      },
    },
  });
}

module.exports = { sendToTopic, fcmConfigured };
