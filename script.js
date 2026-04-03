'use strict';

/* ── State ── */
const S = {
  session: null,          // { token, userId, username } | null (guest)
  isGuest: false,
  boards: [],             // [{ id, name, columns:[{id,name,cards:[...]}] }]
  activeBoardId: null,
  editingCardId: null,
  editingColId: null,
  dragCard: null,         // { cardId, colId, boardId }
  colChips: ['To Do', 'In Progress', 'Done'],
};

/* ── Themes ── */
const THEMES = {
  classic:  { name: 'Classic',                swatch: '#ccffcc', vars: { '--brand': '#ccffcc', '--brand-dark': '#22a85a', '--brand-mid': '#a8f0b8', '--brand-border': 'rgba(34,168,90,0.25)',   '--bg': '#f5fdf7', '--bg-col': 'rgba(204,255,204,0.28)', '--border': 'rgba(34,168,90,0.18)',  '--border-strong': 'rgba(34,168,90,0.32)',  '--text': '#1a2e22', '--text-2': '#4a6855', '--text-3': '#7a9e84', '--brand-rgb': '34,168,90',   '--brand-tint-rgb': '204,255,204' } },
  pink:     { name: 'Not green 1 (#ffcccc)',  swatch: '#ffcccc', vars: { '--brand': '#ffcccc', '--brand-dark': '#cc3344', '--brand-mid': '#f0a8b0', '--brand-border': 'rgba(204,51,68,0.25)',  '--bg': '#fdf5f5', '--bg-col': 'rgba(255,204,204,0.28)', '--border': 'rgba(204,51,68,0.18)', '--border-strong': 'rgba(204,51,68,0.32)', '--text': '#2e1a1a', '--text-2': '#684a4a', '--text-3': '#9e7a7a', '--brand-rgb': '204,51,68',   '--brand-tint-rgb': '255,204,204' } },
  blue:     { name: 'Not green 2 (#ccccff)',  swatch: '#ccccff', vars: { '--brand': '#ccccff', '--brand-dark': '#5544cc', '--brand-mid': '#a8a8f0', '--brand-border': 'rgba(85,68,204,0.25)',  '--bg': '#f5f5fd', '--bg-col': 'rgba(204,204,255,0.28)', '--border': 'rgba(85,68,204,0.18)', '--border-strong': 'rgba(85,68,204,0.32)', '--text': '#1a1a2e', '--text-2': '#4a4a68', '--text-3': '#7a7a9e', '--brand-rgb': '85,68,204',   '--brand-tint-rgb': '204,204,255' } },
  yellow:   { name: 'Not green 3 (#ffffcc)',  swatch: '#ffffcc', vars: { '--brand': '#ffffcc', '--brand-dark': '#aa8800', '--brand-mid': '#f0f0a8', '--brand-border': 'rgba(170,136,0,0.25)', '--bg': '#fdfdf5', '--bg-col': 'rgba(255,255,204,0.28)', '--border': 'rgba(170,136,0,0.18)','--border-strong': 'rgba(170,136,0,0.32)','--text': '#2e2a1a', '--text-2': '#68624a', '--text-3': '#9e987a', '--brand-rgb': '170,136,0',   '--brand-tint-rgb': '255,255,204' } },
  magenta:  { name: 'Not green 4 (#ffccff)',  swatch: '#ffccff', vars: { '--brand': '#ffccff', '--brand-dark': '#aa33aa', '--brand-mid': '#f0a8f0', '--brand-border': 'rgba(170,51,170,0.25)', '--bg': '#fdf5fd', '--bg-col': 'rgba(255,204,255,0.28)', '--border': 'rgba(170,51,170,0.18)','--border-strong': 'rgba(170,51,170,0.32)','--text': '#2e1a2e', '--text-2': '#684a68', '--text-3': '#9e7a9e', '--brand-rgb': '170,51,170',  '--brand-tint-rgb': '255,204,255' } },
  cyan:     { name: 'Not green 5 (#ccffff)',  swatch: '#ccffff', vars: { '--brand': '#ccffff', '--brand-dark': '#0099aa', '--brand-mid': '#a8f0f0', '--brand-border': 'rgba(0,153,170,0.25)',  '--bg': '#f5fdfd', '--bg-col': 'rgba(204,255,255,0.28)', '--border': 'rgba(0,153,170,0.18)', '--border-strong': 'rgba(0,153,170,0.32)', '--text': '#1a2a2e', '--text-2': '#4a6268', '--text-3': '#7a989e', '--brand-rgb': '0,153,170',   '--brand-tint-rgb': '204,255,255' } },
  white:    { name: 'Really really light green (#ffffff)', swatch: '#f0f0f0', vars: { '--brand': '#f0f0f0', '--brand-dark': '#666666', '--brand-mid': '#e0e0e0', '--brand-border': 'rgba(100,100,100,0.25)', '--bg': '#f8f8f8', '--bg-col': 'rgba(235,235,235,0.28)', '--border': 'rgba(100,100,100,0.18)', '--border-strong': 'rgba(100,100,100,0.32)', '--text': '#2a2a2a', '--text-2': '#555555', '--text-3': '#888888', '--brand-rgb': '100,100,100', '--brand-tint-rgb': '235,235,235' } },
};

function applyTheme(key) {
  const theme = THEMES[key] || THEMES.classic;
  const root = document.documentElement;
  Object.entries(theme.vars).forEach(([k, v]) => root.style.setProperty(k, v));

  localStorage.setItem('uwuboard_theme', key);
  S.theme = key;
}

/* ── Apply saved theme immediately ── */
applyTheme(localStorage.getItem('uwuboard_theme') || 'classic');

/* ── Utils ── */
const $ = id => document.getElementById(id);
const uid = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36);

