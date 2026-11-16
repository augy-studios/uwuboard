const supabase = require('../lib/supabase');

module.exports = async (request, response) => {
  if (request.method !== 'POST') {
    return response.status(405).json({ error: 'Method not allowed' });
  }

  let authorizationHeader = request.headers['authorization'];
  if (!authorizationHeader) {
    authorizationHeader = '';
  }
  const token = authorizationHeader.replace(/^Bearer\s+/i, '').trim();
  if (token) {
    await supabase.from('uwu_sessions').delete().eq('token', token);
  }

  return response.status(200).json({ ok: true });
};