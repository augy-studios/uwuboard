// DELETE /api/boards/delete { boardId }: deletes one of the signed-in user's boards.
module.exports = async (request, response) => {
  if (request.method !== 'DELETE') {
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
    const { boardId } = body;
    if (!boardId) {
      return response.status(400).json({ error: 'boardId required' });
    }

    const { error } = await supabase.from('uwuboard_boards')
      .delete()
      .eq('id', boardId)
      .eq('user_id', userId);
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