function toast(msg, type = 'success') {
  const c = $('toast-container');
  const t = document.createElement('div');
  t.className = `toast ${type}`;
  t.textContent = msg;
  c.appendChild(t);
  setTimeout(() => { t.classList.add('out'); setTimeout(() => t.remove(), 250); }, 3000);
}

function showError(id, msg) {
  const el = $(id);
  el.textContent = msg;
  el.classList.remove('hidden');
}

function clearError(id) { $(id).classList.add('hidden'); }

function hexToRgb(hex) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return `${r},${g},${b}`;
}

function resizeImage(file, maxW = 1920) {
  return new Promise(resolve => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      URL.revokeObjectURL(url);
      let { width, height } = img;
      if (width > maxW) { height = Math.round(height * maxW / width); width = maxW; }
      const canvas = document.createElement('canvas');
      canvas.width = width; canvas.height = height;
      canvas.getContext('2d').drawImage(img, 0, 0, width, height);
      // Prefer WebP (25-35% smaller than JPEG at same visual quality); fall back to PNG for lossless
      const useWebP = canvas.toDataURL('image/webp').startsWith('data:image/webp');
      resolve(useWebP ? canvas.toDataURL('image/webp', 0.92) : canvas.toDataURL('image/png'));
    };
    img.src = url;
  });
}

function isDark(hex) {
  const r = parseInt(hex.slice(1, 3), 16);
  const g = parseInt(hex.slice(3, 5), 16);
  const b = parseInt(hex.slice(5, 7), 16);
  return (r * 0.299 + g * 0.587 + b * 0.114) < 140;
}

/* ── API helpers ── */
async function api(method, path, body) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (S.session?.token) opts.headers['Authorization'] = `Bearer ${S.session.token}`;
  if (body) opts.body = JSON.stringify(body);
  const res = await fetch(`/api${path}`, opts);
  const data = await res.json();
  if (!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

/* ── Local storage (guest) ── */
const LS_BOARDS = 'kanbanflow_guest_boards';
function saveGuest() {
  if (S.isGuest) localStorage.setItem(LS_BOARDS, JSON.stringify(S.boards));
}
function loadGuest() {
  try { return JSON.parse(localStorage.getItem(LS_BOARDS)) || []; } catch { return []; }
}

/* ── Auth ── */
function updateSidebarAvatar() {
  const el = $('user-avatar');
  if (!el) return;
  const key = S.session?.userId;
  const saved = key && localStorage.getItem('uwuboard_avatar_' + key);
  if (saved) {
    el.innerHTML = `<img src="${saved}" alt="" style="width:100%;height:100%;object-fit:cover;border-radius:50%;display:block;" />`;
  } else if (!S.isGuest && S.session) {
    el.textContent = ($('user-name').textContent || 'U')[0].toUpperCase();
  } else {
    el.textContent = 'G';
  }
}

function setSession(session, username, displayName) {
  S.session = session;
  S.username = username;
  S.isGuest = false;
  const shown = displayName || username;
  localStorage.setItem('uwuboard_session', JSON.stringify({ session, username, displayName: shown }));
  $('user-name').textContent = shown;
  $('user-role').textContent = 'Signed in';
  $('user-avatar').textContent = shown[0].toUpperCase();
  $('auth-overlay').classList.add('hidden');
  $('app').classList.remove('hidden');
  updateSidebarAvatar();
}

function setGuest() {
  S.session = null;
  S.isGuest = true;
  $('user-name').textContent = 'Guest';
  $('user-role').textContent = 'Guest session';
  $('user-avatar').textContent = 'G';
  $('auth-overlay').classList.add('hidden');
  $('app').classList.remove('hidden');
  S.boards = loadGuest();
  renderBoardList();
  if (S.boards.length) selectBoard(S.boards[0].id);
}

function logout() {
  if (!S.isGuest && S.session) {
    fetch('/api/auth/logout', { method: 'POST', headers: { 'Authorization': `Bearer ${S.session.token}` } }).catch(() => {});
  }
  localStorage.removeItem('uwuboard_session');
  S.session = null;
  S.isGuest = false;
  S.boards = [];
  S.activeBoardId = null;
  $('app').classList.add('hidden');
  $('auth-overlay').classList.remove('hidden');
  $('board-title').textContent = 'Select a board';
  $('columns-container').classList.add('hidden');
  $('empty-state').classList.remove('hidden');
  renderBoardList();
}

/* ── Password visibility toggle ── */
document.querySelectorAll('.pass-eye').forEach(btn => {
  btn.addEventListener('click', () => {
    const input = $(btn.dataset.target);
    const showing = input.type === 'text';
    input.type = showing ? 'password' : 'text';
    btn.querySelector('.eye-show').style.display = showing ? '' : 'none';
    btn.querySelector('.eye-hide').style.display = showing ? 'none' : '';
  });
});

/* ── Tab switching ── */
document.querySelectorAll('.tab-btn').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.tab-pane').forEach(p => p.classList.add('hidden'));
    btn.classList.add('active');
    $(`tab-${btn.dataset.tab}`).classList.remove('hidden');
  });
});

/* ── Login ── */
$('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const user = $('login-user').value.trim();
  const pass = $('login-pass').value;
  clearError('login-error');
  if (!user || !pass) return showError('login-error', 'Please fill in all fields.');
  try {
    const data = await api('POST', '/auth/login', { username: user, password: pass });
    if (window.PasswordCredential) {
      const cred = new PasswordCredential({ id: user, password: pass });
      navigator.credentials.store(cred).catch(() => {});
    }
    setSession(data.session, data.username, data.displayName);
    await loadUserBoards();
  } catch (e) { showError('login-error', e.message); }
});

