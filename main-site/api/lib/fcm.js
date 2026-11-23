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
const TOKEN_MARGIN_SECONDS = 300;

let account;
let token = null;
let tokenExpires = 0;

// The service account key from FIREBASE_SERVICE_ACCOUNT, read once and remembered. It is null
// when the variable is missing or isn't a usable key (the reason is logged once).
function serviceAccount() {
  if (account !== undefined) {
    return account;
  }
  let raw;
  const environmentValue = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (environmentValue !== null && environmentValue !== undefined) {
    raw = environmentValue.trim();
  }
  account = null;
  if (!raw) {
    return account;
  }
  try {
    // The key may be pasted as JSON as it is, or base64'd.
    let json;
    if (raw.startsWith('{')) {
      json = raw;
    } else {
      json = Buffer.from(raw, 'base64').toString('utf8');
    }
    const parsed = JSON.parse(json);
    if (parsed.project_id && parsed.client_email && parsed.private_key) {
      account = parsed;
    } else {
      console.error('[fcm] FIREBASE_SERVICE_ACCOUNT is missing project_id, client_email or private_key');
    }
  } catch {
    console.error('[fcm] FIREBASE_SERVICE_ACCOUNT is not the service account JSON key');
  }
  return account;
}

const fcmConfigured = () => {
  return Boolean(serviceAccount());
};

// A string, or an object as JSON, in the URL-safe base64 that a JWT is made of.
const base64UrlEncode = (value) => {
  let text;
  if (typeof value === 'string') {
    text = value;
  } else {
    text = JSON.stringify(value);
  }
  return Buffer.from(text).toString('base64url');
};

// A Google OAuth access token for sending pushes. The same one is reused until a few minutes
// before it runs out; then a new one is asked for with a JWT signed by the service account key.
async function accessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (token && now < tokenExpires - TOKEN_MARGIN_SECONDS) {
    return token;
  }
  const serviceAccountKey = serviceAccount();
  const unsigned = `${base64UrlEncode({ alg: 'RS256', typ: 'JWT' })}.${base64UrlEncode({
    iss: serviceAccountKey.client_email, scope: SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600,
  })}`;
  const signature = createSign('RSA-SHA256').update(unsigned).sign(serviceAccountKey.private_key).toString('base64url');
  const response = await fetch(TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion: `${unsigned}.${signature}` }),
    cache: 'no-store',
  });
  const data = await response.json().catch(() => {
    return null;
  });
  let hasAccessToken = false;
  if (data !== null && data !== undefined && data.access_token) {
    hasAccessToken = true;
  }
  if (!response.ok || !hasAccessToken) {
    // The best reason Google gave: its description, else its error code, else nothing.
    let reason = '';
    if (data !== null && data !== undefined) {
      if (data.error_description) {
        reason = data.error_description;
      } else if (data.error) {
        reason = data.error;
      }
    }
    throw new Error(`Google token responded ${response.status}: ${reason}`);
  }
  token = data.access_token;
  let lifetimeSeconds = Number(data.expires_in);
  if (!lifetimeSeconds) {
    lifetimeSeconds = 3600;
  }
  tokenExpires = now + lifetimeSeconds;
  return token;
}

class PushError extends Error {
  constructor(statusCode, body) {
    super(`FCM responded ${statusCode}`);
    this.statusCode = statusCode;
    this.body = body;
  }
}

// Sends one message through FCM, and throws a PushError if Google refuses it.
async function post(message) {
  const send = async () => {
    return fetch(`https://fcm.googleapis.com/v1/projects/${serviceAccount().project_id}/messages:send`, {
      method: 'POST',
      headers: { authorization: `Bearer ${await accessToken()}`, 'content-type': 'application/json' },
      body: JSON.stringify({ message }),
      cache: 'no-store',
    });
  };
  let response = await send();
  // A token Google took back early: once more with a fresh one.
  if (response.status === 401) {
    token = null;
    response = await send();
  }
  if (response.ok) {
    return;
  }
  throw new PushError(response.status, await response.json().catch(() => {
    return null;
  }));
}

// To every phone that joined a topic. Topics are shared by every app in the UwU Apps Firebase
// project, hence the uwuboard- prefix on each. The notification goes on the app's own channel
// (Notifications.java); tapping it opens the Updates page (click_action, AndroidManifest.xml).
async function sendToTopic(topic, { title, body = '', data = {}, channel, tag, ttl: timeToLiveSeconds = 24 * 3600 }) {
  if (!fcmConfigured()) {
    throw new PushError(503, 'FIREBASE_SERVICE_ACCOUNT is not set');
  }
  // FCM's data payload only takes strings, and leaves out empty values.
  const strings = {};
  for (const [key, value] of Object.entries({ ...data, title, body })) {
    if (value !== null && value !== undefined) {
      strings[key] = String(value);
    }
  }
  await post({
    topic,
    data: strings,
    notification: { title, body },
    android: {
      // Not urgent: a phone dozing gets it when it next wakes, within the day.
      priority: 'NORMAL',
      ttl: `${timeToLiveSeconds}s`,
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
