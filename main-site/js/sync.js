'use strict';

/* Syncing boards, and the theme, with another device, from the Sync window the tray opens.

   One device shows a code (with a link and a QR code of it), the other enters it. PeerJS's
   public broker introduces the two, then everything goes straight from one to the other over
   a WebRTC data channel, STUN only (js/p2p.js; docs/STUN-p2p-spec.md says why). So both have
   to be on the same network, or one on the other's hotspot. Works the same signed in or as a
   guest, and between the two.

   Once connected, each side sees the other's boards and ticks which to import, or which of its
   own to send over, or all of them, as sgbus-timings' sync does. Copying merges and never
   removes: a board this device hasn't got is added, and for one it has, missing columns and
   cards are added and a card on both keeps whichever copy was edited last (cards, columns and
   board names carry `updatedAt`, which script.js stamps). The theme is one of a thing, so
   taking the other's replaces this one's. Closing the Sync window ends the session.

   Images go over the channel too, as data URLs in chunks, ahead of the boards that need them,
   and only those the other side hasn't got. A signed-in device receiving one uploads it to its
   own account. The board lists sent on connecting carry no image bytes, just each image's id.

   The wire, on top of p2p.js's hello and bye:
     { type: 'boards', boards, theme }   either way: all of the sender's boards (images by id
                                         only) and theme, on connecting (the host in answer to
                                         hello) and whenever they change.
     { type: 'img', img, seq, total, part }  either way: one chunk of an image's data URL.
     { type: 'add', id, boards, theme }  either way: merge these into yours. Its images come
                                         first, as img chunks.
     { type: 'added', id, count }        the answer to add, with how many things changed there.
     { type: 'pull', id, boards }        either way: send me these boards (by id), which the
                                         other side answers with img chunks and an add.

   Loaded before script.js and uses its state and helpers (S, api, persistBoard, ...), so
   nothing here runs until script.js calls Sync.init(). */
