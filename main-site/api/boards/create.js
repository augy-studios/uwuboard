module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase2 = require('../lib/supabase');
    const { userId } = await requireAuth(req);
    const { board } = req.body || {};
    if (!board?.id || !board?.name) return res.status(400).json({ error: 'Invalid board' });

    const { columns, ...meta } = board;
    const { error } = await supabase2.from('uwu_boards').insert({
      id: board.id,
      user_id: userId,
      name: board.name,
      data: { columns: columns || [] },
    });
    if (error) throw error;
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};