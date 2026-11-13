// GET /api/images/get?id=<file>: a card image's bytes, never its address
// (docs/hide-images-spec.md). `id` is the object's name inside the caller's own folder, so
// someone else's image and one that doesn't exist both come back as 404.
const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');
const { IMAGE_BUCKET, isFile, sendImage } = require('../lib/images');

module.exports = async (req, res) => {
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });

  let userId;
  try {
    ({ userId } = await requireAuth(req));
  } catch (e) {
    return res.status(e.status || 401).json({ error: e.message });
  }

  const id = req.query.id;
  if (!id) return res.status(400).json({ error: 'Missing id' });
  if (!isFile(id)) return res.status(404).json({ error: 'Not found' });

  try {
    // Read with the server's credentials, by key: this keeps working once the bucket is private.
    const { data: file, error } = await supabase.storage.from(IMAGE_BUCKET).download(`${userId}/${id}`);
    if (error || !file) return res.status(404).json({ error: 'Not found' });

    const buffer = Buffer.from(await file.arrayBuffer());
    // An image never changes under its name, so a day's private caching is safe.
    return sendImage(res, buffer, file.type, 'private, max-age=86400');
  } catch {
    return res.status(404).json({ error: 'Image unavailable' });
  }
};