(function () {
  const HOST_KEY = 'uwuboard.sync.hostCode';
  const LAST_KEY = 'uwuboard.sync.lastCode';

  // Caps on what's taken from another device, generous enough that nobody meets them.
  const MAX_BOARDS = 200;
  const MAX_COLUMNS = 60;
  const MAX_CARDS = 2000;
  const MAX_IMAGES = 40;
  // An image's chunks: a data URL split into pieces well under the spec's "tens of kilobytes",
  // and under the 16 KB PeerJS would otherwise split each message into again.
  const CHUNK = 12000;
  const MAX_IMAGE_CHARS = 12 * 1024 * 1024;

  // How long the other device has to answer an add before this one says it heard nothing,
  // plus time for the images sent with it.
  const ACK_MS = 6000;
  // How long an import waits between pieces arriving.
  const PULL_IDLE_MS = 15000;

  const $ = (id) => document.getElementById(id);
  const $$ = (sel) => [...document.querySelectorAll(sel)];
  const tap = (selector) => document.querySelector(selector)?.click();

  /* ---- the theme ---- */

  // Each: its label, what it starts as (only one changed from that is offered, so taking the
  // other's never just undoes a choice), its value as words, and how it's read and put in
  // place, through the theme window's own buttons so the window follows as if tapped.
  const SETTINGS = {
    mode: {
      label: 'Light or dark', start: 'light',
      values: () => window.MODE_PREFERENCES || [],
      text: (v) => ({ light: 'Light', dark: 'Dark', time: 'Time-based' })[v] || v,
      get: () => window.getModePreference?.() || 'light',
      set: (v) => tap(`#modeToggle [data-mode="${v}"]`),
    },
    colour: {
      label: 'Brand colour', start: 'classic',
      values: () => (window.COLOR_THEMES || []).map((t) => t.id),
      text: (v) => (window.COLOR_THEMES || []).find((t) => t.id === v)?.label || v,
      get: () => window.getStoredColorTheme?.() || 'classic',
      set: (v) => tap(`#swatchGrid [data-theme-id="${v}"]`),
    },
  };

  const settingOk = (field, value) => !!SETTINGS[field] && typeof value === 'string' && SETTINGS[field].values().includes(value);

  function ownTheme() {
    return Object.entries(SETTINGS)
      .filter(([, s]) => s.get() !== s.start)
      .map(([field, s]) => ({ field, value: s.get() }));
  }

  /* ---- boards ---- */

  const clone = (v) => JSON.parse(JSON.stringify(v));
  const stamp = (v) => (Number.isFinite(v) && v > 0 ? v : 0);

  // A board as another device gets it in a list: each image by id and name, no bytes.
  function listBoard(board) {
    const b = clone(board);
    for (const col of b.columns || []) {
      for (const card of col.cards || []) {
        card.images = (card.images || []).map((img) => ({ id: img.id, name: img.name || '' }));
      }
    }
    return b;
  }

  const ownBoards = () => S.boards.map(listBoard);

  // Boards from the other device, checked field by field. They're input from another machine,
  // so anything malformed is dropped rather than stored, and duplicates go too.
  const ID_RE = /^[\w-]{1,64}$/;
  const isId = (v) => typeof v === 'string' && ID_RE.test(v);
  const text = (v, max) => (typeof v === 'string' ? v.slice(0, max) : '');
  const list = (v, max) => (Array.isArray(v) ? v.slice(0, max) : []);
  const PRIORITIES = ['', 'low', 'medium', 'high', 'urgent'];

  function cleanCard(raw) {
    if (!raw || !isId(raw.id)) return null;
    const images = list(raw.images, MAX_IMAGES)
      .filter((img) => img && isId(img.id))
      .map((img) => ({ id: img.id, name: text(img.name, 200) }));
    return {
      id: raw.id,
      title: text(raw.title, 500) || 'Untitled',
      description: text(raw.description, 20000),
      due: /^\d{4}-\d{2}-\d{2}$/.test(raw.due) ? raw.due : '',
      priority: PRIORITIES.includes(raw.priority) ? raw.priority : '',
      labels: list(raw.labels, 30)
        .filter((l) => l && typeof l.text === 'string' && l.text.trim() && /^#[0-9a-f]{6}$/i.test(l.color))
        .map((l) => ({ text: l.text.trim().slice(0, 60), color: l.color })),
      checklist: list(raw.checklist, 300)
        .filter((c) => c && typeof c.text === 'string' && c.text.trim())
        .map((c) => ({ text: c.text.slice(0, 500), done: c.done === true })),
      images,
      thumbnailId: images.some((img) => img.id === raw.thumbnailId) ? raw.thumbnailId : (images[0]?.id ?? null),
      updatedAt: stamp(raw.updatedAt),
    };
  }

  function cleanBoards(raw) {
    if (!Array.isArray(raw)) return null;
    const seen = new Set();
    const once = (key) => !seen.has(key) && !!seen.add(key);
    return raw.slice(0, MAX_BOARDS)
      .filter((b) => b && isId(b.id) && typeof b.name === 'string' && b.name.trim() && once(`board:${b.id}`))
      .map((b) => ({
        id: b.id,
        name: b.name.trim().slice(0, 120),
        updatedAt: stamp(b.updatedAt),
        columns: list(b.columns, MAX_COLUMNS)
          .filter((c) => c && isId(c.id) && typeof c.name === 'string' && once(`col:${b.id}/${c.id}`))
          .map((c) => ({
            id: c.id,
            name: c.name.trim().slice(0, 120) || 'Column',
            updatedAt: stamp(c.updatedAt),
            cards: list(c.cards, MAX_CARDS).map(cleanCard).filter((card) => card && once(`card:${b.id}/${card.id}`)),
          })),
      }));
  }

  function cleanTheme(raw) {
    const seen = new Set();
    return list(raw, 10)
      .filter((s) => settingOk(s?.field, s?.value) && !seen.has(s.field) && seen.add(s.field))
      .map((s) => ({ field: s.field, value: s.value }));
  }

  // What a card is, for telling whether two copies differ: everything but when it was stamped,
  // and its images by id.
  const cardSig = (c) => JSON.stringify([
    c.title, c.description || '', c.due || '', c.priority || '', c.labels || [], c.checklist || [],
    (c.images || []).map((img) => img.id), c.thumbnailId || null,
  ]);

  // Merges `src` into `dest` in place and says how many things that changed. Adds what `dest`
  // hasn't got; for what both have, the copy changed last wins. Never removes anything.
  function mergeBoardInto(dest, src) {
    let changes = 0;
    if (stamp(src.updatedAt) > stamp(dest.updatedAt)) {
      if (src.name !== dest.name) { dest.name = src.name; changes++; }
      dest.updatedAt = src.updatedAt;
    }

    const cols = new Map(dest.columns.map((c) => [c.id, c]));
    for (const sc of src.columns) {
      const dc = cols.get(sc.id);
      if (!dc) {
        const added = { id: sc.id, name: sc.name, updatedAt: stamp(sc.updatedAt), cards: [] };
        dest.columns.push(added);
        cols.set(sc.id, added);
        changes++;
      } else if (stamp(sc.updatedAt) > stamp(dc.updatedAt)) {
        if (sc.name !== dc.name) { dc.name = sc.name; changes++; }
        dc.updatedAt = sc.updatedAt;
      }
    }

    // Where each of dest's cards is now.
    const where = new Map();
    for (const col of dest.columns) for (const card of col.cards) where.set(card.id, col);

    for (const sc of src.columns) {
      const into = cols.get(sc.id);
      for (const card of sc.cards) {
        const at = where.get(card.id);
        if (!at) {
          into.cards.push(clone(card));
          where.set(card.id, into);
          changes++;
          continue;
        }
        const i = at.cards.findIndex((c) => c.id === card.id);
        const mine = at.cards[i];
        if (stamp(card.updatedAt) <= stamp(mine.updatedAt)) continue;
        if (at === into && cardSig(mine) === cardSig(card)) {
          mine.updatedAt = card.updatedAt;
          continue;
        }
        // Its own images come along by id; resolveImages() fills in the ones this device has.
        const copy = clone(card);
        if (at === into) at.cards[i] = copy;
        else {
          at.cards.splice(i, 1);
          into.cards.push(copy);
          where.set(card.id, into);
        }
        changes++;
      }
    }
    return changes;
  }

  // Whether merging `src` into the boards `into` would change anything there.
  function wouldChange(into, src) {
    const dest = into.find((b) => b.id === src.id);
    return !dest || mergeBoardInto(clone(dest), src) > 0;
  }

  // Every image this device has, by id, wherever it is.
  function ownImages() {
    const out = new Map();
    for (const board of S.boards) {
      for (const col of board.columns) {
        for (const card of col.cards) for (const img of card.images || []) out.set(img.id, img);
      }
    }
    return out;
  }

  // A merged card's images as this device keeps them: its own copy where it has the image,
  // otherwise the bytes that came over (uploaded first when signed in). One that didn't arrive
  // is left out, and the thumbnail moves to one that's there.
  async function resolveImages(board, local) {
    for (const col of board.columns) {
      for (const card of col.cards) {
        if (!card.images?.length) continue;
        const kept = [];
        for (const img of card.images) {
          if (img.file || img.data || img.url) { kept.push(img); continue; }
          if (local.has(img.id)) { kept.push(local.get(img.id)); continue; }
          const data = sync.received.get(img.id);
          if (!data) continue;
          if (S.isGuest) {
            kept.push({ id: img.id, name: img.name, data });
            continue;
          }
          try {
            const r = await api('POST', '/images/upload', { imageData: data, fileName: img.name || 'image' });
            const entry = { id: img.id, name: img.name, file: r.file };
            local.set(img.id, entry);
            kept.push(entry);
          } catch { /* left out; the card keeps the rest */ }
        }
        card.images = kept;
        if (!kept.some((img) => img.id === card.thumbnailId)) card.thumbnailId = kept[0]?.id ?? null;
      }
    }
  }

  // Merges boards and theme from the other device into this one, saves them, and says how many
  // things that changed.
  async function mergeIn(boards, theme) {
    let count = 0;
    for (const { field, value } of theme) {
      if (SETTINGS[field].get() !== value) {
        SETTINGS[field].set(value);
        count++;
      }
    }

    const local = ownImages();
    const changed = [];
    for (const src of boards) {
      let dest = S.boards.find((b) => b.id === src.id);
      if (!dest) {
        dest = { id: src.id, name: src.name, updatedAt: stamp(src.updatedAt), columns: [] };
        mergeBoardInto(dest, src);
        S.boards.push(dest);
        changed.push(dest);
      } else if (mergeBoardInto(dest, src) > 0) {
        changed.push(dest);
      }
    }
    for (const board of changed) await resolveImages(board, local);

    if (changed.length) {
      if (S.isGuest) saveGuest();
      else await Promise.all(changed.map((board) => api('PUT', '/boards/update', { board }).catch(() => toast('Sync error', 'error'))));
      boardsChanged(changed);
    }
    return count + changed.length;
  }

  /* ---- sessions ---- */

  const sync = {
    role: null,        // 'host' | 'guest' while a session runs
    conn: null,        // its P2P.Host or P2P.Guest
    status: 'idle',
    theirs: null,      // the other side's { boards, theme }, once they've arrived
    tab: 'import',
    picked: { import: new Set(), export: new Set() },
    pending: new Map(), // add id -> timer, for sends not yet answered
    pulls: new Map(),   // pull id -> timer, for imports not yet arrived
    incoming: new Map(), // image id -> { total, parts }
    received: new Map(), // image id -> data URL, this session
    lastId: 0,
    retriedTaken: false,
    droppedCode: '',
    wakeLock: null,
    pendingLink: '',
  };

  function readKey(key) {
    try { return localStorage.getItem(key) || ''; } catch { return ''; }
  }

  function writeKey(key, value) {
    try {
      if (value) localStorage.setItem(key, value);
      else localStorage.removeItem(key);
    } catch { /* private mode: codes just aren't remembered */ }
  }

  const syncLink = (code) => `${location.origin}/#sync/${code}`;

  function beginSession(role) {
    sync.role = role;
    sync.status = 'connecting';
    sync.theirs = null;
    sync.droppedCode = '';
    sync.tab = 'import';
    sync.picked.import.clear();
    sync.picked.export.clear();
    showNote('');
    holdScreenOn();
  }

  // Tears down whatever is running. `bye` is for a guest leaving on purpose, which retires the
  // host's code; anything else just closes.
  function endSession({ bye = false, text: message = '', tone = 'busy' } = {}) {
    const conn = sync.conn;
    // Cleared first, so the status the closing connection reports on its way out is ignored.
    sync.conn = null;
    if (conn) {
      if (bye && sync.role === 'guest') conn.leave();
      else conn.close();
    }
    for (const timer of [...sync.pending.values(), ...sync.pulls.values()]) clearTimeout(timer);
    sync.pending.clear();
    sync.pulls.clear();
    sync.incoming.clear();
    sync.received.clear();
    sync.role = null;
    sync.status = 'idle';
    sync.theirs = null;
    releaseScreen();
    showStatus(message, tone);
    render();
  }

  // Stop, Cancel or Disconnect, or the window closing.
  function stop() {
    sync.droppedCode = '';
    if (sync.role) endSession({ bye: true });
  }

  async function startHosting() {
    if (sync.role) return;
    const stored = readKey(HOST_KEY);
    const code = P2P.isValidCode(stored) ? stored : P2P.generateCode();
    writeKey(HOST_KEY, code);

    beginSession('host');
    $('syncCode').textContent = code;
    $('syncLink').textContent = syncLink(code);
    $('syncQr').innerHTML = window.qrToSvg ? qrToSvg(syncLink(code)) : '';

    const host = new P2P.Host({ maxGuests: 1 });
    sync.conn = host;
    host.addEventListener('status', ({ detail }) => {
      if (sync.conn !== host) return;
      // The stored code is held by something else: another tab, or the broker not yet letting
      // go of it after a reload. A fresh one, once; a second collision in a row is not stale.
      if (detail.taken && !sync.retriedTaken) {
        sync.retriedTaken = true;
        newHostCode();
        return;
      }
      if (detail.status === 'error') {
        if (detail.taken) writeKey(HOST_KEY, '');
        endSession({ text: detail.message, tone: 'error' });
        return;
      }
      if (detail.status === 'waiting') sync.retriedTaken = false;
      onStatus(detail.status);
    });
    // A newcomer replaces the device that was connected, whose boards no longer apply.
    host.addEventListener('join', () => {
      if (sync.conn !== host) return;
      sync.theirs = null;
      renderList();
    });
    host.addEventListener('message', ({ detail }) => {
      if (sync.conn === host) onMessage(detail.message);
    });
    render();

    try {
      await host.start(code);
    } catch {
      if (sync.conn === host) endSession({ text: 'Could not load syncing. Check your connection.', tone: 'error' });
    }
  }

  // Gives up the code on show for a fresh one, which the old one stops working the moment it does.
  async function newHostCode(note = '') {
    endSession();
    writeKey(HOST_KEY, '');
    await startHosting();
    if (note) showNote(note);
  }

  async function join(input) {
    const code = P2P.normaliseCode(input);
    if (!P2P.isValidCode(code)) {
      showStatus(`The code is the ${P2P.CODE_LENGTH} letters and numbers on the other device’s screen.`, 'error');
      return;
    }
    if (sync.role) endSession();

    beginSession('guest');
    writeKey(LAST_KEY, code);
    $('syncCodeInput').value = code;

    const guest = new P2P.Guest();
    sync.conn = guest;
    guest.addEventListener('status', ({ detail }) => {
      if (sync.conn !== guest) return;
      const { status } = detail;
      if (status === 'dropped') {
        endSession({ text: 'Lost the connection to the other device. Press Connect to try again.', tone: 'warn' });
        sync.droppedCode = code;
      } else if (status === 'unreachable') {
        endSession({
          text: 'Could not reach the other device. Both have to be on the same network: join the same wifi, or turn on a hotspot on one and join it from the other. Check the code is still the one on screen.',
          tone: 'error',
        });
      } else if (status === 'error') {
        endSession({ text: detail.message, tone: 'error' });
      } else {
        onStatus(status);
      }
    });
    guest.addEventListener('message', ({ detail }) => {
      if (sync.conn === guest) onMessage(detail.message);
    });
    render();

    try {
      await guest.connect(code);
    } catch {
      if (sync.conn === guest) endSession({ text: 'Could not load syncing. Check your connection.', tone: 'error' });
    }
  }

  function onStatus(status) {
    const was = sync.status;
    sync.status = status;
    if (status !== 'connected') sync.theirs = null;
    // The host answers p2p.js's hello with its boards; these are ours for it.
    else if (was !== 'connected' && sync.role === 'guest') sendBoards();
    render();
  }

  const send = (message) => sync.conn?.send(message);

  // Ids for add and pull, odd on the host and even on the guest, so an answer to one side's
  // request is never taken for an answer to the other's.
  const nextId = () => ++sync.lastId * 2 + (sync.role === 'host' ? 1 : 0);

  function sendBoards() {
    send({ type: 'boards', boards: ownBoards(), theme: ownTheme() });
  }

  // This device's boards changed (script.js): the other side's lists follow.
  let changeTimer = null;
  function changed() {
    if (sync.status !== 'connected') return;
    clearTimeout(changeTimer);
    changeTimer = setTimeout(() => {
      if (sync.status === 'connected') sendBoards();
      renderList();
    }, 300);
  }

  /* ---- images over the channel ---- */

  // Sends the images in `boards` that the other side hasn't got, ahead of whatever needs them,
  // and says how many characters that was. Stops if the session ends meanwhile.
  async function sendImages(boards) {
    const conn = sync.conn;
    const theirs = new Set();
    for (const b of sync.theirs?.boards || []) {
      for (const col of b.columns) for (const card of col.cards) for (const img of card.images) theirs.add(img.id);
    }
    let sent = 0;
    for (const board of boards) {
      for (const col of board.columns) {
        for (const card of col.cards) {
          for (const img of card.images || []) {
            if (theirs.has(img.id)) continue;
            theirs.add(img.id);
            let data;
            try { data = await ImageStore.dataUrl(img); } catch { continue; }
            if (sync.conn !== conn) return sent;
            if (typeof data !== 'string' || data.length > MAX_IMAGE_CHARS) continue;
            const total = Math.ceil(data.length / CHUNK);
            for (let seq = 0; seq < total; seq++) {
              send({ type: 'img', img: img.id, seq, total, part: data.slice(seq * CHUNK, (seq + 1) * CHUNK) });
            }
            sent += data.length;
          }
        }
      }
    }
    return sent;
  }

  const DATA_URL_RE = /^data:image\/(png|jpeg|webp|gif);base64,[A-Za-z0-9+/=]+$/;

  // One chunk of an image. Kept until the image is whole, then checked as a whole.
  function onChunk(m) {
    const total = Math.floor(Number(m.total));
    const seq = Math.floor(Number(m.seq));
    if (!isId(m.img) || typeof m.part !== 'string' || m.part.length > CHUNK
      || !(total >= 1 && total <= Math.ceil(MAX_IMAGE_CHARS / CHUNK)) || !(seq >= 0 && seq < total)) return;
    if (sync.received.has(m.img)) return;
    let entry = sync.incoming.get(m.img);
    if (!entry || entry.total !== total) {
      entry = { total, parts: new Array(total), have: 0 };
      sync.incoming.set(m.img, entry);
    }
    if (entry.parts[seq] === undefined) {
      entry.parts[seq] = m.part;
      entry.have++;
    }
    // An import still arriving is still alive.
    for (const [id, timer] of sync.pulls) {
      clearTimeout(timer);
      sync.pulls.set(id, pullTimer(id));
    }
    if (entry.have < total) return;
    sync.incoming.delete(m.img);
    const data = entry.parts.join('');
    if (DATA_URL_RE.test(data)) sync.received.set(m.img, data);
  }

  /* ---- messages ---- */

  // Everything the other device sends goes through here. Unknown types are ignored, never
  // thrown on: the other device may be a version ahead or behind.
  function onMessage(message) {
    switch (message.type) {
      case 'hello':
        if (sync.role === 'host') sendBoards();
        break;

      case 'boards': {
        const boards = cleanBoards(message.boards);
        if (!boards) break;
        sync.theirs = { boards, theme: cleanTheme(message.theme) };
        renderList();
        break;
      }

      case 'img':
        onChunk(message);
        break;

      case 'add':
        onAdd(message);
        break;

      case 'added': {
        const timer = sync.pending.get(message.id);
        if (timer === undefined) break;
        clearTimeout(timer);
        sync.pending.delete(message.id);
        const count = Math.max(0, Math.min(MAX_BOARDS + 10, Math.floor(Number(message.count)) || 0));
        showNote(count
          ? `Sent. The other device took ${count === 1 ? '1 new thing' : `${count} new things`}.`
          : 'Sent. The other device already had all of those.');
        break;
      }

      case 'pull':
        onPull(message);
        break;

      // The guest is finished with this code, so nobody else gets to use it.
      case 'bye':
        if (sync.role === 'host') newHostCode('The other device disconnected. The old code no longer works; this is a new one.');
        break;

      default:
        break;
    }
  }

  async function onAdd(message) {
    const boards = cleanBoards(message.boards);
    if (!boards || !Number.isInteger(message.id)) return;
    const conn = sync.conn;
    // An answer to this device's own import, or something the other side sent.
    const pulled = sync.pulls.has(message.id);
    if (pulled) {
      clearTimeout(sync.pulls.get(message.id));
      sync.pulls.delete(message.id);
    }
    if (boards.some((b) => b.columns.some((c) => c.cards.some((card) => card.images.length)))) showNote('Saving…');
    const count = await mergeIn(boards, cleanTheme(message.theme));
    if (sync.conn !== conn) return;
    send({ type: 'added', id: message.id, count });
    if (count) sendBoards();
    if (pulled) showNote(count === 1 ? 'Imported 1 thing to this device.' : `Imported ${count} things to this device.`);
    else showNote(count
      ? `The other device sent ${count === 1 ? '1 thing' : `${count} things`}, now saved here.`
      : 'The other device sent things this device already has.');
    renderList();
  }

  // The other side importing some of this device's boards: they go as if sent from here.
  async function onPull(message) {
    if (!Number.isInteger(message.id) || !Array.isArray(message.boards)) return;
    const ids = new Set(message.boards.filter(isId));
    const chosen = S.boards.filter((b) => ids.has(b.id)).map(clone);
    const conn = sync.conn;
    await sendImages(chosen);
    if (sync.conn !== conn) return;
    send({ type: 'add', id: message.id, boards: chosen.map(listBoard), theme: [] });
  }

  /* ---- copying ---- */

  // Every board and setting on one side as items, each keyed the same way on both devices.
  function items(side) {
    if (!side) return [];
    return [
      ...side.boards.map((board) => ({ key: `board:${board.id}`, kind: 'board', item: board })),
      ...side.theme.map((s) => ({ key: `setting:${s.field}=${s.value}`, kind: 'setting', item: s })),
    ];
  }

  const own = () => ({ boards: ownBoards(), theme: ownTheme() });
  const source = () => (sync.tab === 'import' ? sync.theirs : own());
  const dest = () => (sync.tab === 'import' ? own() : sync.theirs);

  // What's on offer in the tab on show, and whether each would change anything at the other end.
  function offered() {
    const from = source();
    const to = dest();
    if (!from || !to) return [];
    return items(from).map((f) => {
      if (f.kind === 'setting') {
        const there = f.item.value === (sync.tab === 'import' ? SETTINGS[f.item.field].get() : to.theme.find((s) => s.field === f.item.field)?.value || SETTINGS[f.item.field].start);
        return { ...f, done: there, update: false };
      }
      const exists = to.boards.some((b) => b.id === f.item.id);
      const done = !wouldChange(to.boards, f.item);
      return { ...f, done, update: exists && !done };
    });
  }

  async function copyPicked() {
    const picked = sync.picked[sync.tab];
    if (!picked.size || !source()) return;
    const chosen = items(source()).filter((f) => picked.has(f.key));
    const boards = chosen.filter((f) => f.kind === 'board').map((f) => f.item);
    const theme = chosen.filter((f) => f.kind === 'setting').map((f) => f.item);
    picked.clear();

    if (sync.tab === 'import') {
      // The theme straight away; boards are pulled, so their images come with them.
      let count = theme.length ? await mergeIn([], theme) : 0;
      if (boards.length) {
        const id = nextId();
        sync.pulls.set(id, pullTimer(id));
        send({ type: 'pull', id, boards: boards.map((b) => b.id) });
        showNote(boards.length === 1 ? 'Importing 1 board…' : `Importing ${boards.length} boards…`);
      } else {
        showNote(count === 1 ? 'Imported 1 thing to this device.' : `Imported ${count} things to this device.`);
      }
      if (count) sendBoards();
    } else {
      const id = nextId();
      const n = chosen.length;
      showNote(n === 1 ? 'Sending 1 thing…' : `Sending ${n} things…`);
      const full = S.boards.filter((b) => boards.some((x) => x.id === b.id)).map(clone);
      const conn = sync.conn;
      const chars = await sendImages(full);
      if (sync.conn !== conn) return;
      send({ type: 'add', id, boards: full.map(listBoard), theme });
      // More time for every 100 KB of images.
      sync.pending.set(id, setTimeout(() => {
        sync.pending.delete(id);
        showNote('No answer from the other device. Check it still says connected, then try again.', 'error');
      }, ACK_MS + Math.ceil(chars / 100000) * 2000));
    }
    renderList();
  }

  function pullTimer(id) {
    return setTimeout(() => {
      sync.pulls.delete(id);
      showNote('Nothing came from the other device. Check it still says connected, then try again.', 'error');
    }, PULL_IDLE_MS);
  }

  function copyLink() {
    const link = $('syncLink').textContent;
    if (!link || !navigator.clipboard) return;
    navigator.clipboard.writeText(link)
      .then(() => showNote('Link copied.'))
      .catch(() => showNote('Couldn’t copy the link. Type the code on the other device instead.', 'error'));
  }

  /* ---- screen wake lock ---- */

  // A phone that locks mid-sync suspends the page and drops the channel with it.
  async function holdScreenOn() {
    if (!sync.role || sync.wakeLock || !navigator.wakeLock) return;
    try {
      const lock = await navigator.wakeLock.request('screen');
      if (!sync.role) { lock.release().catch(() => {}); return; }
      sync.wakeLock = lock;
      lock.addEventListener('release', () => { if (sync.wakeLock === lock) sync.wakeLock = null; });
    } catch { /* battery saver, or not allowed: the session carries on without it */ }
  }

  function releaseScreen() {
    sync.wakeLock?.release().catch(() => {});
    sync.wakeLock = null;
  }

  /* ---- rendering ---- */

  function showStatus(message, tone = 'busy') {
    $('syncStatus').hidden = !message;
    $('syncStatusText').textContent = message;
    $('syncStatus').querySelector('.statusDot').className = `statusDot ${tone}`;
  }

  function showNote(message, tone = '') {
    $('syncNote').hidden = !message;
    $('syncNote').textContent = message;
    $('syncNote').classList.toggle('error', tone === 'error');
  }

  function render() {
    const { role, status } = sync;
    const connected = status === 'connected';

    $('syncStart').hidden = !!role;
    $('syncHost').hidden = role !== 'host' || connected;
    $('syncLive').hidden = !connected;
    $('syncControls').hidden = !role;
    $('syncNewCode').hidden = role !== 'host';
    $('syncEnd').textContent = connected ? 'Disconnect' : role === 'host' ? 'Stop' : 'Cancel';

    if (role === 'host' && status === 'waiting') {
      showStatus('Waiting for the other device. On it, open Sync and enter this code, or scan the QR code with its camera.', 'warn');
    } else if (role && status === 'connecting') {
      showStatus(role === 'host' ? 'Getting the code ready…' : 'Connecting to the other device…', 'busy');
    } else if (connected) {
      showStatus('Connected to the other device.', 'ok');
    }

    renderList();
  }

  function boardSub(board) {
    const cards = board.columns.reduce((n, c) => n + c.cards.length, 0);
    const images = board.columns.reduce((n, c) => n + c.cards.reduce((m, card) => m + (card.images?.length || 0), 0), 0);
    const parts = [
      board.columns.length === 1 ? '1 column' : `${board.columns.length} columns`,
      cards === 1 ? '1 card' : `${cards} cards`,
    ];
    if (images) parts.push(images === 1 ? '1 image' : `${images} images`);
    return parts.join(' · ');
  }

  function renderList() {
    if (sync.status !== 'connected') return;
    const importing = sync.tab === 'import';
    $$('#syncTabs [data-sync-tab]').forEach((tab) => {
      const on = tab.dataset.syncTab === sync.tab;
      tab.classList.toggle('active', on);
      tab.setAttribute('aria-selected', String(on));
    });
    $('syncListNote').textContent = importing
      ? 'The other device’s boards and theme. Tick the ones to copy to this device.'
      : 'This device’s boards and theme. Tick the ones to copy to the other device.';

    const picked = sync.picked[sync.tab];
    if (!sync.theirs) {
      picked.clear();
      $('syncList').innerHTML = '<div class="syncEmpty">Waiting for the other device…</div>';
      renderPicks([]);
      return;
    }

    const all = offered();
    // A pick the other end has since got some other way isn't on offer any more.
    const open = new Set(all.filter((f) => !f.done).map((f) => f.key));
    for (const key of picked) if (!open.has(key)) picked.delete(key);

    const row = ({ key, kind, item, done, update }) => {
      const title = kind === 'board' ? item.name : SETTINGS[item.field].label;
      const sub = kind === 'board' ? boardSub(item) : SETTINGS[item.field].text(item.value);
      const tag = done ? (importing ? 'Already here' : 'Already there') : update ? 'Has changes' : '';
      return `<label class="syncItem${done ? ' done' : ''}">` +
        `<input type="checkbox" data-sync-key="${esc(key)}"${done ? ' disabled' : picked.has(key) ? ' checked' : ''}>` +
        `<span class="syncItemText"><span class="name">${esc(title)}</span><span class="sub">${esc(sub)}</span></span>` +
        (tag ? `<span class="syncTag">${tag}</span>` : '') +
        '</label>';
    };
    const group = (kind, label) => {
      const rows = all.filter((f) => f.kind === kind);
      return rows.length ? `<div class="syncGroupLabel">${label}</div>${rows.map(row).join('')}` : '';
    };
    $('syncList').innerHTML = (group('board', 'Boards') + group('setting', 'Theme'))
      || `<div class="syncEmpty">${importing ? 'The other device has nothing to share yet.' : 'This device has nothing to share yet.'}</div>`;
    renderPicks(all);
  }

  // The Select all box and the button under the list, which follow the ticks without
  // redrawing the list.
  function renderPicks(all = offered()) {
    const importing = sync.tab === 'import';
    const picked = sync.picked[sync.tab];
    const open = all.filter((f) => !f.done);
    const ticked = open.filter((f) => picked.has(f.key)).length;
    const box = $('syncAll');
    box.disabled = !open.length;
    box.checked = open.length > 0 && ticked === open.length;
    box.indeterminate = ticked > 0 && ticked < open.length;

    const n = picked.size;
    const go = $('syncGo');
    go.disabled = !n;
    go.textContent = !n
      ? (importing ? 'Tick what to import' : 'Tick what to send')
      : importing
        ? (n === 1 ? 'Import 1 thing to this device' : `Import ${n} things to this device`)
        : (n === 1 ? 'Send 1 thing to the other device' : `Send ${n} things to the other device`);
  }

  /* ---- the window ---- */

  const modalOpen = () => !$('syncModal').classList.contains('hidden');

  // As the window opens: the last code this device joined with, ready to use again.
  function open() {
    openModal('syncModal');
    if (!sync.role && !$('syncCodeInput').value) $('syncCodeInput').value = readKey(LAST_KEY);
    render();
  }

  // A link from another device's QR code (#sync/CODE): the code filled in, waiting for a press
  // on Connect rather than connecting outright, since connecting shows this device's boards to
  // whoever made the link.
  function openLink(code) {
    history.replaceState(null, '', location.pathname + location.search);
    open();
    if (sync.role) return;
    $('syncCodeInput').value = P2P.normaliseCode(code);
    showStatus('Press Connect to sync with the device showing this code.', 'busy');
    $('syncJoinBtn').focus({ preventScroll: true });
  }

  // The app is on screen (signed in or as a guest): a sync link that opened the page can be used.
  function appShown() {
    if (!sync.pendingLink) return;
    const code = sync.pendingLink;
    sync.pendingLink = '';
    openLink(code);
  }

  function readLink() {
    const m = location.hash.match(/^#sync\/([A-Za-z0-9-]{1,20})$/);
    return m ? m[1] : '';
  }

  function init() {
    $('syncBtn').addEventListener('click', open);
    $('syncHostBtn').addEventListener('click', () => {
      sync.retriedTaken = false;
      startHosting();
    });
    $('syncJoinBtn').addEventListener('click', () => join($('syncCodeInput').value));
    $('syncCodeInput').addEventListener('keydown', (e) => {
      if (e.key === 'Enter') join(e.target.value);
    });
    $('syncCode').addEventListener('click', copyLink);
    $('syncNewCode').addEventListener('click', () => newHostCode());
    $('syncEnd').addEventListener('click', stop);

    $('syncTabs').addEventListener('click', (e) => {
      const tab = e.target.closest('[data-sync-tab]');
      if (!tab) return;
      sync.tab = tab.dataset.syncTab;
      renderList();
      $('syncList').scrollTop = 0;
    });
    $('syncList').addEventListener('change', (e) => {
      const key = e.target.dataset.syncKey;
      if (!key) return;
      const picked = sync.picked[sync.tab];
      if (e.target.checked) picked.add(key);
      else picked.delete(key);
      renderPicks();
    });
    $('syncAll').addEventListener('change', (e) => {
      const picked = sync.picked[sync.tab];
      for (const { key, done } of offered()) {
        if (done) continue;
        if (e.target.checked) picked.add(key);
        else picked.delete(key);
      }
      $$('#syncList [data-sync-key]:not(:disabled)').forEach((box) => { box.checked = picked.has(box.dataset.syncKey); });
      renderPicks();
    });
    $('syncGo').addEventListener('click', copyPicked);

    $('syncModal').addEventListener('click', (e) => {
      if (e.target === $('syncModal')) closeModal('syncModal');
    });
    // A session belongs to the open window, so nothing is left running out of sight. Watched
    // rather than hooked, as the window closes in several ways (its button, the backdrop,
    // Escape, signing out).
    new MutationObserver(() => {
      if (modalOpen()) return;
      stop();
      showStatus('');
      showNote('');
    }).observe($('syncModal'), { attributes: true, attributeFilter: ['class'] });

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible') return;
      // The browser lets go of the wake lock whenever the page is hidden.
      if (sync.role) holdScreenOn();
      // Back from the background with a channel that died meanwhile. An unreachable one isn't
      // retried: the network hasn't changed, so the result wouldn't either.
      else if (sync.droppedCode && modalOpen()) join(sync.droppedCode);
    });
    // A link followed in a page already open: used now, or kept until the app is on screen.
    addEventListener('hashchange', () => {
      const code = readLink();
      if (!code) return;
      if ($('app').classList.contains('hidden')) sync.pendingLink = code;
      else openLink(code);
    });

    sync.pendingLink = readLink();
    render();
  }

  window.Sync = { init, open, changed, appShown, stop };
})();
