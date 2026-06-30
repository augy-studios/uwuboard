const supabase = require('../lib/supabase');
const { verifySignedRequest } = require('../../lib/uwu-request-signing-server');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const verification = await verifySignedRequest(req, supabase);
  if (!verification.valid) return res.status(401).json({ error: verification.reason });

  const auth = req.headers['authorization'] || '';
  const token = auth.replace(/^Bearer\s+/i, '').trim();
  if (token) await supabase.from('uwu_sessions').delete().eq('token', token);

  return res.status(200).json({ ok: true });
};