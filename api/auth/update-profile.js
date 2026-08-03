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
      if (name.length < 1 || name.length > 32)
        return res.status(400).json({ error: 'Display name must be 1–32 characters' });
      updates.display_name = name;
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

    return res.status(200).json({ ok: true, displayName: updates.display_name });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
