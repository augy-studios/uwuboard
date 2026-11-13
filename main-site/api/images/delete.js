module.exports = async (req, res) => {
  if (req.method !== 'DELETE') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase = require('../lib/supabase');
    const { IMAGE_BUCKET, isFile } = require('../lib/images');
    const { userId } = await requireAuth(req);
    const { file, path } = req.body || {};

    // `file`, the object's name in the caller's own folder. `path` is what pages from before
    // images were hidden still send.
    let key = null;
    if (isFile(file)) key = `${userId}/${file}`;
    else if (typeof path === 'string' && path.startsWith(`${userId}/`) && isFile(path.slice(userId.length + 1))) key = path;
    if (!key) return res.status(400).json({ error: 'No image' });

    const { error } = await supabase.storage.from(IMAGE_BUCKET).remove([key]);
    if (error) throw error;
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
