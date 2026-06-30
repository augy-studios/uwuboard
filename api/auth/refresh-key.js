const crypto = require('crypto');
const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');

// Exchanges a still-valid session token for a fresh signing key. Lets a persisted
// ("remember me") session restore in a new tab/after a browser restart, where the
// previous tab's sessionStorage signing key is gone but the session token survives
// in localStorage. Exempt from verifySignedRequest like login/register — it's a
// key-issuance endpoint, gated by requireAuth instead.
module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    await requireAuth(req); // throws if session invalid/expired

    const auth = req.headers['authorization'] || '';
    const token = auth.replace(/^Bearer\s+/i, '').trim();

    const { data: session } = await supabase
      .from('uwu_sessions')
      .select('expires_at')
      .eq('token', token)
      .single();
    if (!session) return res.status(401).json({ error: 'Unauthorised' });

    const signingKey = crypto.randomBytes(32).toString('hex');
    const { error } = await supabase.from('uwu_signing_keys').upsert({
      session_token: token,
      signing_key: signingKey,
      is_guest: false,
      app_id: 'uwuboard',
      expires_at: session.expires_at,
    }, { onConflict: 'session_token' });
    if (error) throw error;

    return res.status(200).json({ signing_key: signingKey, key_id: token });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
