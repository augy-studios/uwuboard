// POST /api/boards/create { board }: saves a new board for the signed-in user.
module.exports = async (request, response) => {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase = require('../lib/supabase');
    const { boardData } = require('../lib/images');
    const { userId } = await requireAuth(request);
    let body = request.body;
    if (!body) {
      body = {};
    }
    const { board } = body;
    if (board === null || board === undefined || !board.id || !board.name) {
      return response.status(400).json({ error: 'Invalid board' });
    }

    const { error } = await supabase.from('uwuboard_boards').insert({
      id: board.id,
      user_id: userId,
      name: board.name,
      data: boardData(board, userId),
    });
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
