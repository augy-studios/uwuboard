const supabase = require('../lib/supabase');
const {
    requireAuth
} = require('../lib/auth');
const {
    cleanColumns
} = require('../lib/images');

// GET /api/boards/get?boardId=<id>: one of the signed-in user's boards, with its columns.
module.exports = async (request, response) => {
    if (request.method !== 'GET') {
        return response.status(405).json({
            error: 'Method not allowed'
        });
    }

    try {
        const {
            userId
        } = await requireAuth(request);
        const {
            boardId
        } = request.query;
        if (!boardId) {
            return response.status(400).json({
                error: 'boardId query parameter is required'
            });
        }

        const {
            data,
            error
        } = await supabase
            .from('uwuboard_boards')
            .select('id, name, data, created_at, updated_at')
            .eq('id', boardId)
            .eq('user_id', userId) // ensures users can only fetch their own boards
            .single();

        if (error || !data) {
            return response.status(404).json({
                error: 'Board not found'
            });
        }

        // No storage addresses: each image goes by its name (api/lib/images.js).
        let storedColumns;
        if (data.data !== null && data.data !== undefined) {
            storedColumns = data.data.columns;
        }
        const board = {
            id: data.id,
            name: data.name,
            createdAt: data.created_at,
            updatedAt: data.updated_at,
            ...data.data,
            columns: cleanColumns(storedColumns, userId),
        };

        return response.status(200).json({
            board
        });
    } catch (error) {
        let status = error.status;
        if (!status) {
            status = 500;
        }
        return response.status(status).json({
            error: error.message
        });
    }
};