/* ── Register ── */
$('register-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const user = $('reg-user').value.trim();
  const email = $('reg-email').value.trim();
  const pass = $('reg-pass').value;
  clearError('reg-error');
  if (!user || !email || !pass) return showError('reg-error', 'Please fill in all fields.');
  if (pass.length < 8) return showError('reg-error', 'Password must be at least 8 characters.');
  try {
    const data = await api('POST', '/auth/register', { username: user, email, password: pass });
    if (window.PasswordCredential) {
      const cred = new PasswordCredential({ id: user, password: pass });
      navigator.credentials.store(cred).catch(() => {});
    }
    setSession(data.session, data.username, data.displayName);
    await loadUserBoards();
  } catch (e) { showError('reg-error', e.message); }
});

/* ── Guest ── */
$('guest-btn').addEventListener('click', setGuest);
$('logout-btn').addEventListener('click', logout);

/* ── Enter key shortcuts ── */
$('reg-pass').addEventListener('keydown', e => { if (e.key === 'Enter') $('register-form').requestSubmit(); });

/* ── Guest file import ── */
setupFileImport($('guest-import-file'), $('guest-import-zone'), json => {
  importBoardFromJSON(json, true);
});

/* ── Boards ── */
async function loadUserBoards() {
  if (S.isGuest) return;
  try {
    const data = await api('GET', '/boards/list');
    S.boards = data.boards;
    renderBoardList();
    if (S.boards.length) selectBoard(S.boards[0].id);
  } catch (e) { toast('Failed to load boards', 'error'); }
}

function renderBoardList() {
  const list = $('board-list');
  list.innerHTML = '';
  S.boards.forEach(b => {
    const el = document.createElement('div');
    el.className = 'board-item' + (b.id === S.activeBoardId ? ' active' : '');
    el.dataset.id = b.id;
    el.innerHTML = `<span class="board-dot"></span><span>${esc(b.name)}</span>`;
    el.addEventListener('click', () => selectBoard(b.id));
    list.appendChild(el);
  });
}

function selectBoard(id) {
  S.activeBoardId = id;
  const board = S.boards.find(b => b.id === id);
  if (!board) return;
  $('board-title').textContent = board.name;
  $('edit-board-title-btn').classList.remove('hidden');
  $('board-export-btn').classList.remove('hidden');
  $('board-import-btn').classList.remove('hidden');
  $('add-col-btn').classList.remove('hidden');
  $('delete-board-btn').classList.remove('hidden');
  $('empty-state').classList.add('hidden');
  $('columns-container').classList.remove('hidden');
  renderBoardList();
  renderBoard(board);
}

function getActiveBoard() { return S.boards.find(b => b.id === S.activeBoardId); }

/* ── Render board ── */
function renderBoard(board) {
  const container = $('columns-container');
  container.innerHTML = '';
  board.columns.forEach(col => container.appendChild(buildColumn(col, board.id)));
}

function buildColumn(col, boardId) {
  const el = document.createElement('div');
  el.className = 'column';
  el.dataset.colId = col.id;

  el.innerHTML = `
    <div class="column-header">
      <div class="col-title-wrap">
        <span class="col-title">${esc(col.name)}</span>
        <span class="col-count">${col.cards.length}</span>
      </div>
      <button class="icon-btn col-menu-btn" title="Column options">
        <svg width="14" height="14" viewBox="0 0 14 14"><circle cx="7" cy="2" r="1.2" fill="currentColor"/><circle cx="7" cy="7" r="1.2" fill="currentColor"/><circle cx="7" cy="12" r="1.2" fill="currentColor"/></svg>
      </button>
    </div>
    <div class="cards-list" data-col-id="${col.id}"></div>
    <button class="add-card-btn">
      <svg width="12" height="12" viewBox="0 0 12 12"><path d="M6 1v10M1 6h10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
      Add card
    </button>
  `;

  const cardsList = el.querySelector('.cards-list');
  col.cards.forEach(card => cardsList.appendChild(buildCard(card, col.id)));

  el.querySelector('.add-card-btn').addEventListener('click', () => openInlineAdd(col.id, cardsList, el));
  el.querySelector('.col-menu-btn').addEventListener('click', () => openRenameColModal(col));

  setupColDrop(cardsList, col.id);
  return el;
}

function buildCard(card, colId) {
  const el = document.createElement('div');
  el.className = 'card';
  el.dataset.cardId = card.id;
  el.draggable = true;

  let labelsHtml = '';
  if (card.labels?.length) {
    labelsHtml = `<div class="card-labels">${card.labels.map(l => {
      const rgb = hexToRgb(l.color);
      const textClr = isDark(l.color) ? '#fff' : '#1a2e22';
      return `<span class="card-label" style="background:rgba(${rgb},0.2);border-color:rgba(${rgb},0.4);color:${textClr}">${esc(l.text)}</span>`;
    }).join('')}</div>`;
  }

  let metaHtml = '';
  if (card.due || card.priority) {
    let dueHtml = '';
    if (card.due) {
      const d = new Date(card.due), now = new Date();
      const diff = (d - now) / 86400000;
      const cls = diff < 0 ? 'overdue' : diff < 2 ? 'soon' : '';
      dueHtml = `<span class="card-due ${cls}">
        <svg width="10" height="10" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" stroke="currentColor" fill="none" stroke-width="1.2"/><path d="M5 3v2.5l1.5 1" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>
        ${card.due}
      </span>`;
    }
    let prioHtml = card.priority ? `<span class="card-priority priority-${card.priority}">${card.priority}</span>` : '';
    metaHtml = `<div class="card-meta">${dueHtml}${prioHtml}</div>`;
  }

  let checkHtml = '';
  if (card.checklist?.length) {
    const done = card.checklist.filter(c => c.done).length;
    const pct = Math.round((done / card.checklist.length) * 100);
    checkHtml = `<div class="card-checklist-bar">
      <div class="check-progress"><div class="check-fill" style="width:${pct}%"></div></div>
      <span class="check-text">${done}/${card.checklist.length}</span>
    </div>`;
  }

  let thumbnailHtml = '';
  if (card.images?.length) {
    const thumb = card.images.find(i => i.id === card.thumbnailId) || card.images[0];
    thumbnailHtml = `<div class="card-thumb"><img src="${thumb.url || thumb.data}" alt="" /></div>`;
  }
  el.innerHTML = `${thumbnailHtml}${labelsHtml}<div class="card-title">${esc(card.title)}</div>${metaHtml}${checkHtml}`;
  el.addEventListener('click', () => openCardModal(card.id, colId));
  el.addEventListener('dragstart', e => {
    S.dragCard = { cardId: card.id, colId };
    el.classList.add('dragging');
    e.dataTransfer.effectAllowed = 'move';
  });
  el.addEventListener('dragend', () => el.classList.remove('dragging'));
  return el;
}

