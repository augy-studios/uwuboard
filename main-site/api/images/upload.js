// POST /api/images/upload { imageData, fileName }: stores a card image (a base64 data: URL)
// under a new random name in the caller's own folder, and answers with that name.
module.exports = async (request, response) => {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase = require('../lib/supabase');
    const { userId } = await requireAuth(request);
    let body = request.body;
    if (!body) {
      body = {};
    }
    const { imageData, fileName } = body;
    if (!imageData) {
      return response.status(400).json({ error: 'No image data' });
    }

    const mimeMatch = imageData.match(/^data:(image\/[\w+]+);base64,/);
    if (!mimeMatch) {
      return response.status(400).json({ error: 'Invalid image format' });
    }
    const contentType = mimeMatch[1];
    const base64 = imageData.slice(mimeMatch[0].length);
    const buffer = Buffer.from(base64, 'base64');

    const extension = contentType.split('/')[1].replace('jpeg', 'jpg').replace('png', 'png').replace('webp', 'webp');
    const path = `${userId}/${Date.now()}-${Math.random().toString(36).slice(2)}.${extension}`;

    const { error: uploadError } = await supabase.storage
      .from('card-images')
      .upload(path, buffer, { contentType, upsert: false });
    if (uploadError) {
      throw uploadError;
    }

    // The object's name, not its address: the page shows it through api/images/get.js.
    // `path` (the key, which names no host or bucket) is for pages still running the build
    // from before, which save it back; api/lib/images.js turns it into `file`. Drop it once
    // those have reloaded.
    const file = path.slice(userId.length + 1);
    return response.status(200).json({ file, path });
  } catch (error) {
    let status = error.status;
    if (!status) {
      status = 500;
    }
    return response.status(status).json({ error: error.message });
  }
};
