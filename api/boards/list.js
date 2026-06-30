const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');
const { verifySignedRequest } = require('../../lib/uwu-request-signing-server');

module.exports = async (req, res) => {
  if (req.method !== 'GET') return res.status(405).json({ error: 'Method not allowed' });
  try {
    const verification = await verifySignedRequest(req, supabase);
    if (!verification.valid) return res.status(401).json({ error: verification.reason });

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