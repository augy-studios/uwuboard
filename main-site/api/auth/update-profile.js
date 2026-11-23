const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');

// PUT /api/auth/update-profile { displayName?, newPassword? }: changes the display name and/or
// the password, whichever were sent.
module.exports = async (request, response) => {
  if (request.method !== 'PUT') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { requireAuth } = require('../lib/auth');
    const { userId } = await requireAuth(request);
    let body = request.body;
    if (!body) {
      body = {};
    }
    const { displayName, newPassword } = body;

    const updates = {};

    if (displayName !== undefined) {
      const name = displayName.trim();
      if (name.length < 1 || name.length > 32) {
        return response.status(400).json({ error: 'Display name must be 1–32 characters' });
      }
      updates.display_name = name;
    }

    if (newPassword) {
      if (newPassword.length < 8) {
        return response.status(400).json({ error: 'Password must be at least 8 characters' });
      }
      updates.password_hash = await bcrypt.hash(newPassword, 12);
    }

    if (Object.keys(updates).length === 0) {
      return response.status(400).json({ error: 'Nothing to update' });
    }

    const { error } = await supabase.from('uwu_users').update(updates).eq('id', userId);
    if (error) {
      throw error;
    }

    return response.status(200).json({ ok: true, displayName: updates.display_name });
  } catch (error) {
    let status = error.status;
    if (!status) {
      status = 500;
    }
    return response.status(status).json({ error: error.message });
  }
};
