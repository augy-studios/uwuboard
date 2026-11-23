// GET /api/auth/avatar: the signed-in user's avatar as bytes, so the page never learns where
// it's stored (docs/hide-images-spec.md). 404 when there isn't one.
const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');
const { sendImage } = require('../lib/images');

const AVATAR_BUCKET = 'avatars';

// `avatar_url` holds the public URL update-avatar.js saved. The key is worked out from it,
// and only a key in this user's own folder is read.
function avatarKey(stored, userId) {
  if (typeof stored !== 'string' || !stored) {
    return null;
  }
  let key = stored;
  const match = stored.split('?')[0].match(new RegExp(`/${AVATAR_BUCKET}/(.+)$`));
  if (match) {
    try {
      key = decodeURIComponent(match[1]);
    } catch {
      return null;
    }
  }
  if (/^[\w-]+\/avatar\.(webp|png)$/.test(key) && key.startsWith(`${userId}/`)) {
    return key;
  } else {
    return null;
  }
}

module.exports = async (request, response) => {
  if (request.method !== 'GET') {
    return response.status(405).json({ error: 'Method not allowed' });
  }

  let userId;
  try {
    ({ userId } = await requireAuth(request));
  } catch (error) {
    let status = error.status;
    if (!status) {
      status = 401;
    }
    return response.status(status).json({ error: error.message });
  }

  try {
    const { data: user } = await supabase.from('uwu_users').select('avatar_url').eq('id', userId).maybeSingle();
    let storedAvatarUrl;
    if (user !== null && user !== undefined) {
      storedAvatarUrl = user.avatar_url;
    }
    const key = avatarKey(storedAvatarUrl, userId);
    if (!key) {
      return response.status(404).json({ error: 'Not found' });
    }

    const { data: file, error } = await supabase.storage.from(AVATAR_BUCKET).download(key);
    if (error || !file) {
      return response.status(404).json({ error: 'Not found' });
    }

    const buffer = Buffer.from(await file.arrayBuffer());
    // A new avatar replaces the old one under the same route, so the browser checks every time.
    return sendImage(response, buffer, file.type, 'private, no-cache');
  } catch {
    return response.status(404).json({ error: 'Avatar unavailable' });
  }
};
