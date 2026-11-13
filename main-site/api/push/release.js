// POST /api/push/release: a new version of the apps is out.
//
// GitHub calls this for the repository's releases (a webhook, flutter/FIREBASE-SETUP.md), and
// it pushes "uwuBoard 1.0.1 is out" to the uwuboard-releases FCM topic, which the Android app
// joins when "New versions of the app" is on in its Updates page. Tapping it opens that page.
//
// GitHub signs each delivery with GITHUB_WEBHOOK_SECRET, checked here against the body exactly
// as sent before anything is sent, so nobody else can make every phone buzz. Only "released"
// counts: a release published, or a pre-release made a full one. Drafts, pre-releases, other
// tags, releases without their APK, and a version older than the newest already out are
// answered with why, and nothing is sent.

const { createHmac, timingSafeEqual } = require('crypto');
const { sendToTopic } = require('../lib/fcm');
const { asRelease, latestRelease, newer } = require('../lib/releases');

const TOPIC = 'uwuboard-releases';

function signedByGitHub(body, signature) {
  const secret = process.env.GITHUB_WEBHOOK_SECRET;
  if (!secret || typeof signature !== 'string' || !signature.startsWith('sha256=')) return false;
  const expected = Buffer.from(`sha256=${createHmac('sha256', secret).update(body).digest('hex')}`);
  const given = Buffer.from(signature);
  return expected.length === given.length && timingSafeEqual(expected, given);
}

// The body exactly as GitHub sent it: the signature is over these bytes.
async function rawBody(req) {
  if (Buffer.isBuffer(req.body)) return req.body;
  if (typeof req.body === 'string') return Buffer.from(req.body);
  const chunks = [];
  for await (const chunk of req) chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  return Buffer.concat(chunks);
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  const body = await rawBody(req);
  if (!signedByGitHub(body, req.headers['x-hub-signature-256'])) return res.status(401).json({ error: 'Bad signature' });

  const event = req.headers['x-github-event'];
  // GitHub's hello when the webhook is first saved.
  if (event === 'ping') return res.status(200).json({ ok: true, pong: true });
  if (event !== 'release') return res.status(200).json({ sent: false, why: `Not a release event (${event})` });

  let payload;
  try {
    payload = JSON.parse(body.toString('utf8'));
  } catch {
    return res.status(400).json({ error: 'Not JSON: set the webhook content type to application/json' });
  }
  if (payload.action !== 'released') return res.status(200).json({ sent: false, why: `Release ${payload.action}, not released` });

  const release = asRelease(payload.release);
  if (!release) return res.status(200).json({ sent: false, why: 'Not an android-v* release with its APK uploaded' });

  // Re-publishing an old version shouldn't tell everyone it's new.
  try {
    const latest = await latestRelease();
    if (latest && newer(latest.version, release.version)) {
      return res.status(200).json({ sent: false, why: `${latest.version} is newer than ${release.version}` });
    }
  } catch (cause) {
    console.warn('push/release: could not compare with the newest release:', cause.message);
  }

  try {
    await sendToTopic(TOPIC, {
      title: `uwuBoard ${release.version} is out`,
      body: 'Tap to see what is new and update.',
      data: { type: 'release', version: release.version },
      channel: 'releases',
      tag: 'release',
    });
  } catch (cause) {
    const why = typeof cause.body === 'string' ? cause.body
      : cause.body?.error?.message ? `${cause.message}: ${cause.body.error.message}` : cause.message;
    console.error('push/release:', why);
    return res.status(502).json({ sent: false, error: why });
  }
  return res.status(200).json({ sent: true, version: release.version });
};