/* ── Inline add card ── */
function openInlineAdd(colId, cardsList, colEl) {
  const existing = colEl.querySelector('.inline-add-card');
  if (existing) { existing.querySelector('textarea').focus(); return; }

  const zone = document.createElement('div');
  zone.className = 'inline-add-card';
  zone.innerHTML = `
    <textarea placeholder="Card title…" rows="2"></textarea>
    <div class="inline-add-actions">
      <button class="btn-primary small">Add</button>
      <button class="btn-ghost small">Cancel</button>
    </div>`;

  const ta = zone.querySelector('textarea');
  zone.querySelectorAll('button')[0].addEventListener('click', () => {
    const title = ta.value.trim();
    if (!title) return;
    addCard(colId, title);
    zone.remove();
  });
  zone.querySelectorAll('button')[1].addEventListener('click', () => zone.remove());
  ta.addEventListener('keydown', e => {
    if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); zone.querySelectorAll('button')[0].click(); }
    if (e.key === 'Escape') zone.remove();
  });

  colEl.insertBefore(zone, colEl.querySelector('.add-card-btn'));
  ta.focus();
}

/* ── Add card ── */
async function addCard(colId, title) {
  const board = getActiveBoard();
  if (!board) return;
  const col = board.columns.find(c => c.id === colId);
  if (!col) return;
  const card = { id: uid(), title, description: '', labels: [], checklist: [], due: '', priority: '', images: [], thumbnailId: null };
  col.cards.push(card);

  if (!S.isGuest) {
    try { await api('PUT', `/boards/update`, { board }); }
    catch (e) { toast('Sync error', 'error'); }
  } else { saveGuest(); }

  renderBoard(board);
}

/* ── Drag & drop ── */
function setupColDrop(cardsList, colId) {
  cardsList.addEventListener('dragover', e => {
    e.preventDefault();
    e.dataTransfer.dropEffect = 'move';
    cardsList.classList.add('drag-over');

    const afterEl = getDragAfterEl(cardsList, e.clientY);
    let placeholder = cardsList.querySelector('.drag-placeholder');
    if (!placeholder) { placeholder = document.createElement('div'); placeholder.className = 'drag-placeholder'; }
    if (afterEl) cardsList.insertBefore(placeholder, afterEl);
    else cardsList.appendChild(placeholder);
  });

  cardsList.addEventListener('dragleave', e => {
    if (!cardsList.contains(e.relatedTarget)) {
      cardsList.classList.remove('drag-over');
      cardsList.querySelector('.drag-placeholder')?.remove();
    }
  });

  cardsList.addEventListener('drop', e => {
    e.preventDefault();
    cardsList.classList.remove('drag-over');
    cardsList.querySelector('.drag-placeholder')?.remove();
    if (!S.dragCard) return;

    const board = getActiveBoard();
    const srcCol = board.columns.find(c => c.id === S.dragCard.colId);
    const dstCol = board.columns.find(c => c.id === colId);
    if (!srcCol || !dstCol) return;

    const cardIdx = srcCol.cards.findIndex(c => c.id === S.dragCard.cardId);
    if (cardIdx === -1) return;
    const [card] = srcCol.cards.splice(cardIdx, 1);

    const afterEl = getDragAfterEl(cardsList, e.clientY);
    if (!afterEl) {
      dstCol.cards.push(card);
    } else {
      const afterId = afterEl.dataset.cardId;
      const insertAt = dstCol.cards.findIndex(c => c.id === afterId);
      dstCol.cards.splice(insertAt, 0, card);
    }

    S.dragCard = null;
    persistBoard(board);
    renderBoard(board);
  });
}

function getDragAfterEl(container, y) {
  const els = [...container.querySelectorAll('.card:not(.dragging)')];
  return els.reduce((closest, el) => {
    const box = el.getBoundingClientRect();
    const offset = y - box.top - box.height / 2;
    if (offset < 0 && offset > closest.offset) return { offset, el };
    return closest;
  }, { offset: -Infinity }).el;
}

/* ── Card modal ── */
function openCardModal(cardId, colId) {
  const board = getActiveBoard();
  const col = board.columns.find(c => c.id === colId);
  const card = col?.cards.find(c => c.id === cardId);
  if (!card) return;

  S.editingCardId = cardId;
  S.editingColId = colId;

  $('card-modal-title').value = card.title;
  $('card-modal-desc').value = card.description || '';
  $('card-modal-due').value = card.due || '';
  $('card-modal-priority').value = card.priority || '';

  $('card-modal-col').value = colId;
  $('card-modal-col-label').textContent = col?.name || '—';

  renderCardImages(card);
  renderModalLabels(card.labels || []);
  renderChecklist(card.checklist || []);

  $('card-modal').classList.remove('hidden');
}

