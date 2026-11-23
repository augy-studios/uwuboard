const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

// POST /api/auth/register { username, email, password }: creates the account and signs it in
// with a new 30-day session.
module.exports = async (request, response) => {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'Method not allowed' });
  }

  let body = request.body;
  if (!body) {
    body = {};
  }
  const { username, email, password } = body;
  if (!username || !email || !password) {
    return response.status(400).json({ error: 'username, email, and password are required' });
  }
  if (password.length < 8) {
    return response.status(400).json({ error: 'Password must be at least 8 characters' });
  }
  if (!/^[a-zA-Z0-9_]{3,24}$/.test(username)) {
    return response.status(400).json({ error: 'Username must be 3-24 alphanumeric/underscore characters' });
  }

  // Check uniqueness
  const { data: existing } = await supabase
    .from('uwu_users')
    .select('id')
    .or(`username.eq.${username},email.eq.${email}`)
    .maybeSingle();

  if (existing) {
    return response.status(409).json({ error: 'Username or email already taken' });
  }

  const passwordHash = await bcrypt.hash(password, 12);
  const { data: user, error } = await supabase
    .from('uwu_users')
    .insert({ username, email, password_hash: passwordHash })
    .select('id, username')
    .single();

  if (error) {
    return response.status(500).json({ error: 'Registration failed' });
  }

  const token = crypto.randomBytes(32).toString('hex');
  const expires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000); // 30 days

  await supabase.from('uwu_sessions').insert({
    token,
    user_id: user.id,
    expires_at: expires.toISOString(),
  });

  return response.status(200).json({
    username: user.username,
    displayName: user.username,
    session: { token, userId: user.id },
  });
};