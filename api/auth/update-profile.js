const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');

module.exports = async (req, res) => {
  if (req.method !== 'PUT') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { requireAuth } = require('../lib/auth');
    const { userId } = await requireAuth(req);
    const { displayName, newPassword } = req.body || {};

    const updates = {};

    if (displayName !== undefined) {
      const name = displayName.trim();
      if (!/^[a-zA-Z0-9_]{3,24}$/.test(name))
        return res.status(400).json({ error: 'Name must be 3–24 alphanumeric/underscore characters' });
      // Check uniqueness (exclude self)
      const { data: existing } = await supabase
        .from('uwu_users').select('id').eq('username', name).neq('id', userId).maybeSingle();
      if (existing) return res.status(409).json({ error: 'That name is already taken' });
      updates.username = name;
    }

    if (newPassword) {
      if (newPassword.length < 8)
        return res.status(400).json({ error: 'Password must be at least 8 characters' });
      updates.password_hash = await bcrypt.hash(newPassword, 12);
    }

    if (Object.keys(updates).length === 0)
      return res.status(400).json({ error: 'Nothing to update' });

    const { error } = await supabase.from('uwu_users').update(updates).eq('id', userId);
    if (error) throw error;

    return res.status(200).json({ ok: true, username: updates.username });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
