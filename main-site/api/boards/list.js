const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');
const { cleanColumns } = require('../lib/images');

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
    // No storage addresses in the list: each image goes by its name, and its bytes come from
    // api/images/get.js.
    const boards = (data || []).map(row => ({
      id: row.id,
      name: row.name,
      ...row.data,
      columns: cleanColumns(row.data?.columns, userId),
    }));
    return res.status(200).json({ boards });
  } catch (e) {
    return res.status(e.status || 500).json({ error: e.message });
  }
};