function renderModalLabels(labels) {
  const c = $('card-modal-labels');
  c.innerHTML = '';
  labels.forEach((l, i) => {
    const chip = document.createElement('div');
    chip.className = 'label-chip';
    const rgb = hexToRgb(l.color);
    const textClr = isDark(l.color) ? '#fff' : '#1a2e22';
    chip.style.cssText = `background:rgba(${rgb},0.2);border-color:rgba(${rgb},0.4);color:${textClr}`;
    chip.innerHTML = `${esc(l.text)}<button data-i="${i}" title="Remove">×</button>`;
    chip.querySelector('button').addEventListener('click', () => {
      const board = getActiveBoard();
      const col = board.columns.find(c => c.id === S.editingColId);
      const card = col?.cards.find(c => c.id === S.editingCardId);
      if (card) { card.labels.splice(i, 1); renderModalLabels(card.labels); }
    });
    c.appendChild(chip);
  });
}

function renderChecklist(items) {
  const c = $('card-checklist');
  c.innerHTML = '';
  items.forEach((item, i) => {
    const row = document.createElement('div');
    row.className = 'check-item';
    row.innerHTML = `
      <input type="checkbox" ${item.done ? 'checked' : ''} data-i="${i}" />
      <span class="${item.done ? 'done' : ''}">${esc(item.text)}</span>
      <button class="del-check" data-i="${i}" title="Remove">×</button>`;
    row.querySelector('input').addEventListener('change', e => {
      const board = getActiveBoard();
      const col = board.columns.find(c => c.id === S.editingColId);
      const card = col?.cards.find(c => c.id === S.editingCardId);
      if (card) { card.checklist[i].done = e.target.checked; renderChecklist(card.checklist); }
    });
    row.querySelector('.del-check').addEventListener('click', () => {
      const board = getActiveBoard();
      const col = board.columns.find(c => c.id === S.editingColId);
      const card = col?.cards.find(c => c.id === S.editingCardId);
      if (card) { card.checklist.splice(i, 1); renderChecklist(card.checklist); }
    });
    c.appendChild(row);
  });
}

$('add-label-btn').addEventListener('click', () => {
  const text = $('new-label-input').value.trim();
  const color = $('new-label-color').value;
  if (!text) return;
  const board = getActiveBoard();
  const col = board.columns.find(c => c.id === S.editingColId);
  const card = col?.cards.find(c => c.id === S.editingCardId);
  if (!card) return;
  if (!card.labels) card.labels = [];
  card.labels.push({ text, color });
  $('new-label-input').value = '';
  renderModalLabels(card.labels);
});

$('add-check-btn').addEventListener('click', () => {
  const text = $('new-check-input').value.trim();
  if (!text) return;
  const board = getActiveBoard();
  const col = board.columns.find(c => c.id === S.editingColId);
  const card = col?.cards.find(c => c.id === S.editingCardId);
  if (!card) return;
  if (!card.checklist) card.checklist = [];
  card.checklist.push({ text, done: false });
  $('new-check-input').value = '';
  renderChecklist(card.checklist);
});

$('new-check-input').addEventListener('keydown', e => { if (e.key === 'Enter') $('add-check-btn').click(); });
$('new-label-input').addEventListener('keydown', e => { if (e.key === 'Enter') $('add-label-btn').click(); });

$('save-card-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  const col = board.columns.find(c => c.id === S.editingColId);
  const card = col?.cards.find(c => c.id === S.editingCardId);
  if (!card) return;

  card.title = $('card-modal-title').value.trim() || card.title;
  card.description = $('card-modal-desc').value;
  card.due = $('card-modal-due').value;
  card.priority = $('card-modal-priority').value;

  const targetColId = $('card-modal-col').value;
  if (targetColId && targetColId !== S.editingColId) {
    const targetCol = board.columns.find(c => c.id === targetColId);
    if (targetCol) {
      col.cards = col.cards.filter(c => c.id !== S.editingCardId);
      targetCol.cards.push(card);
    }
  }

  closeCardModal();
  persistBoard(board);
  renderBoard(board);
  toast('Card saved');
});

$('delete-card-btn').addEventListener('click', () => {
  if (!confirm('Delete this card?')) return;
  const board = getActiveBoard();
  const col = board.columns.find(c => c.id === S.editingColId);
  if (!col) return;
  col.cards = col.cards.filter(c => c.id !== S.editingCardId);
  closeCardModal();
  persistBoard(board);
  renderBoard(board);
  toast('Card deleted');
});

$('card-modal-close').addEventListener('click', closeCardModal);
$('card-modal').addEventListener('click', e => { if (e.target === $('card-modal')) closeCardModal(); });

/* ── Column picker ── */
$('card-modal-col-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  if (!board) return;
  const currentColId = $('card-modal-col').value;
  const list = $('col-picker-list');
  list.innerHTML = '';
  board.columns.forEach(col => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'col-picker-item' + (col.id === currentColId ? ' active' : '');
    btn.textContent = col.name;
    btn.addEventListener('click', () => {
      $('card-modal-col').value = col.id;
      $('card-modal-col-label').textContent = col.name;
      $('col-picker-sheet').classList.add('hidden');
    });
    list.appendChild(btn);
  });
  $('col-picker-sheet').classList.remove('hidden');
});

$('col-picker-close').addEventListener('click', () => $('col-picker-sheet').classList.add('hidden'));
$('col-picker-sheet').addEventListener('click', e => { if (e.target === $('col-picker-sheet')) $('col-picker-sheet').classList.add('hidden'); });

function closeCardModal() { $('card-modal').classList.add('hidden'); }

