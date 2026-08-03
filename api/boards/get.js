const supabase = require('../lib/supabase');
const {
    requireAuth
} = require('../lib/auth');

module.exports = async (req, res) => {
    if (req.method !== 'GET') return res.status(405).json({
        error: 'Method not allowed'
    });

    try {
        const {
            userId
        } = await requireAuth(req);
        const {
            boardId
        } = req.query;
        if (!boardId) return res.status(400).json({
            error: 'boardId query parameter is required'
        });

        const {
            data,
            error
        } = await supabase
            .from('uwu_boards')
            .select('id, name, data, created_at, updated_at')
            .eq('id', boardId)
            .eq('user_id', userId) // ensures users can only fetch their own boards
            .single();

        if (error || !data) return res.status(404).json({
            error: 'Board not found'
        });

        const board = {
            id: data.id,
            name: data.name,
            createdAt: data.created_at,
            updatedAt: data.updated_at,
            ...data.data,
        };

        return res.status(200).json({
            board
        });
    } catch (e) {
        return res.status(e.status || 500).json({
            error: e.message
        });
    }
};