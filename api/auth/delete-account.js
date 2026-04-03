const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');

module.exports = async (req, res) => {
  if (req.method !== 'DELETE') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { requireAuth } = require('../lib/auth');
    const { userId } = await requireAuth(req);
    const { password } = req.body || {};
    if (!password) return res.status(400).json({ error: 'Password required' });

    const { data: user } = await supabase
      .from('uwu_users').select('password_hash').eq('id', userId).single();
    if (!user) return res.status(404).json({ error: 'User not found' });

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) return res.status(401).json({ error: 'Incorrect password' });

    await supabase.from('uwu_sessions').delete().eq('user_id', userId);
    await supabase.from('uwu_boards').delete().eq('user_id', userId);
    await supabase.from('uwu_users').delete().eq('id', userId);

    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
