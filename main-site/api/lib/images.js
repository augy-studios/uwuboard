// Card images live in the card-images bucket under `<userId>/<file>`. The page only ever
// holds `file`, the object's name inside the user's own folder, and gets the bytes from
// api/images/get.js. It never sees a storage address (docs/hide-images-spec.md).

const IMAGE_BUCKET = 'card-images';

// An object name: no folders, no "..", nothing that could climb out of the user's folder.
const FILE_RE = /^[A-Za-z0-9][\w.-]{0,127}$/;

function isFile(value) {
  return typeof value === 'string' && FILE_RE.test(value) && !value.includes('..');
}

// The object name from a storage key, only when the key is in this user's folder.
function fileFromPath(path, userId) {
  if (typeof path !== 'string') return null;
  const prefix = `${userId}/`;
  if (!path.startsWith(prefix)) return null;
  const file = path.slice(prefix.length);
  return isFile(file) ? file : null;
}

// Rows from before this change kept the public URL as well:
// https://<project>.supabase.co/storage/v1/object/public/card-images/<userId>/<file>
function fileFromUrl(url, userId) {
  if (typeof url !== 'string') return null;
  const match = url.split('?')[0].match(new RegExp(`/${IMAGE_BUCKET}/(.+)$`));
  if (!match) return null;
  try {
    return fileFromPath(decodeURIComponent(match[1]), userId);
  } catch {
    return null;
  }
}

// An image entry as the page may see it and as it is stored: `url` and `path` go, and the
// object's name is kept as `file`, worked out from them for rows written before `file` was.
function cleanImage(image, userId) {
  if (!image || typeof image !== 'object') return image;
  const { url, path, ...rest } = image;
  const file = isFile(rest.file) ? rest.file : fileFromPath(path, userId) || fileFromUrl(url, userId);
  if (file) rest.file = file;
  else delete rest.file;
  return rest;
}

// Every card image in a board's columns, cleaned. Used both on the way out (list, get) and on
// the way in (create, update), so a page still running an older build, which sends `path`
// back, keeps its images.
function cleanColumns(columns, userId) {
  if (!Array.isArray(columns)) return [];
  return columns.map((col) => {
    if (!col || typeof col !== 'object' || !Array.isArray(col.cards)) return col;
    return {
      ...col,
      cards: col.cards.map((card) =>
        card && Array.isArray(card.images)
          ? { ...card, images: card.images.map((image) => cleanImage(image, userId)) }
          : card
      ),
    };
  });
}

// A board row's `data`, as stored: its columns, how it's shown, and when the board itself
// (its name or view) was last changed, which device sync compares (js/sync.js).
function boardData(board, userId) {
  const data = { columns: cleanColumns(board.columns, userId) };
  if (Number.isFinite(board.updatedAt)) data.updatedAt = board.updatedAt;
  // How the board is shown: as columns, or as a Timeline (js/timeline.js).
  if (board.view === 'timeline' || board.view === 'kanban') data.view = board.view;
  return data;
}

// The bytes, with the headers the spec asks for: private so no CDN or shared cache keeps
// one user's image for the next, and the declared type trusted rather than sniffed.
function sendImage(res, buffer, contentType, cacheControl) {
  res.setHeader('Content-Type', contentType || 'image/png');
  res.setHeader('Content-Length', buffer.length);
  res.setHeader('Cache-Control', cacheControl);
  res.setHeader('Vary', 'Authorization');
  res.setHeader('X-Content-Type-Options', 'nosniff');
  return res.status(200).send(buffer);
}

module.exports = { IMAGE_BUCKET, isFile, cleanColumns, boardData, sendImage };
