const crypto = require('crypto');
const supabase = require('../lib/supabase');

const GUEST_TTL_MS = 10 * 60 * 1000;

module.exports = async (req, res) => {
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });

  // Same-origin requests sometimes arrive with no Origin header at all — that's normal,
  // only reject when Origin is present and not in the allowed list.
  const origin = req.headers['origin'];
  if (origin) {
    const allowed = (process.env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
    if (!allowed.includes(origin)) return res.status(403).json({ error: 'Origin not allowed' });
  }

  const appId = (req.query && req.query.app) || 'unknown';
  const sessionToken = crypto.randomUUID();
  const signingKey = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + GUEST_TTL_MS);

  const { error } = await supabase.from('uwu_signing_keys').insert({
    session_token: sessionToken,
    signing_key: signingKey,
    is_guest: true,
    app_id: appId,
    expires_at: expiresAt.toISOString(),
  });
  if (error) return res.status(500).json({ error: 'Failed to issue guest key' });

  return res.status(200).json({ key_id: sessionToken, signing_key: signingKey });
};
