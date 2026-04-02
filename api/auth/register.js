const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const { username, email, password } = req.body || {};
  if (!username || !email || !password)
    return res.status(400).json({ error: 'username, email, and password are required' });
  if (password.length < 8)
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  if (!/^[a-zA-Z0-9_]{3,24}$/.test(username))
    return res.status(400).json({ error: 'Username must be 3-24 alphanumeric/underscore characters' });

  // Check uniqueness
  const { data: existing } = await supabase
    .from('uwu_users')
    .select('id')
    .or(`username.eq.${username},email.eq.${email}`)
    .maybeSingle();

  if (existing) return res.status(409).json({ error: 'Username or email already taken' });

  const hash = await bcrypt.hash(password, 12);
  const { data: user, error } = await supabase
    .from('uwu_users')
    .insert({ username, email, password_hash: hash })
    .select('id, username')
    .single();

  if (error) return res.status(500).json({ error: 'Registration failed' });

  const token = crypto.randomBytes(32).toString('hex');
  const expires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

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