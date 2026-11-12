module.exports = async (req, res) => {
  if (req.method !== 'PUT') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { requireAuth } = require('../lib/auth');
    const supabase3 = require('../lib/supabase');
    const { userId } = await requireAuth(req);
    const { board } = req.body || {};
    if (!board?.id) return res.status(400).json({ error: 'Invalid board' });

    // Upsert: create if doesn't exist, update otherwise
    const { error } = await supabase3.from('uwu_boards').upsert({
      id: board.id,
      user_id: userId,
      name: board.name,
      data: { columns: board.columns || [] },
    }, { onConflict: 'id' });
    if (error) throw error;
    return res.status(200).json({ ok: true });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};