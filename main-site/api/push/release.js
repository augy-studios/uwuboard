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

// Whether the X-Hub-Signature-256 header matches the body signed with our webhook secret. The
// comparison takes the same time however much matches, so it gives nothing away.
function signedByGitHub(body, signature) {
  const secret = process.env.GITHUB_WEBHOOK_SECRET;
  if (!secret || typeof signature !== 'string' || !signature.startsWith('sha256=')) {
    return false;
  }
  const expected = Buffer.from(`sha256=${createHmac('sha256', secret).update(body).digest('hex')}`);
  const given = Buffer.from(signature);
  if (expected.length !== given.length) {
    return false;
  }
  return timingSafeEqual(expected, given);
}

// The body exactly as GitHub sent it: the signature is over these bytes.
async function rawBody(request) {
  if (Buffer.isBuffer(request.body)) {
    return request.body;
  }
  if (typeof request.body === 'string') {
    return Buffer.from(request.body);
  }
  // Not read yet: collect it from the request stream.
  const chunks = [];
  for await (const chunk of request) {
    if (Buffer.isBuffer(chunk)) {
      chunks.push(chunk);
    } else {
      chunks.push(Buffer.from(chunk));
    }
  }
  return Buffer.concat(chunks);
}

// Checks the delivery, then pushes the release to the topic unless there's a reason not to,
// answering with whether it was sent and, if not, why.
module.exports = async (request, response) => {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  const body = await rawBody(request);
  if (!signedByGitHub(body, request.headers['x-hub-signature-256'])) {
    return response.status(401).json({ error: 'Bad signature' });
  }

  const event = request.headers['x-github-event'];
  // GitHub's hello when the webhook is first saved.
  if (event === 'ping') {
    return response.status(200).json({ ok: true, pong: true });
  }
  if (event !== 'release') {
    return response.status(200).json({ sent: false, why: `Not a release event (${event})` });
  }

  let payload;
  try {
    payload = JSON.parse(body.toString('utf8'));
  } catch {
    return response.status(400).json({ error: 'Not JSON: set the webhook content type to application/json' });
  }
  if (payload.action !== 'released') {
    return response.status(200).json({ sent: false, why: `Release ${payload.action}, not released` });
  }

  const release = asRelease(payload.release);
  if (!release) {
    return response.status(200).json({ sent: false, why: 'Not an android-v* release with its APK uploaded' });
  }

  // Re-publishing an old version shouldn't tell everyone it's new.
  try {
    const latest = await latestRelease();
    if (latest && newer(latest.version, release.version)) {
      return response.status(200).json({ sent: false, why: `${latest.version} is newer than ${release.version}` });
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
    // The clearest reason: FCM's own text, else its error message added to ours, else ours.
    let googleErrorMessage;
    if (cause.body !== null && cause.body !== undefined) {
      const googleError = cause.body.error;
      if (googleError !== null && googleError !== undefined) {
        googleErrorMessage = googleError.message;
      }
    }
    let why;
    if (typeof cause.body === 'string') {
      why = cause.body;
    } else if (googleErrorMessage) {
      why = `${cause.message}: ${cause.body.error.message}`;
    } else {
      why = cause.message;
    }
    console.error('push/release:', why);
    return response.status(502).json({ sent: false, error: why });
  }
  return response.status(200).json({ sent: true, version: release.version });
};
