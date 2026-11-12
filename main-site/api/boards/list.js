const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');

module.exports = async (req, res) => {
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const { userId } = await requireAuth(req);
    const { data, error } = await supabase
      .from('uwu_boards')
      .select('id, name, data')
      .eq('user_id', userId)
      .order('created_at', { ascending: true });
    if (error) throw error;
    const boards = (data || []).map(row => ({
      id: row.id,
      name: row.name,
      ...row.data,
    }));
    return res.status(200).json({ boards });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};