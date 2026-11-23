// DELETE /api/images/delete { file }: removes one card image from the caller's own folder.
module.exports = async (request, response) => {
  if (request.method !== 'DELETE') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase = require('../lib/supabase');
    const { IMAGE_BUCKET, isFile } = require('../lib/images');
    const { userId } = await requireAuth(request);
    let body = request.body;
    if (!body) {
      body = {};
    }
    const { file, path } = body;

    // `file`, the object's name in the caller's own folder. `path` is what pages from before
    // images were hidden still send.
    let key = null;
    if (isFile(file)) {
      key = `${userId}/${file}`;
    } else if (typeof path === 'string' && path.startsWith(`${userId}/`) && isFile(path.slice(userId.length + 1))) {
      key = path;
    }
    if (!key) {
      return response.status(400).json({ error: 'No image' });
    }

    const { error } = await supabase.storage.from(IMAGE_BUCKET).remove([key]);
    if (error) {
      throw error;
    }
    return response.status(200).json({ ok: true });
  } catch (error) {
    let status = error.status;
    if (!status) {
      status = 500;
    }
    return response.status(status).json({ error: error.message });
  }
};
