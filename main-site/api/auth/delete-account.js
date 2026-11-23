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
  for (let page = 0; page < MAX_PAGES; page = page + 1) {
    const { data, error } = await store.list(userId, { limit: PAGE });
    if (error) {
      throw error;
    }
    let listed = data;
    if (!listed) {
      listed = [];
    }
    // A sub-folder is listed with no id; there are none, but they aren't files to remove.
    const keys = listed
      .filter((listedFile) => {
        return listedFile && listedFile.id && listedFile.name;
      })
      .map((listedFile) => {
        return `${userId}/${listedFile.name}`;
      });
    if (!keys.length) {
      return;
    }
    const { data: removed, error: removeError } = await store.remove(keys);
    if (removeError) {
      throw removeError;
    }
    if (!removed || !removed.length) {
      throw new Error(`${bucket}: nothing was removed`);
    }
  }
  throw new Error(`${bucket}: more than ${PAGE * MAX_PAGES} files`);
}

// Checks the password, removes the pictures, then deletes the sessions, boards and account.
module.exports = async (request, response) => {
  if (request.method !== 'DELETE') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { requireAuth } = require('../lib/auth');
    const { userId } = await requireAuth(request);
    let body = request.body;
    if (!body) {
      body = {};
    }
    const { password } = body;
    if (!password) {
      return response.status(400).json({ error: 'Password required' });
    }

    const { data: user } = await supabase
      .from('uwu_users').select('password_hash').eq('id', userId).single();
    if (!user) {
      return response.status(404).json({ error: 'User not found' });
    }

    const valid = await bcrypt.compare(password, user.password_hash);
    if (!valid) {
      return response.status(401).json({ error: 'Incorrect password' });
    }

    try {
      for (const bucket of BUCKETS) {
        await removeFolder(bucket, userId);
      }
    } catch (error) {
      console.error(`delete-account: pictures: ${error.message}`);
      return response.status(500).json({ error: "Couldn't delete your pictures, so nothing was deleted. Please try again." });
    }

    await supabase.from('uwu_sessions').delete().eq('user_id', userId);
    await supabase.from('uwuboard_boards').delete().eq('user_id', userId);
    await supabase.from('uwu_users').delete().eq('id', userId);

    return response.status(200).json({ ok: true });
  } catch (error) {
    let status = error.status;
    if (!status) {
      status = 500;
    }
    return response.status(status).json({ error: error.message });
  }
};
