const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');

module.exports = async (req, res) => {
  if (req.method !== 'PUT') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { userId } = await requireAuth(req);
    const { imageData } = req.body || {};
    if (!imageData) return res.status(400).json({ error: 'imageData required' });

    const isWebP = imageData.startsWith('data:image/webp');
    const ext = isWebP ? 'webp' : 'png';
    const contentType = isWebP ? 'image/webp' : 'image/png';
    const base64 = imageData.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(base64, 'base64');
    const path = `${userId}/avatar.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from('avatars')
      .upload(path, buffer, { contentType, upsert: true });
    if (uploadError) throw uploadError;

    const { data: { publicUrl } } = supabase.storage.from('avatars').getPublicUrl(path);

    await supabase.from('uwu_users').update({ avatar_url: publicUrl }).eq('id', userId);

    // Return with cache-buster so the browser shows the new image immediately
    return res.status(200).json({ avatarUrl: `${publicUrl}?v=${Date.now()}` });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
