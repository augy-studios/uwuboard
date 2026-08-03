module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase = require('../lib/supabase');
    const { userId } = await requireAuth(req);
    const { imageData, fileName } = req.body || {};
    if (!imageData) return res.status(400).json({ error: 'No image data' });

    const mimeMatch = imageData.match(/^data:(image\/[\w+]+);base64,/);
    if (!mimeMatch) return res.status(400).json({ error: 'Invalid image format' });
    const contentType = mimeMatch[1];
    const base64 = imageData.slice(mimeMatch[0].length);
    const buffer = Buffer.from(base64, 'base64');

    const ext = contentType.split('/')[1].replace('jpeg', 'jpg').replace('png', 'png').replace('webp', 'webp');
    const path = `${userId}/${Date.now()}-${Math.random().toString(36).slice(2)}.${ext}`;

    const { error: uploadError } = await supabase.storage
      .from('card-images')
      .upload(path, buffer, { contentType, upsert: false });
    if (uploadError) throw uploadError;

    const { data: { publicUrl } } = supabase.storage
      .from('card-images')
      .getPublicUrl(path);

    return res.status(200).json({ url: publicUrl, path });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