/* ── Card images ── */
function renderCardImages(card) {
  if (!card.images) card.images = [];
  const grid = $('card-images-grid');
  grid.innerHTML = '';
  card.images.forEach(img => {
    const thumbId = card.thumbnailId || card.images[0]?.id;
    const isThumb = img.id === thumbId;
    const src = img.url || img.data;
    const item = document.createElement('div');
    item.className = 'card-img-item' + (isThumb ? ' is-thumb' : '');
    item.innerHTML = `
      <img src="${src}" alt="${esc(img.name)}" />
      <div class="img-actions">
        <button type="button" class="img-action-btn${isThumb ? ' active' : ''}" title="${isThumb ? 'Thumbnail' : 'Set as thumbnail'}">
          <svg width="11" height="11" viewBox="0 0 11 11"><path d="M5.5 1l1.2 2.4 2.8.4-2 2 .5 2.7-2.5-1.4L3 8.5l.5-2.7-2-2 2.8-.4z" fill="currentColor"/></svg>
          ${isThumb ? 'Thumbnail' : 'Set thumb'}
        </button>
        <button type="button" class="img-action-btn del-img-btn" title="Delete">✕ Delete</button>
      </div>`;
    item.querySelector('.img-action-btn:not(.del-img-btn)').addEventListener('click', () => {
      card.thumbnailId = img.id;
      renderCardImages(card);
    });
    item.querySelector('.del-img-btn').addEventListener('click', async () => {
      if (!S.isGuest && img.path) {
        try { await api('DELETE', '/images/delete', { path: img.path }); } catch { toast('Could not delete image from storage', 'error'); }
      }
      card.images = card.images.filter(i => i.id !== img.id);
      if (card.thumbnailId === img.id) card.thumbnailId = card.images[0]?.id ?? null;
      renderCardImages(card);
    });
    grid.appendChild(item);
  });
}

$('card-img-input').addEventListener('change', async e => {
  const files = [...e.target.files];
  if (!files.length) return;
  const board = getActiveBoard();
  const col = board?.columns.find(c => c.id === S.editingColId);
  const card = col?.cards.find(c => c.id === S.editingCardId);
  if (!card) return;
  if (!card.images) card.images = [];
  for (const file of files) {
    const imageData = await resizeImage(file);
    if (S.isGuest) {
      card.images.push({ id: uid(), data: imageData, name: file.name });
    } else {
      try {
        const result = await api('POST', '/images/upload', { imageData, fileName: file.name });
        card.images.push({ id: uid(), url: result.url, path: result.path, name: file.name });
      } catch { toast('Image upload failed', 'error'); }
    }
  }
  if (!card.thumbnailId && card.images.length) card.thumbnailId = card.images[0].id;
  renderCardImages(card);
  e.target.value = '';
});

/* ── Rename/delete column modal ── */
function openRenameColModal(col) {
  S.editingColId = col.id;
  $('rename-col-input').value = col.name;
  $('rename-col-modal').classList.remove('hidden');
}

$('save-col-name-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  const col = board.columns.find(c => c.id === S.editingColId);
  if (!col) return;
  col.name = $('rename-col-input').value.trim() || col.name;
  $('rename-col-modal').classList.add('hidden');
  persistBoard(board);
  renderBoard(board);
});

$('delete-col-btn').addEventListener('click', () => {
  if (!confirm('Delete this column and all its cards?')) return;
  const board = getActiveBoard();
  board.columns = board.columns.filter(c => c.id !== S.editingColId);
  $('rename-col-modal').classList.add('hidden');
  persistBoard(board);
  renderBoard(board);
  toast('Column deleted');
});

$('rename-col-close').addEventListener('click', () => $('rename-col-modal').classList.add('hidden'));
$('rename-col-modal').addEventListener('click', e => { if (e.target === $('rename-col-modal')) $('rename-col-modal').classList.add('hidden'); });

/* ── Add column ── */
$('add-col-btn').addEventListener('click', () => {
  const name = prompt('Column name:');
  if (!name?.trim()) return;
  const board = getActiveBoard();
  board.columns.push({ id: uid(), name: name.trim(), cards: [] });
  persistBoard(board);
  renderBoard(board);
});

/* ── New board modal ── */
$('new-board-btn').addEventListener('click', openNewBoardModal);
$('empty-new-board-btn').addEventListener('click', openNewBoardModal);

function openNewBoardModal() {
  S.colChips = ['To Do', 'In Progress', 'Done'];
  renderColChips();
  $('new-board-name').value = '';
  $('new-board-modal').classList.remove('hidden');
  setTimeout(() => $('new-board-name').focus(), 50);
}

function renderColChips() {
  const container = $('new-board-cols');
  container.innerHTML = '';
  S.colChips.forEach((name, i) => {
    const chip = document.createElement('span');
    chip.className = 'col-chip removable';
    chip.textContent = name;
    chip.addEventListener('click', () => {
      S.colChips.splice(i, 1);
      renderColChips();
    });
    container.appendChild(chip);
  });
  const addBtn = document.createElement('button');
  addBtn.className = 'btn-ghost small';
  addBtn.id = 'add-default-col-btn';
  addBtn.textContent = '+ Add';
  addBtn.addEventListener('click', () => {
    const inp = $('new-col-chip-input');
    inp.classList.toggle('hidden');
    if (!inp.classList.contains('hidden')) inp.focus();
  });
  container.appendChild(addBtn);
}

$('new-col-chip-input').addEventListener('keydown', e => {
  if (e.key === 'Enter') {
    const v = e.target.value.trim();
    if (v) { S.colChips.push(v); e.target.value = ''; e.target.classList.add('hidden'); renderColChips(); }
  }
  if (e.key === 'Escape') { e.target.value = ''; e.target.classList.add('hidden'); }
});

$('create-board-btn').addEventListener('click', async () => {
  const name = $('new-board-name').value.trim();
  if (!name) return;
  const board = {
    id: uid(),
    name,
    columns: S.colChips.map(n => ({ id: uid(), name: n, cards: [] })),
  };
  S.boards.push(board);

  if (!S.isGuest) {
    try { await api('POST', '/boards/create', { board }); }
    catch (e) { toast('Save error', 'error'); }
  } else { saveGuest(); }

  $('new-board-modal').classList.add('hidden');
  renderBoardList();
  selectBoard(board.id);
  toast(`Board "${name}" created`);
});

