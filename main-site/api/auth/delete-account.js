// DELETE /api/auth/delete-account { password }: Delete Account, from the site's Profile and the
// apps'. Everything the account has goes: its card images and its avatar (each in the user's
// own folder of its bucket, `<user id>/…`: api/images/upload.js, api/auth/update-avatar.js),
// then its sessions, its boards and the account itself. The Privacy page (privacy.html) and
// Google Play's Data safety answers (GOOGLE-PLAY.md) say so.
//
// The pictures go first: if they can't be removed, nothing is deleted and it answers 500, so
// trying again finds the account as it was, rather than an account gone and its pictures left.
const supabase = require('../lib/supabase');
const bcrypt = require('bcryptjs');

const BUCKETS = ['card-images', 'avatars'];
// Listed and removed a page at a time. A page that removes nothing ends it, so a storage that
// keeps answering with the same files can't go round for ever.
const PAGE = 100;
const MAX_PAGES = 1000;

// Every file in the user's folder of `bucket`. The folders are flat: a card image is
// `<user id>/<file>` and an avatar `<user id>/avatar.<ext>`, each a file of its own.
async function removeFolder(bucket, userId) {
  const store = supabase.storage.from(bucket);
  for (let page = 0; page < MAX_PAGES; page++) {
    const { data, error } = await store.list(userId, { limit: PAGE });
    if (error) throw error;
    // A sub-folder is listed with no id; there are none, but they aren't files to remove.
    const keys = (data || []).filter((f) => f && f.id && f.name).map((f) => `${userId}/${f.name}`);
    if (!keys.length) return;
    const { data: removed, error: removeError } = await store.remove(keys);
    if (removeError) throw removeError;
    if (!removed || !removed.length) throw new Error(`${bucket}: nothing was removed`);
  }
  throw new Error(`${bucket}: more than ${PAGE * MAX_PAGES} files`);
}

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

    try {
      for (const bucket of BUCKETS) await removeFolder(bucket, userId);
    } catch (e) {
      console.error(`delete-account: pictures: ${e.message}`);
      return res.status(500).json({ error: "Couldn't delete your pictures, so nothing was deleted. Please try again." });
    }

    await supabase.from('uwu_sessions').delete().eq('user_id', userId);
    await supabase.from('uwuboard_boards').delete().eq('user_id', userId);
    await supabase.from('uwu_users').delete().eq('id', userId);

    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
