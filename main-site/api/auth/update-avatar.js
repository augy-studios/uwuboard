const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');

// PUT /api/auth/update-avatar { imageData }: stores the picture (a data: URL, WebP or PNG) as
// `<userId>/avatar.<extension>` in the avatars bucket and saves its address on the user.
module.exports = async (request, response) => {
  if (request.method !== 'PUT') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { userId } = await requireAuth(request);
    let body = request.body;
    if (!body) {
      body = {};
    }
    const { imageData } = body;
    if (!imageData) {
      return response.status(400).json({ error: 'imageData required' });
    }

    const isWebP = imageData.startsWith('data:image/webp');
    let extension;
    let contentType;
    if (isWebP) {
      extension = 'webp';
      contentType = 'image/webp';
    } else {
      extension = 'png';
      contentType = 'image/png';
    }
    const base64 = imageData.replace(/^data:image\/\w+;base64,/, '');
    const buffer = Buffer.from(base64, 'base64');
    const path = `${userId}/avatar.${extension}`;

    const { error: uploadError } = await supabase.storage
      .from('avatars')
      .upload(path, buffer, { contentType, upsert: true });
    if (uploadError) {
      throw uploadError;
    }

    const { data: { publicUrl } } = supabase.storage.from('avatars').getPublicUrl(path);

    await supabase.from('uwu_users').update({ avatar_url: publicUrl }).eq('id', userId);

    // Not the address: the page fetches the bytes from api/auth/avatar.js.
    return response.status(200).json({ ok: true });
  } catch (error) {
    let status = error.status;
    if (!status) {
      status = 500;
    }
    return response.status(status).json({ error: error.message });
  }
};
