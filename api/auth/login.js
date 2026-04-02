const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { username, password } = req.body || {};
  if (!username || !password)
    return res.status(400).json({ error: 'Username and password are required' });

  const { data: user, error } = await supabase
    .from('uwu_users')
    .select('id, username, password_hash')
    .eq('username', username)
    .maybeSingle();

  if (error || !user) return res.status(401).json({ error: 'Invalid username or password' });

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) return res.status(401).json({ error: 'Invalid username or password' });

  const token = crypto.randomBytes(32).toString('hex');
  const expires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  await supabase.from('uwu_sessions').insert({
    token,
    user_id: user.id,
    expires_at: expires.toISOString(),
  });

  return res.status(200).json({
    username: user.username,
    session: { token, userId: user.id },
  });
};