module.exports = async (req, res) => {
  if (req.method !== 'DELETE') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase4 = require('../lib/supabase');
    const { userId } = await requireAuth(req);
    const { boardId } = req.body || {};
    if (!boardId) return res.status(400).json({ error: 'boardId required' });

    const { error } = await supabase4.from('uwu_boards')
      .delete()
      .eq('id', boardId)
      .eq('user_id', userId);
    if (error) throw error;
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};