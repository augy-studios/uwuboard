const supabase = require('../lib/supabase');
const { requireAuth } = require('../lib/auth');
const { cleanColumns } = require('../lib/images');

// GET /api/boards/list: every board the signed-in user has, oldest first.
module.exports = async (request, response) => {
  if (request.method !== 'GET') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  try {
    const { userId } = await requireAuth(request);
    const { data, error } = await supabase
      .from('uwuboard_boards')
      .select('id, name, data')
      .eq('user_id', userId)
      .order('created_at', { ascending: true });
    if (error) {
      throw error;
    }
    // No storage addresses in the list: each image goes by its name, and its bytes come from
    // api/images/get.js.
    let rows = data;
    if (!rows) {
      rows = [];
    }
    const boards = rows.map((row) => {
      let storedColumns;
      if (row.data !== null && row.data !== undefined) {
        storedColumns = row.data.columns;
      }
      return {
        id: row.id,
        name: row.name,
        ...row.data,
        columns: cleanColumns(storedColumns, userId),
      };
    });
    return response.status(200).json({ boards });
  } catch (error) {
    let status = error.status;
    if (!status) {
      status = 500;
    }
    return response.status(status).json({ error: error.message });
  }
};