$('new-board-cancel').addEventListener('click', () => $('new-board-modal').classList.add('hidden'));
$('new-board-modal-close').addEventListener('click', () => $('new-board-modal').classList.add('hidden'));
$('new-board-modal').addEventListener('click', e => { if (e.target === $('new-board-modal')) $('new-board-modal').classList.add('hidden'); });

/* ── Rename board ── */
$('edit-board-title-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  if (!board) return;
  const name = prompt('Board name:', board.name);
  if (!name?.trim()) return;
  board.name = name.trim();
  $('board-title').textContent = board.name;
  persistBoard(board);
  renderBoardList();
});

/* ── Delete board ── */
$('delete-board-btn').addEventListener('click', async () => {
  const board = getActiveBoard();
  if (!board || !confirm(`Delete board "${board.name}"?`)) return;

  if (!S.isGuest) {
    try { await api('DELETE', '/boards/delete', { boardId: board.id }); }
    catch (e) { toast('Delete error', 'error'); }
  }

  S.boards = S.boards.filter(b => b.id !== board.id);
  S.activeBoardId = null;
  saveGuest();
  renderBoardList();
  $('board-title').textContent = 'Select a board';
  $('columns-container').classList.add('hidden');
  $('empty-state').classList.remove('hidden');
  $('edit-board-title-btn').classList.add('hidden');
  $('board-export-btn').classList.add('hidden');
  $('board-import-btn').classList.add('hidden');
  $('add-col-btn').classList.add('hidden');
  $('delete-board-btn').classList.add('hidden');
  toast('Board deleted');
  if (S.boards.length) selectBoard(S.boards[0].id);
});

/* ── Export / Import ── */
$('board-export-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  if (!board) return;
  const blob = new Blob([JSON.stringify(board, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `${board.name.replace(/\s+/g, '_')}_kanban.json`;
  a.click();
  toast('Board exported');
});

$('board-import-btn').addEventListener('click', () => $('board-import-file').click());
setupFileImport($('board-import-file'), null, json => importBoardFromJSON(json, false));

function setupFileImport(input, dropZone, callback) {
  input?.addEventListener('change', e => {
    const file = e.target.files[0];
    if (!file) return;
    readJSON(file, callback);
    input.value = '';
  });

  if (dropZone) {
    dropZone.addEventListener('dragover', e => { e.preventDefault(); dropZone.classList.add('drag-over'); });
    dropZone.addEventListener('dragleave', () => dropZone.classList.remove('drag-over'));
    dropZone.addEventListener('drop', e => {
      e.preventDefault();
      dropZone.classList.remove('drag-over');
      const file = e.dataTransfer.files[0];
      if (file) readJSON(file, callback);
    });
  }
}

function readJSON(file, callback) {
  const reader = new FileReader();
  reader.onload = e => {
    try {
      const json = JSON.parse(e.target.result);
      callback(json);
    } catch { toast('Invalid JSON file', 'error'); }
  };
  reader.readAsText(file);
}

function importBoardFromJSON(json, asNew) {
  if (!json.id || !json.name || !Array.isArray(json.columns)) {
    toast('Invalid board file', 'error');
    return;
  }
  if (asNew || !S.activeBoardId) {
    json.id = uid();
    S.boards.push(json);
  } else {
    const idx = S.boards.findIndex(b => b.id === S.activeBoardId);
    if (idx !== -1) S.boards[idx] = json;
  }
  saveGuest();
  if (!S.isGuest) persistBoard(json).catch(() => {});
  renderBoardList();
  selectBoard(json.id);
  toast('Board imported');
}

/* ── Persist board ── */
async function persistBoard(board) {
  if (S.isGuest) { saveGuest(); return; }
  try {
    await api('PUT', '/boards/update', { board });
  } catch (e) { toast('Sync error', 'error'); }
}

/* ── Sidebar toggle ── */
$('sidebar-toggle').addEventListener('click', () => {
  if (window.innerWidth <= 720) {
    $('sidebar').classList.remove('open');
  } else {
    $('sidebar').classList.toggle('collapsed');
  }
});

$('mobile-menu-btn').addEventListener('click', () => {
  if (window.innerWidth <= 720) {
    $('sidebar').classList.toggle('open');
  } else {
    $('sidebar').classList.toggle('collapsed');
  }
});

/* ── Escape closes modals ── */
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') {
    closeCardModal();
    $('rename-col-modal').classList.add('hidden');
    $('new-board-modal').classList.add('hidden');
    $('col-picker-sheet').classList.add('hidden');
    $('theme-picker').classList.add('hidden');
    $('profile-modal').classList.add('hidden');
    $('delete-account-modal').classList.add('hidden');
  }
});

