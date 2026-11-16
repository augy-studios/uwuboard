// PUT /api/boards/update { board }: saves a board, creating it if it isn't stored yet.
module.exports = async (request, response) => {
  if (request.method !== 'PUT') {
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
    if (board === null || board === undefined || !board.id) {
      return response.status(400).json({ error: 'Invalid board' });
    }

    // Upsert: create if doesn't exist, update otherwise
    const { error } = await supabase.from('uwuboard_boards').upsert({
      id: board.id,
      user_id: userId,
      name: board.name,
      data: boardData(board, userId),
    }, { onConflict: 'id' });
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
