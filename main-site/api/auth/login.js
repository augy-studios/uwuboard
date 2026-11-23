const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');
const crypto = require('crypto');

// POST /api/auth/login { username, password }: checks the password and starts a 30-day session.
module.exports = async (request, response) => {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'Method not allowed' });
  }

  let body = request.body;
  if (!body) {
    body = {};
  }
  const { username, password } = body;
  if (!username || !password) {
    return response.status(400).json({ error: 'Username and password are required' });
  }

  const { data: user, error } = await supabase
    .from('uwu_users')
    .select('id, username, password_hash, display_name, avatar_url')
    .eq('username', username)
    .maybeSingle();

  if (error || !user) {
    return response.status(401).json({ error: 'Invalid username or password' });
  }

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) {
    return response.status(401).json({ error: 'Invalid username or password' });
  }

  const token = crypto.randomBytes(32).toString('hex');
  const expires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  await supabase.from('uwu_sessions').insert({
    token,
    user_id: user.id,
    expires_at: expires.toISOString(),
  });

  let displayName = user.display_name;
  if (!displayName) {
    displayName = user.username;
  }
  return response.status(200).json({
    username: user.username,
    displayName: displayName,
    // Whether there is one, not where: the bytes come from api/auth/avatar.js.
    hasAvatar: Boolean(user.avatar_url),
    session: { token, userId: user.id },
  });
};