/* ── Escape helper ── */
function esc(str) {
  return String(str ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/* ── Theme picker ── */
function openThemePicker() {
  const list = $('theme-picker-list');
  list.innerHTML = '';
  Object.entries(THEMES).forEach(([key, theme]) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'theme-option' + (key === (S.theme || 'classic') ? ' active' : '');
    btn.innerHTML = `
      <span class="theme-swatch" style="background:${theme.swatch}"></span>
      <span>${theme.name}</span>
      ${key === (S.theme || 'classic') ? '<svg class="theme-check" width="14" height="14" viewBox="0 0 14 14"><path d="M2 7l4 4 6-6" stroke="currentColor" stroke-width="1.8" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>' : ''}`;
    btn.addEventListener('click', () => {
      applyTheme(key);
      openThemePicker();
    });
    list.appendChild(btn);
  });
  $('theme-picker').classList.remove('hidden');
}

$('theme-btn').addEventListener('click', openThemePicker);
$('theme-picker-close').addEventListener('click', () => $('theme-picker').classList.add('hidden'));
$('theme-picker').addEventListener('click', e => { if (e.target === $('theme-picker')) $('theme-picker').classList.add('hidden'); });

/* ── Profile Modal ── */
function openProfileModal() {
  if (S.isGuest) { toast('Sign in to edit your profile', 'error'); return; }
  $('profile-username-display').textContent = S.username || '';
  $('profile-display-name').value = $('user-name').textContent;
  $('profile-new-pass').value = '';
  $('profile-confirm-pass').value = '';
  clearError('profile-error');
  S._pendingAvatarData = null;
  const avatarEl = $('profile-modal-avatar');
  const saved = S.session?.userId && localStorage.getItem('uwuboard_avatar_' + S.session.userId);
  if (saved) {
    avatarEl.innerHTML = `<img src="${saved}" alt="" style="width:100%;height:100%;object-fit:cover;" />`;
  } else {
    avatarEl.textContent = username[0]?.toUpperCase() || 'U';
  }
  $('profile-modal').classList.remove('hidden');
}

$('user-avatar').addEventListener('click', openProfileModal);
$('profile-modal-close').addEventListener('click', () => $('profile-modal').classList.add('hidden'));
$('profile-modal').addEventListener('click', e => { if (e.target === $('profile-modal')) $('profile-modal').classList.add('hidden'); });

$('profile-avatar-wrap').addEventListener('click', () => $('profile-pic-input').click());

$('profile-pic-input').addEventListener('change', async e => {
  const file = e.target.files[0];
  if (!file) return;
  e.target.value = '';
  const dataUrl = await resizeImage(file, 200);
  S._pendingAvatarData = dataUrl;
  const avatarEl = $('profile-modal-avatar');
  avatarEl.innerHTML = `<img src="${dataUrl}" alt="" style="width:100%;height:100%;object-fit:cover;" />`;
});

$('save-profile-btn').addEventListener('click', async () => {
  const displayName = $('profile-display-name').value.trim();
  const newPass = $('profile-new-pass').value;
  const confirmPass = $('profile-confirm-pass').value;
  clearError('profile-error');
  if (!displayName) return showError('profile-error', 'Display name cannot be empty.');
  if (!/^[a-zA-Z0-9_]{3,24}$/.test(displayName)) return showError('profile-error', 'Name must be 3–24 characters (letters, numbers, underscore).');
  if (newPass && newPass.length < 8) return showError('profile-error', 'Password must be at least 8 characters.');
  if (newPass && newPass !== confirmPass) return showError('profile-error', 'Passwords do not match.');

  const currentName = $('user-name').textContent;
  const payload = {};
  if (displayName !== currentName) payload.displayName = displayName;
  if (newPass) payload.newPassword = newPass;

  try {
    $('save-profile-btn').disabled = true;
    if (Object.keys(payload).length > 0) {
      const result = await api('PUT', '/auth/update-profile', payload);
      if (result.displayName) {
        $('user-name').textContent = result.displayName;
        const saved = JSON.parse(localStorage.getItem('uwuboard_session') || '{}');
        saved.displayName = result.displayName;
        localStorage.setItem('uwuboard_session', JSON.stringify(saved));
      }
    }
    if (S._pendingAvatarData) {
      localStorage.setItem('uwuboard_avatar_' + S.session.userId, S._pendingAvatarData);
      S._pendingAvatarData = null;
      updateSidebarAvatar();
    }
    $('profile-modal').classList.add('hidden');
    toast('Profile updated');
  } catch (e) {
    showError('profile-error', e.message);
  } finally {
    $('save-profile-btn').disabled = false;
  }
});

/* ── Delete Account ── */
function showDeleteStep(n) {
  [1, 2, 3].forEach(i => $(`delete-step-${i}`).classList.toggle('hidden', i !== n));
}

$('delete-account-btn').addEventListener('click', () => {
  $('profile-modal').classList.add('hidden');
  showDeleteStep(1);
  $('delete-account-modal').classList.remove('hidden');
});

$('delete-step1-cancel').addEventListener('click', () => $('delete-account-modal').classList.add('hidden'));
$('delete-step1-confirm').addEventListener('click', () => showDeleteStep(2));
$('delete-step2-cancel').addEventListener('click', () => $('delete-account-modal').classList.add('hidden'));
$('delete-step2-confirm').addEventListener('click', () => {
  $('delete-confirm-pass').value = '';
  clearError('delete-error');
  showDeleteStep(3);
});
$('delete-step3-cancel').addEventListener('click', () => $('delete-account-modal').classList.add('hidden'));
$('delete-step3-confirm').addEventListener('click', async () => {
  const pass = $('delete-confirm-pass').value;
  clearError('delete-error');
  if (!pass) return showError('delete-error', 'Please enter your password.');
  try {
    $('delete-step3-confirm').disabled = true;
    await api('DELETE', '/auth/delete-account', { password: pass });
    localStorage.removeItem('uwuboard_avatar_' + S.session.userId);
    $('delete-account-modal').classList.add('hidden');
    logout();
    toast('Account deleted');
  } catch (e) {
    showError('delete-error', e.message);
    $('delete-step3-confirm').disabled = false;
  }
});

/* ── Restore session on load ── */
(async () => {
  const saved = localStorage.getItem('uwuboard_session');
  if (!saved) return;
  let parsed;
  try { parsed = JSON.parse(saved); } catch { localStorage.removeItem('uwuboard_session'); return; }
  const { session, username, displayName } = parsed;
  S.session = session;
  try {
    const data = await api('GET', '/boards/list');
    setSession(session, username, displayName);
    S.boards = data.boards;
    renderBoardList();
    if (S.boards.length) selectBoard(S.boards[0].id);
  } catch {
    S.session = null;
    localStorage.removeItem('uwuboard_session');
  }
})();

/* ── PWA service worker ── */
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {});
  });
}