'use strict';

/* ── State ── */
const state = {
  session: null,          // { token, userId, username } | null (guest)
  isGuest: false,
  boards: [],             // [{ id, name, columns:[{id,name,cards:[...]}] }]
  activeBoardId: null,
  editingCardId: null,
  editingColumnId: null,
  dragCard: null,         // { cardId, columnId, boardId }
  columnChips: ['To Do', 'In Progress', 'Done'],
};

/* Theme lives in js/theme.js. */

/* ── Utils ── */
// The page element with this id (document.getElementById, shorter to read).
const elementById = (id) => {
  return document.getElementById(id);
};

// A new random id for a board, column, card or image.
const makeId = () => {
  return Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
};

// When a card, a column or a board's name was last changed. Syncing with another device
// (js/sync.js) keeps whichever copy of a thing on both was changed last.
const touch = (item) => {
  item.updatedAt = Date.now();
  return item;
};

// The card details window opening or closing, or the app appearing: js/tour.js listens.
const pageChanged = () => {
  return window.dispatchEvent(new Event('pagechange'));
};

// A short message in the corner that fades away after three seconds.
function toast(message, type = 'success') {
  const container = elementById('toast-container');
  const toastElement = document.createElement('div');
  toastElement.className = `toast ${type}`;
  toastElement.textContent = message;
  container.appendChild(toastElement);
  setTimeout(() => {
    toastElement.classList.add('out');
    setTimeout(() => {
      toastElement.remove();
    }, 250);
  }, 3000);
}

function showError(id, message) {
  const errorElement = elementById(id);
  errorElement.textContent = message;
  errorElement.classList.remove('hidden');
}

function clearError(id) {
  elementById(id).classList.add('hidden');
}

// "#rrggbb" to "red,green,blue" as three numbers from 0 to 255.
function hexToRgb(hex) {
  const red = parseInt(hex.slice(1, 3), 16);
  const green = parseInt(hex.slice(3, 5), 16);
  const blue = parseInt(hex.slice(5, 7), 16);
  return `${red},${green},${blue}`;
}

// Shrinks an image file to at most maxWidth pixels wide and hands it back as a data URL.
function resizeImage(file, maxWidth = 1920) {
  return new Promise((resolve) => {
    const image = new Image();
    const url = URL.createObjectURL(file);
    image.onload = () => {
      URL.revokeObjectURL(url);
      let { width, height } = image;
      if (width > maxWidth) {
        height = Math.round(height * maxWidth / width);
        width = maxWidth;
      }
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      canvas.getContext('2d').drawImage(image, 0, 0, width, height);
      // Prefer WebP (25-35% smaller than JPEG at same visual quality); fall back to PNG for lossless
      const useWebP = canvas.toDataURL('image/webp').startsWith('data:image/webp');
      if (useWebP) {
        resolve(canvas.toDataURL('image/webp', 0.92));
      } else {
        resolve(canvas.toDataURL('image/png'));
      }
    };
    image.src = url;
  });
}

// Whether a "#rrggbb" colour is dark enough to need white text on it.
function isDark(hex) {
  const red = parseInt(hex.slice(1, 3), 16);
  const green = parseInt(hex.slice(3, 5), 16);
  const blue = parseInt(hex.slice(5, 7), 16);
  return (red * 0.299 + green * 0.587 + blue * 0.114) < 140;
}

/* ── API helpers ── */
// Calls one of the site's /api routes with a JSON body and the session's token, and returns
// the JSON answer. A failed answer throws an Error carrying the server's message.
async function api(method, path, body) {
  const options = {
    method,
    headers: { 'Content-Type': 'application/json' },
  };
  if (state.session !== null && state.session !== undefined && state.session.token) {
    options.headers['Authorization'] = `Bearer ${state.session.token}`;
  }
  if (body) {
    options.body = JSON.stringify(body);
  }
  const response = await fetch(`/api${path}`, options);
  const data = await response.json();
  if (!response.ok) {
    let errorMessage = data.error;
    if (!errorMessage) {
      errorMessage = 'Request failed';
    }
    throw new Error(errorMessage);
  }
  return data;
}

/* ── Local storage (guest) ── */
const LOCAL_STORAGE_BOARDS = 'kanbanflow_guest_boards';
function saveGuest() {
  if (!state.isGuest) {
    return;
  }
  localStorage.setItem(LOCAL_STORAGE_BOARDS, JSON.stringify(state.boards));
  if (window.Sync !== null && window.Sync !== undefined) {
    window.Sync.changed();
  }
}
function loadGuest() {
  try {
    const boards = JSON.parse(localStorage.getItem(LOCAL_STORAGE_BOARDS));
    if (!boards) {
      return [];
    }
    return boards;
  } catch {
    return [];
  }
}

/* ── Auth ── */
// The avatar as a blob: URL from /api/auth/avatar (js/images.js), never its address. The
// initial while it loads, or when there isn't one.
function showAvatar(element, round) {
  let initial;
  if (!state.isGuest && state.session) {
    let shownName = elementById('user-name').textContent;
    if (!shownName) {
      shownName = 'U';
    }
    initial = shownName[0].toUpperCase();
  } else {
    initial = 'G';
  }
  element.textContent = initial;
  if (state.isGuest || !state.session || !state.hasAvatar) {
    return;
  }
  const session = state.session;
  ImageStore.avatar().then((url) => {
    if (state.session !== session) {
      return;
    }
    let roundStyle = '';
    if (round) {
      roundStyle = 'border-radius:50%;';
    }
    element.innerHTML = `<img src="${url}" alt="" style="width:100%;height:100%;object-fit:cover;${roundStyle}display:block;" />`;
  }, () => {});
}

function updateSidebarAvatar() {
  const avatarElement = elementById('user-avatar');
  if (avatarElement) {
    showAvatar(avatarElement, true);
  }
}

// What's kept of a session in this browser: no avatar address, just whether there is one.
function saveSession(changes) {
  let savedText = localStorage.getItem('uwuboard_session');
  if (!savedText) {
    savedText = '{}';
  }
  const saved = JSON.parse(savedText);
  delete saved.avatarUrl;
  localStorage.setItem('uwuboard_session', JSON.stringify({ ...saved, ...changes }));
}

// The app is on screen, signed in or as a guest.
function appShown() {
  elementById('auth-overlay').classList.add('hidden');
  elementById('app').classList.remove('hidden');
  Tray.show(true);
  // The tour first, while a sync link is still in the address (it skips the welcome for one).
  Tour.init();
  Sync.appShown();
  pageChanged();
}

// Signed in: keeps the session in memory and in this browser, and shows the app.
function setSession(session, username, displayName, hasAvatar) {
  state.session = session;
  state.username = username;
  state.hasAvatar = Boolean(hasAvatar);
  state.isGuest = false;
  let token;
  if (session !== null && session !== undefined) {
    token = session.token;
  } else {
    token = undefined;
  }
  ImageStore.setToken(token);
  let shown = displayName;
  if (!shown) {
    shown = username;
  }
  localStorage.setItem('uwuboard_session', JSON.stringify({ session, username, displayName: shown, hasAvatar: state.hasAvatar }));
  elementById('user-name').textContent = shown;
  elementById('user-role').textContent = 'Signed in';
  updateSidebarAvatar();
  appShown();
}

// A guest: boards come from this browser's storage.
function setGuest() {
  state.session = null;
  state.isGuest = true;
  state.hasAvatar = false;
  elementById('user-name').textContent = 'Guest';
  elementById('user-role').textContent = 'Guest session';
  elementById('user-avatar').textContent = 'G';
  state.boards = loadGuest();
  state.boardsReady = true;
  renderBoardList();
  if (state.boards.length) {
    selectBoard(state.boards[0].id);
  }
  appShown();
}

// Signs out (or leaves guest mode): tells the server, forgets everything this account had in
// memory and in the service worker's cache, and goes back to the sign-in screen.
function logout() {
  if (!state.isGuest && state.session) {
    fetch('/api/auth/logout', { method: 'POST', headers: { 'Authorization': `Bearer ${state.session.token}` } }).catch(() => {});
  }
  // Whatever was open belongs to the account going away: a sync session ends with its window.
  document.querySelectorAll('.modal-backdrop:not(.hidden)').forEach((openWindow) => {
    closeModal(openWindow.id);
  });
  Tour.end();
  localStorage.removeItem('uwuboard_session');
  state.session = null;
  state.isGuest = false;
  state.hasAvatar = false;
  state.boards = [];
  state.boardsReady = false;
  state.activeBoardId = null;
  // Nothing of this account is left for the next: its images' URLs, and the worker's copies
  // of its API answers.
  ImageStore.clear();
  const serviceWorkers = navigator.serviceWorker;
  if (serviceWorkers !== null && serviceWorkers !== undefined) {
    const controller = serviceWorkers.controller;
    if (controller !== null && controller !== undefined) {
      controller.postMessage('clear-api-cache');
    }
  }
  Tray.show(false);
  setBoardActions(false);
  elementById('app').classList.add('hidden');
  elementById('auth-overlay').classList.remove('hidden');
  elementById('board-title').textContent = 'Select a board';
  elementById('edit-board-title-btn').classList.add('hidden');
  hideBoardViews();
  elementById('empty-state').classList.remove('hidden');
  renderBoardList();
}

/* ── Password visibility toggle ── */
document.querySelectorAll('.pass-eye').forEach((button) => {
  button.addEventListener('click', () => {
    const input = elementById(button.dataset.target);
    const showing = input.type === 'text';
    if (showing) {
      input.type = 'password';
      button.querySelector('.eye-show').style.display = '';
      button.querySelector('.eye-hide').style.display = 'none';
    } else {
      input.type = 'text';
      button.querySelector('.eye-show').style.display = 'none';
      button.querySelector('.eye-hide').style.display = '';
    }
  });
});

/* ── Tab switching ── */
document.querySelectorAll('.tab-btn').forEach((button) => {
  button.addEventListener('click', () => {
    document.querySelectorAll('.tab-btn').forEach((tabButton) => {
      tabButton.classList.remove('active');
    });
    document.querySelectorAll('.tab-pane').forEach((pane) => {
      pane.classList.add('hidden');
    });
    button.classList.add('active');
    elementById(`tab-${button.dataset.tab}`).classList.remove('hidden');
  });
});

/* ── Login ── */
elementById('login-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const username = elementById('login-user').value.trim();
  const password = elementById('login-pass').value;
  clearError('login-error');
  if (!username || !password) {
    return showError('login-error', 'Please fill in all fields.');
  }
  try {
    const data = await api('POST', '/auth/login', { username: username, password: password });
    if (window.PasswordCredential) {
      const credential = new PasswordCredential({ id: username, password: password });
      navigator.credentials.store(credential).catch(() => {});
    }
    setSession(data.session, data.username, data.displayName, data.hasAvatar);
    await loadUserBoards();
  } catch (error) {
    showError('login-error', error.message);
  }
});

/* ── Register ── */
elementById('register-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const username = elementById('reg-user').value.trim();
  const email = elementById('reg-email').value.trim();
  const password = elementById('reg-pass').value;
  clearError('reg-error');
  if (!username || !email || !password) {
    return showError('reg-error', 'Please fill in all fields.');
  }
  if (password.length < 8) {
    return showError('reg-error', 'Password must be at least 8 characters.');
  }
  try {
    const data = await api('POST', '/auth/register', { username: username, email, password: password });
    if (window.PasswordCredential) {
      const credential = new PasswordCredential({ id: username, password: password });
      navigator.credentials.store(credential).catch(() => {});
    }
    setSession(data.session, data.username, data.displayName);
    await loadUserBoards();
  } catch (error) {
    showError('reg-error', error.message);
  }
});

/* ── Guest ── */
elementById('guest-btn').addEventListener('click', setGuest);
elementById('logout-btn').addEventListener('click', logout);

/* ── Enter key shortcuts ── */
elementById('reg-pass').addEventListener('keydown', (event) => {
  if (event.key === 'Enter') {
    elementById('register-form').requestSubmit();
  }
});

/* ── Guest file import ── */
setupFileImport(elementById('guest-import-file'), elementById('guest-import-zone'), (json) => {
  importBoardFromJSON(json, true);
});

/* ── Boards ── */
async function loadUserBoards() {
  if (state.isGuest) {
    return;
  }
  try {
    const data = await api('GET', '/boards/list');
    state.boards = data.boards;
    renderBoardList();
    if (state.boards.length) {
      selectBoard(state.boards[0].id);
    }
    if (window.Sync !== null && window.Sync !== undefined) {
      window.Sync.changed();
    }
  } catch (error) {
    toast('Failed to load boards', 'error');
  }
  state.boardsReady = true;
}

function renderBoardList() {
  const list = elementById('board-list');
  list.innerHTML = '';
  state.boards.forEach((board) => {
    const item = document.createElement('div');
    let className = 'board-item';
    if (board.id === state.activeBoardId) {
      className = className + ' active';
    }
    item.className = className;
    item.dataset.id = board.id;
    item.innerHTML = `<span class="board-dot"></span><span>${escapeHtml(board.name)}</span>`;
    item.addEventListener('click', () => {
      selectBoard(board.id);
    });
    list.appendChild(item);
  });
}

function selectBoard(id) {
  state.activeBoardId = id;
  const board = state.boards.find((candidate) => {
    return candidate.id === id;
  });
  if (!board) {
    return;
  }
  elementById('board-title').textContent = board.name;
  elementById('edit-board-title-btn').classList.remove('hidden');
  setBoardActions(true);
  elementById('empty-state').classList.add('hidden');
  state.viewOverride = null;
  renderBoardList();
  renderBoard(board);
  pageChanged();
}

// No board open: neither view on show.
function hideBoardViews() {
  state.viewOverride = null;
  elementById('columns-container').classList.add('hidden');
  elementById('timeline-container').classList.add('hidden');
  elementById('timeline-container').innerHTML = '';
  elementById('board-canvas').classList.remove('is-timeline');
}

function getActiveBoard() {
  return state.boards.find((board) => {
    return board.id === state.activeBoardId;
  });
}

// The open board's actions in the edge tray, and the rule above them: there only with a board open.
function setBoardActions(visible) {
  ['trayBoardRule', 'board-view-btn', 'board-export-btn', 'board-import-btn', 'delete-board-btn']
    .forEach((id) => {
      elementById(id).classList.toggle('hidden', !visible);
    });
}

/* ── Kanban or Timeline ── */
// The same board either way: its columns are a timeline's phases and its cards the tasks.
// Show me around can show the open board as the other view for its tour (js/tour.js); that's
// state.viewOverride, which is never saved and goes when the tour ends or another board opens.
const isTimeline = (board) => {
  let view;
  if (board && board === getActiveBoard() && state.viewOverride) {
    view = state.viewOverride;
  } else if (board !== null && board !== undefined) {
    view = board.view;
  } else {
    view = undefined;
  }
  return view === 'timeline';
};
window.isTimeline = isTimeline;

// `view` for the open board, just for now; its own view clears it.
function setViewOverride(view) {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  let own;
  if (board.view === 'timeline') {
    own = 'timeline';
  } else {
    own = 'kanban';
  }
  if (view && view !== own) {
    state.viewOverride = view;
  } else {
    state.viewOverride = null;
  }
  renderBoard(board);
  pageChanged();
}

// The tray button offers the other view.
function updateViewButton(board) {
  const button = elementById('board-view-btn');
  let label;
  if (isTimeline(board)) {
    label = 'Show as Kanban';
  } else {
    label = 'Show as Timeline';
  }
  button.setAttribute('aria-label', label);
  button.title = label;
  let iconName;
  if (isTimeline(board)) {
    iconName = 'kanban';
  } else {
    iconName = 'timeline';
  }
  button.querySelector('[data-icon]').setAttribute('data-icon', iconName);
  hydrateIcons(button);
}

elementById('board-view-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  if (isTimeline(board)) {
    board.view = 'kanban';
  } else {
    board.view = 'timeline';
  }
  state.viewOverride = null;
  touch(board);
  persistBoard(board);
  renderBoard(board);
  pageChanged();
  if (isTimeline(board)) {
    toast('Showing as a timeline');
  } else {
    toast('Showing as a kanban board');
  }
});

// Boards that came in from another device (js/sync.js): the list and the board on show follow.
function boardsChanged(changed) {
  renderBoardList();
  const active = getActiveBoard();
  if (!active) {
    if (state.boards.length) {
      selectBoard(state.boards[0].id);
    }
  } else if (changed.includes(active)) {
    elementById('board-title').textContent = active.name;
    renderBoard(active);
  }
}

// The first card on the open board, for the card details tour (js/tour.js).
function firstCard() {
  const board = getActiveBoard();
  let columns;
  if (board !== null && board !== undefined) {
    columns = board.columns;
  }
  if (!columns) {
    columns = [];
  }
  for (const column of columns) {
    if (column.cards.length) {
      return { card: column.cards[0], column: column };
    }
  }
  return null;
}

function openFirstCard() {
  const first = firstCard();
  if (first) {
    openCardModal(first.card.id, first.column.id);
  }
}

/* ── Render board ── */
// Draws the board as a timeline (js/timeline.js) or as kanban columns with an "add column"
// button at the end, emptying whichever view isn't in use.
function renderBoard(board) {
  const timeline = isTimeline(board);
  elementById('columns-container').classList.toggle('hidden', timeline);
  elementById('timeline-container').classList.toggle('hidden', !timeline);
  elementById('board-canvas').classList.toggle('is-timeline', timeline);
  updateViewButton(board);
  if (timeline) {
    elementById('columns-container').innerHTML = '';
    Timeline.render(board);
    return;
  }
  elementById('timeline-container').innerHTML = '';

  const container = elementById('columns-container');
  container.innerHTML = '';
  board.columns.forEach((column) => {
    container.appendChild(buildColumn(column));
  });
  const addColumnButton = document.createElement('button');
  addColumnButton.className = 'add-col-circle-btn';
  addColumnButton.title = 'Add Column';
  addColumnButton.innerHTML = `<svg width="22" height="22" viewBox="0 0 22 22" fill="none"><path d="M11 4v14M4 11h14" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg>`;
  addColumnButton.addEventListener('click', addColumn);
  container.appendChild(addColumnButton);
}

// One kanban column: its header, its cards, and its "Add card" and reorder buttons, with
// card dropping wired up.
function buildColumn(column) {
  const columnElement = document.createElement('div');
  columnElement.className = 'column';
  columnElement.dataset.colId = column.id;

  columnElement.innerHTML = `
    <div class="column-header">
      <div class="col-title-wrap">
        <span class="col-title">${escapeHtml(column.name)}</span>
        <span class="col-count">${column.cards.length}</span>
      </div>
      <button class="mini-btn col-menu-btn" title="Column options">
        <svg width="14" height="14" viewBox="0 0 14 14"><circle cx="7" cy="2" r="1.2" fill="currentColor"/><circle cx="7" cy="7" r="1.2" fill="currentColor"/><circle cx="7" cy="12" r="1.2" fill="currentColor"/></svg>
      </button>
    </div>
    <div class="cards-list" data-col-id="${column.id}"></div>
    <div class="col-bottom-bar">
      <button class="add-card-btn">
        <svg width="12" height="12" viewBox="0 0 12 12"><path d="M6 1v10M1 6h10" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>
        Add card
      </button>
      <button class="col-reorder-btn" title="Reorder columns">
        <svg width="13" height="13" viewBox="0 0 14 14" fill="none">
          <path d="M2 3h10M2 7h10M2 11h10" stroke="currentColor" stroke-width="1.3" stroke-linecap="round"/>
          <path d="M11 1l2 2-2 2M11 9l2 2-2 2" stroke="currentColor" stroke-width="1.3" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </button>
    </div>
  `;

  const cardsList = columnElement.querySelector('.cards-list');
  column.cards.forEach((card) => {
    cardsList.appendChild(buildCard(card, column.id));
  });

  columnElement.querySelector('.add-card-btn').addEventListener('click', () => {
    openInlineAdd(column.id, columnElement);
  });
  columnElement.querySelector('.col-reorder-btn').addEventListener('click', openReorderColumnsModal);
  columnElement.querySelector('.col-menu-btn').addEventListener('click', () => {
    openRenameColumnModal(column);
  });

  setupColumnDrop(cardsList, column.id);
  return columnElement;
}

// One card on the board: thumbnail, labels, title, due date and priority, checklist
// progress. Clicking opens its details; it can be dragged to another place.
function buildCard(card, columnId) {
  const cardElement = document.createElement('div');
  cardElement.className = 'card';
  cardElement.dataset.cardId = card.id;
  cardElement.draggable = true;

  let labelsHtml = '';
  if (card.labels && card.labels.length) {
    const labelChips = card.labels.map((label) => {
      const rgb = hexToRgb(label.color);
      // The label colour is user data, so the chip carries it opaquely and the
      // text flips with it. A tint would drop under AA in dark mode.
      let textColor;
      if (isDark(label.color)) {
        textColor = '#ffffff';
      } else {
        textColor = '#121815';
      }
      return `<span class="card-label" style="background:${label.color};border-color:rgba(${rgb},0.6);color:${textColor}">${escapeHtml(label.text)}</span>`;
    }).join('');
    labelsHtml = `<div class="card-labels">${labelChips}</div>`;
  }

  let metaHtml = '';
  if (card.due || card.priority) {
    let dueHtml = '';
    if (card.due) {
      const dueDate = new Date(card.due);
      const now = new Date();
      const daysLeft = (dueDate - now) / 86400000;
      let dueClass;
      if (daysLeft < 0) {
        dueClass = 'overdue';
      } else if (daysLeft < 2) {
        dueClass = 'soon';
      } else {
        dueClass = '';
      }
      let dateText;
      if (card.start && card.start !== card.due) {
        dateText = `${card.start} → ${card.due}`;
      } else {
        dateText = card.due;
      }
      let dueNote;
      if (dueClass === 'overdue') {
        dueNote = ' · overdue';
      } else if (dueClass === 'soon') {
        dueNote = ' · due soon';
      } else {
        dueNote = '';
      }
      dueHtml = `<span class="card-due ${dueClass}">
        <svg width="10" height="10" viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" stroke="currentColor" fill="none" stroke-width="1.2"/><path d="M5 3v2.5l1.5 1" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>
        ${dateText}${dueNote}
      </span>`;
    }
    let priorityHtml;
    if (card.priority) {
      priorityHtml = `<span class="card-priority priority-${card.priority}">${card.priority}</span>`;
    } else {
      priorityHtml = '';
    }
    metaHtml = `<div class="card-meta">${dueHtml}${priorityHtml}</div>`;
  }

  let checkHtml = '';
  if (card.checklist && card.checklist.length) {
    const done = card.checklist.filter((item) => {
      return item.done;
    }).length;
    const percent = Math.round((done / card.checklist.length) * 100);
    checkHtml = `<div class="card-checklist-bar">
      <div class="check-progress"><div class="check-fill" style="width:${percent}%"></div></div>
      <span class="check-text">${done}/${card.checklist.length}</span>
    </div>`;
  }

  // The thumbnail's bytes arrive as a blob: URL (js/images.js), never the storage address.
  let thumbnail = null;
  if (card.images && card.images.length) {
    thumbnail = card.images.find((image) => {
      return image.id === card.thumbnailId;
    });
    if (!thumbnail) {
      thumbnail = card.images[0];
    }
  }
  let thumbnailHtml = '';
  if (thumbnail) {
    thumbnailHtml = `<div class="card-thumb"><img alt="" /></div>`;
  }
  cardElement.innerHTML = `${thumbnailHtml}${labelsHtml}<div class="card-title">${escapeHtml(card.title)}</div>${metaHtml}${checkHtml}`;
  if (thumbnail) {
    ImageStore.show(cardElement.querySelector('.card-thumb img'), thumbnail);
  }
  cardElement.addEventListener('click', () => {
    openCardModal(card.id, columnId);
  });
  cardElement.addEventListener('dragstart', (event) => {
    state.dragCard = { cardId: card.id, columnId: columnId };
    cardElement.classList.add('dragging');
    event.dataTransfer.effectAllowed = 'move';
  });
  cardElement.addEventListener('dragend', () => {
    cardElement.classList.remove('dragging');
  });
  return cardElement;
}

/* ── Inline add card ── */
// A small title box at the bottom of a column for adding a card without opening a window.
// Enter (without Shift) adds it, Escape or Cancel throws it away.
function openInlineAdd(columnId, columnElement) {
  const existing = columnElement.querySelector('.inline-add-card');
  if (existing) {
    existing.querySelector('textarea').focus();
    return;
  }

  const zone = document.createElement('div');
  zone.className = 'inline-add-card';
  zone.innerHTML = `
    <textarea placeholder="Card title…" rows="2"></textarea>
    <div class="inline-add-actions">
      <button class="btn-primary small">Add</button>
      <button class="btn-ghost small">Cancel</button>
    </div>`;

  const titleInput = zone.querySelector('textarea');
  zone.querySelectorAll('button')[0].addEventListener('click', () => {
    const title = titleInput.value.trim();
    if (!title) {
      return;
    }
    addCard(columnId, title);
    zone.remove();
  });
  zone.querySelectorAll('button')[1].addEventListener('click', () => {
    zone.remove();
  });
  titleInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && !event.shiftKey) {
      event.preventDefault();
      zone.querySelectorAll('button')[0].click();
    }
    if (event.key === 'Escape') {
      zone.remove();
    }
  });

  columnElement.insertBefore(zone, columnElement.querySelector('.col-bottom-bar'));
  titleInput.focus();
}

/* ── Add card ── */
async function addCard(columnId, title) {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  const column = board.columns.find((candidate) => {
    return candidate.id === columnId;
  });
  if (!column) {
    return;
  }
  const card = touch({ id: makeId(), title, description: '', labels: [], checklist: [], due: '', priority: '', images: [], thumbnailId: null });
  column.cards.push(card);

  if (!state.isGuest) {
    try {
      await api('PUT', `/boards/update`, { board });
    } catch (error) {
      toast('Sync error', 'error');
    }
  } else {
    saveGuest();
  }

  renderBoard(board);
}

/* ── Drag & drop ── */
// Lets a column's card list take a dragged card: a placeholder shows where it will land,
// and dropping moves the card there and saves the board.
function setupColumnDrop(cardsList, columnId) {
  cardsList.addEventListener('dragover', (event) => {
    event.preventDefault();
    event.dataTransfer.dropEffect = 'move';
    cardsList.classList.add('drag-over');

    const afterElement = getDragAfterElement(cardsList, event.clientY);
    let placeholder = cardsList.querySelector('.drag-placeholder');
    if (!placeholder) {
      placeholder = document.createElement('div');
      placeholder.className = 'drag-placeholder';
    }
    if (afterElement) {
      cardsList.insertBefore(placeholder, afterElement);
    } else {
      cardsList.appendChild(placeholder);
    }
  });

  cardsList.addEventListener('dragleave', (event) => {
    if (!cardsList.contains(event.relatedTarget)) {
      cardsList.classList.remove('drag-over');
      const placeholder = cardsList.querySelector('.drag-placeholder');
      if (placeholder !== null) {
        placeholder.remove();
      }
    }
  });

  cardsList.addEventListener('drop', (event) => {
    event.preventDefault();
    cardsList.classList.remove('drag-over');
    const placeholder = cardsList.querySelector('.drag-placeholder');
    if (placeholder !== null) {
      placeholder.remove();
    }
    if (!state.dragCard) {
      return;
    }

    const board = getActiveBoard();
    const sourceColumn = board.columns.find((candidate) => {
      return candidate.id === state.dragCard.columnId;
    });
    const targetColumn = board.columns.find((candidate) => {
      return candidate.id === columnId;
    });
    if (!sourceColumn || !targetColumn) {
      return;
    }

    const cardIndex = sourceColumn.cards.findIndex((candidate) => {
      return candidate.id === state.dragCard.cardId;
    });
    if (cardIndex === -1) {
      return;
    }
    const [card] = sourceColumn.cards.splice(cardIndex, 1);
    // Where a card is counts as a change to it, so a move made here wins over an older copy.
    if (sourceColumn !== targetColumn) {
      touch(card);
    }

    const afterElement = getDragAfterElement(cardsList, event.clientY);
    if (!afterElement) {
      targetColumn.cards.push(card);
    } else {
      const afterId = afterElement.dataset.cardId;
      const insertAt = targetColumn.cards.findIndex((candidate) => {
        return candidate.id === afterId;
      });
      targetColumn.cards.splice(insertAt, 0, card);
    }

    state.dragCard = null;
    persistBoard(board);
    renderBoard(board);
  });
}

/* ── Reorder columns modal ── */
function openReorderColumnsModal() {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  renderReorderList(board.columns);
  elementById('reorder-cols-modal').classList.remove('hidden');
}

// The reorder window's list: each column with up and down buttons (the first can't go up,
// the last can't go down). The new order is saved only when Save is pressed.
function renderReorderList(columns) {
  const list = elementById('reorder-col-list');
  list.innerHTML = '';
  columns.forEach((column, index) => {
    const row = document.createElement('div');
    row.className = 'reorder-row';
    row.dataset.colId = column.id;
    let upDisabled = '';
    if (index === 0) {
      upDisabled = 'disabled';
    }
    let downDisabled = '';
    if (index === columns.length - 1) {
      downDisabled = 'disabled';
    }
    row.innerHTML = `
      <span class="reorder-name">${escapeHtml(column.name)}</span>
      <div class="reorder-btns">
        <button class="reorder-btn" data-dir="-1" ${upDisabled} title="Move up">
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M2 9l5-5 5 5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
        </button>
        <button class="reorder-btn" data-dir="1" ${downDisabled} title="Move down">
          <svg width="14" height="14" viewBox="0 0 14 14" fill="none"><path d="M2 5l5 5 5-5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
        </button>
      </div>`;
    row.querySelectorAll('.reorder-btn').forEach((button) => {
      button.addEventListener('click', () => {
        const board = getActiveBoard();
        const currentIndex = board.columns.findIndex((candidate) => {
          return candidate.id === column.id;
        });
        const newIndex = currentIndex + parseInt(button.dataset.dir);
        if (newIndex < 0 || newIndex >= board.columns.length) {
          return;
        }
        const [moved] = board.columns.splice(currentIndex, 1);
        board.columns.splice(newIndex, 0, moved);
        renderReorderList(board.columns);
      });
    });
    list.appendChild(row);
  });
}

elementById('reorder-cols-close').addEventListener('click', () => {
  elementById('reorder-cols-modal').classList.add('hidden');
});
elementById('reorder-cols-cancel').addEventListener('click', () => {
  elementById('reorder-cols-modal').classList.add('hidden');
});
elementById('reorder-cols-modal').addEventListener('click', (event) => {
  if (event.target === elementById('reorder-cols-modal')) {
    elementById('reorder-cols-modal').classList.add('hidden');
  }
});

elementById('reorder-cols-save').addEventListener('click', () => {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  elementById('reorder-cols-modal').classList.add('hidden');
  persistBoard(board);
  renderBoard(board);
  toast('Columns reordered');
});

// The card a dragged card would land in front of: of the cards whose middle is below the
// pointer, the nearest one. Undefined means "at the end of the list".
function getDragAfterElement(container, y) {
  const cardElements = [...container.querySelectorAll('.card:not(.dragging)')];
  return cardElements.reduce((closest, element) => {
    const box = element.getBoundingClientRect();
    const offset = y - box.top - box.height / 2;
    if (offset < 0 && offset > closest.offset) {
      return { offset: offset, element: element };
    }
    return closest;
  }, { offset: -Infinity }).element;
}

/* ── Card modal ── */
// Opens the card details window filled in from the card: title, description, dates,
// priority, column, images, labels, checklist and (on a timeline) what it waits for.
function openCardModal(cardId, columnId) {
  const board = getActiveBoard();
  const column = board.columns.find((candidate) => {
    return candidate.id === columnId;
  });
  let card;
  if (column !== undefined) {
    card = column.cards.find((candidate) => {
      return candidate.id === cardId;
    });
  }
  if (!card) {
    return;
  }

  state.editingCardId = cardId;
  state.editingColumnId = columnId;

  elementById('card-modal-title').value = card.title;
  let description = card.description;
  if (!description) {
    description = '';
  }
  elementById('card-modal-desc').value = description;
  let due = card.due;
  if (!due) {
    due = '';
  }
  elementById('card-modal-due').value = due;
  let priority = card.priority;
  if (!priority) {
    priority = '';
  }
  elementById('card-modal-priority').value = priority;

  elementById('card-modal-col').value = columnId;
  let columnName;
  if (column !== undefined) {
    columnName = column.name;
  }
  if (!columnName) {
    columnName = 'None';
  }
  elementById('card-modal-col-label').textContent = columnName;

  renderCardImages(card);
  let labels = card.labels;
  if (!labels) {
    labels = [];
  }
  renderModalLabels(labels);
  let checklist = card.checklist;
  if (!checklist) {
    checklist = [];
  }
  renderChecklist(checklist);

  // A timeline's own fields: a start date, whether it's a milestone, and what it waits for.
  elementById('card-tl-fields').classList.toggle('hidden', !isTimeline(board));
  let start = card.start;
  if (!start) {
    start = '';
  }
  elementById('card-modal-start').value = start;
  elementById('card-modal-milestone').checked = Boolean(card.milestone);
  elementById('card-modal-start').disabled = Boolean(card.milestone);
  renderDependencies(card);

  elementById('card-modal').classList.remove('hidden');
  pageChanged();
}

/* ── What a task waits for (Timeline) ── */
// The card open in the details window, or null.
function editingCard() {
  const board = getActiveBoard();
  let column;
  if (board !== null && board !== undefined) {
    column = board.columns.find((candidate) => {
      return candidate.id === state.editingColumnId;
    });
  }
  let card;
  if (column !== undefined) {
    card = column.cards.find((candidate) => {
      return candidate.id === state.editingCardId;
    });
  }
  if (!card) {
    return null;
  }
  return card;
}

// The tasks this one waits for as chips, and a list of the others it could: never itself, nor
// anything already waiting for it, which would make the chain go round in a circle.
function renderDependencies(card) {
  const board = getActiveBoard();
  const allCards = board.columns.flatMap((column) => {
    return column.cards;
  });
  let dependsOn = card.dependsOn;
  if (!dependsOn) {
    dependsOn = [];
  }
  const dependencies = dependsOn.filter((id) => {
    return allCards.some((other) => {
      return other.id === id;
    });
  });
  const chips = elementById('card-deps');
  let chipsHtml = dependencies.map((id) => {
    const other = allCards.find((candidate) => {
      return candidate.id === id;
    });
    const clash = Timeline.clashes(other, card);
    let clashClass = '';
    let clashTitle = '';
    if (clash) {
      clashClass = ' clash';
      clashTitle = 'Its dates clash with this task';
    }
    return `<span class="dep-chip${clashClass}" title="${clashTitle}">${escapeHtml(other.title)}` +
      `<button type="button" data-dep="${escapeHtml(id)}" aria-label="Stop waiting for ${escapeHtml(other.title)}"><span data-icon="close"></span></button></span>`;
  }).join('');
  if (!chipsHtml) {
    chipsHtml = '<span class="dep-none">Doesn’t wait for anything</span>';
  }
  chips.innerHTML = chipsHtml;
  hydrateIcons(chips);
  const blocked = Timeline.waitingOn(board, card.id);
  const choices = allCards.filter((other) => {
    return other.id !== card.id && !dependencies.includes(other.id) && !blocked.has(other.id);
  });
  let promptText;
  if (choices.length) {
    promptText = 'Add a task this one waits for…';
  } else {
    promptText = 'No other tasks to wait for';
  }
  elementById('card-dep-add').innerHTML = `<option value="">${promptText}</option>` +
    choices.map((other) => {
      return `<option value="${escapeHtml(other.id)}">${escapeHtml(other.title)}</option>`;
    }).join('');
  elementById('card-dep-add').disabled = !choices.length;
}

elementById('card-deps').addEventListener('click', (event) => {
  const button = event.target.closest('[data-dep]');
  const card = editingCard();
  if (!button || !card) {
    return;
  }
  let dependsOn = card.dependsOn;
  if (!dependsOn) {
    dependsOn = [];
  }
  card.dependsOn = dependsOn.filter((id) => {
    return id !== button.dataset.dep;
  });
  renderDependencies(card);
});

elementById('card-dep-add').addEventListener('change', (event) => {
  const card = editingCard();
  if (!card || !event.target.value) {
    return;
  }
  let dependsOn = card.dependsOn;
  if (!dependsOn) {
    dependsOn = [];
  }
  card.dependsOn = [...dependsOn, event.target.value];
  renderDependencies(card);
});

// A milestone is one day, its due date: the start date goes with it.
elementById('card-modal-milestone').addEventListener('change', (event) => {
  elementById('card-modal-start').disabled = event.target.checked;
});

// The card's labels in the details window, each with a button that removes it.
function renderModalLabels(labels) {
  const container = elementById('card-modal-labels');
  container.innerHTML = '';
  labels.forEach((label, index) => {
    const chip = document.createElement('div');
    chip.className = 'label-chip';
    const rgb = hexToRgb(label.color);
    let textColor;
    if (isDark(label.color)) {
      textColor = '#ffffff';
    } else {
      textColor = '#121815';
    }
    chip.style.cssText = `background:${label.color};border-color:rgba(${rgb},0.6);color:${textColor}`;
    chip.innerHTML = `${escapeHtml(label.text)}<button data-i="${index}" title="Remove"><span data-icon="close"></span></button>`;
    chip.querySelector('button').addEventListener('click', () => {
      const board = getActiveBoard();
      const column = board.columns.find((candidate) => {
        return candidate.id === state.editingColumnId;
      });
      let card;
      if (column !== undefined) {
        card = column.cards.find((candidate) => {
          return candidate.id === state.editingCardId;
        });
      }
      if (card) {
        card.labels.splice(index, 1);
        renderModalLabels(card.labels);
      }
    });
    container.appendChild(chip);
  });
  hydrateIcons(container);
}

// The card's checklist in the details window: a tick box and a remove button per item.
function renderChecklist(items) {
  const container = elementById('card-checklist');
  container.innerHTML = '';
  items.forEach((item, index) => {
    const row = document.createElement('div');
    row.className = 'check-item';
    let checkedAttribute = '';
    if (item.done) {
      checkedAttribute = 'checked';
    }
    let doneClass = '';
    if (item.done) {
      doneClass = 'done';
    }
    row.innerHTML = `
      <input type="checkbox" ${checkedAttribute} data-i="${index}" />
      <span class="${doneClass}">${escapeHtml(item.text)}</span>
      <button class="del-check" data-i="${index}" title="Remove"><span data-icon="close"></span></button>`;
    row.querySelector('input').addEventListener('change', (event) => {
      const board = getActiveBoard();
      const column = board.columns.find((candidate) => {
        return candidate.id === state.editingColumnId;
      });
      let card;
      if (column !== undefined) {
        card = column.cards.find((candidate) => {
          return candidate.id === state.editingCardId;
        });
      }
      if (card) {
        card.checklist[index].done = event.target.checked;
        renderChecklist(card.checklist);
      }
    });
    row.querySelector('.del-check').addEventListener('click', () => {
      const board = getActiveBoard();
      const column = board.columns.find((candidate) => {
        return candidate.id === state.editingColumnId;
      });
      let card;
      if (column !== undefined) {
        card = column.cards.find((candidate) => {
          return candidate.id === state.editingCardId;
        });
      }
      if (card) {
        card.checklist.splice(index, 1);
        renderChecklist(card.checklist);
      }
    });
    container.appendChild(row);
  });
  hydrateIcons(container);
}

elementById('add-label-btn').addEventListener('click', () => {
  const text = elementById('new-label-input').value.trim();
  const color = elementById('new-label-color').value;
  if (!text) {
    return;
  }
  const board = getActiveBoard();
  const column = board.columns.find((candidate) => {
    return candidate.id === state.editingColumnId;
  });
  let card;
  if (column !== undefined) {
    card = column.cards.find((candidate) => {
      return candidate.id === state.editingCardId;
    });
  }
  if (!card) {
    return;
  }
  if (!card.labels) {
    card.labels = [];
  }
  card.labels.push({ text, color });
  elementById('new-label-input').value = '';
  renderModalLabels(card.labels);
});

elementById('add-check-btn').addEventListener('click', () => {
  const text = elementById('new-check-input').value.trim();
  if (!text) {
    return;
  }
  const board = getActiveBoard();
  const column = board.columns.find((candidate) => {
    return candidate.id === state.editingColumnId;
  });
  let card;
  if (column !== undefined) {
    card = column.cards.find((candidate) => {
      return candidate.id === state.editingCardId;
    });
  }
  if (!card) {
    return;
  }
  if (!card.checklist) {
    card.checklist = [];
  }
  card.checklist.push({ text, done: false });
  elementById('new-check-input').value = '';
  renderChecklist(card.checklist);
});

elementById('new-check-input').addEventListener('keydown', (event) => {
  if (event.key === 'Enter') {
    elementById('add-check-btn').click();
  }
});
elementById('new-label-input').addEventListener('keydown', (event) => {
  if (event.key === 'Enter') {
    elementById('add-label-btn').click();
  }
});

// Save in the card details window: copies the fields back onto the card (checking the
// timeline dates make sense), moves it if another column was picked, and saves the board.
elementById('save-card-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  const column = board.columns.find((candidate) => {
    return candidate.id === state.editingColumnId;
  });
  let card;
  if (column !== undefined) {
    card = column.cards.find((candidate) => {
      return candidate.id === state.editingCardId;
    });
  }
  if (!card) {
    return;
  }

  // Timeline dates: a start after the due date is a mistake to fix, not to guess at.
  const timeline = isTimeline(board);
  const due = elementById('card-modal-due').value;
  let milestone;
  if (timeline) {
    milestone = elementById('card-modal-milestone').checked;
  } else {
    milestone = Boolean(card.milestone);
  }
  let start;
  if (timeline) {
    start = elementById('card-modal-start').value;
  } else {
    start = card.start;
    if (!start) {
      start = '';
    }
  }
  if (milestone) {
    if (due) {
      start = due;
    }
  }
  if (start && due && start > due) {
    toast('The start date is after the due date', 'error');
    return;
  }

  let title = elementById('card-modal-title').value.trim();
  if (!title) {
    title = card.title;
  }
  card.title = title;
  card.description = elementById('card-modal-desc').value;
  if (milestone) {
    if (due) {
      card.due = due;
    } else {
      card.due = start;
    }
  } else {
    card.due = due;
  }
  card.priority = elementById('card-modal-priority').value;
  if (start) {
    card.start = start;
  } else {
    delete card.start;
  }
  if (milestone) {
    card.milestone = true;
  } else {
    delete card.milestone;
  }
  touch(card);

  const targetColumnId = elementById('card-modal-col').value;
  if (targetColumnId && targetColumnId !== state.editingColumnId) {
    const targetColumn = board.columns.find((candidate) => {
      return candidate.id === targetColumnId;
    });
    if (targetColumn) {
      column.cards = column.cards.filter((candidate) => {
        return candidate.id !== state.editingCardId;
      });
      targetColumn.cards.push(card);
    }
  }

  closeCardModal();
  persistBoard(board);
  renderBoard(board);
  toast('Card saved');
});

elementById('delete-card-btn').addEventListener('click', () => {
  if (!confirm('Delete this card?')) {
    return;
  }
  const board = getActiveBoard();
  const column = board.columns.find((candidate) => {
    return candidate.id === state.editingColumnId;
  });
  if (!column) {
    return;
  }
  column.cards = column.cards.filter((candidate) => {
    return candidate.id !== state.editingCardId;
  });
  Timeline.pruneDependencies(board);
  closeCardModal();
  persistBoard(board);
  renderBoard(board);
  toast('Card deleted');
});

elementById('card-modal-close').addEventListener('click', closeCardModal);
elementById('card-modal').addEventListener('click', (event) => {
  if (event.target === elementById('card-modal')) {
    closeCardModal();
  }
});

/* ── Column picker ── */
elementById('card-modal-col-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  const currentColumnId = elementById('card-modal-col').value;
  const list = elementById('col-picker-list');
  list.innerHTML = '';
  board.columns.forEach((column) => {
    const button = document.createElement('button');
    button.type = 'button';
    let className = 'col-picker-item';
    if (column.id === currentColumnId) {
      className = className + ' active';
    }
    button.className = className;
    button.textContent = column.name;
    button.addEventListener('click', () => {
      elementById('card-modal-col').value = column.id;
      elementById('card-modal-col-label').textContent = column.name;
      elementById('col-picker-sheet').classList.add('hidden');
    });
    list.appendChild(button);
  });
  elementById('col-picker-sheet').classList.remove('hidden');
});

elementById('col-picker-close').addEventListener('click', () => {
  elementById('col-picker-sheet').classList.add('hidden');
});
elementById('col-picker-sheet').addEventListener('click', (event) => {
  if (event.target === elementById('col-picker-sheet')) {
    elementById('col-picker-sheet').classList.add('hidden');
  }
});

function closeCardModal() {
  if (elementById('card-modal').classList.contains('hidden')) {
    return;
  }
  elementById('card-modal').classList.add('hidden');
  pageChanged();
}

/* ── Card images ── */
// The card's images in the details window, each with buttons to make it the thumbnail,
// save it, or delete it (from storage too, when signed in). Clicking an image opens it.
function renderCardImages(card) {
  if (!card.images) {
    card.images = [];
  }
  const grid = elementById('card-images-grid');
  grid.innerHTML = '';
  card.images.forEach((image) => {
    let thumbnailId = card.thumbnailId;
    if (!thumbnailId) {
      const firstImage = card.images[0];
      if (firstImage !== null && firstImage !== undefined) {
        thumbnailId = firstImage.id;
      } else {
        thumbnailId = undefined;
      }
    }
    const isThumbnail = image.id === thumbnailId;
    const item = document.createElement('div');
    let itemClass = 'card-img-item';
    if (isThumbnail) {
      itemClass = itemClass + ' is-thumb';
    }
    item.className = itemClass;
    let thumbnailButtonActive = '';
    let thumbnailButtonTitle = 'Set as thumbnail';
    let thumbnailButtonText = 'Set thumb';
    if (isThumbnail) {
      thumbnailButtonActive = ' active';
      thumbnailButtonTitle = 'Thumbnail';
      thumbnailButtonText = 'Thumbnail';
    }
    item.innerHTML = `
      <img alt="${escapeHtml(image.name)}" title="Open image" />
      <div class="img-actions">
        <button type="button" class="img-action-btn thumb-img-btn${thumbnailButtonActive}" title="${thumbnailButtonTitle}">
          <svg width="11" height="11" viewBox="0 0 11 11"><path d="M5.5 1l1.2 2.4 2.8.4-2 2 .5 2.7-2.5-1.4L3 8.5l.5-2.7-2-2 2.8-.4z" fill="currentColor"/></svg>
          ${thumbnailButtonText}
        </button>
        <button type="button" class="img-action-btn save-img-btn" title="Download"><span data-icon="download"></span> Save</button>
        <button type="button" class="img-action-btn del-img-btn" title="Delete"><span data-icon="close"></span> Delete</button>
      </div>`;
    // Bytes, as a blob: URL: opening or saving the image never shows where it's stored.
    const imageElement = item.querySelector('img');
    ImageStore.show(imageElement, image);
    // Pressing the image (its actions sit over it) opens it, straight from the click, before
    // anything is awaited, so no popup blocker stops it.
    item.addEventListener('click', (event) => {
      if (!event.target.closest('button') && imageElement.src) {
        window.open(imageElement.src, '_blank');
      }
    });
    item.querySelector('.save-img-btn').addEventListener('click', () => {
      ImageStore.blob(image).then(
        (imageBlob) => {
          let fileName = image.name;
          if (!fileName) {
            fileName = `image-${image.id}`;
          }
          return ImageStore.save(imageBlob, fileName);
        },
        () => {
          return toast('That image could not be loaded', 'error');
        });
    });
    item.querySelector('.thumb-img-btn').addEventListener('click', () => {
      card.thumbnailId = image.id;
      renderCardImages(card);
    });
    item.querySelector('.del-img-btn').addEventListener('click', async () => {
      if (!state.isGuest && (image.file || image.path)) {
        try {
          let deleteBody;
          if (image.file) {
            deleteBody = { file: image.file };
          } else {
            deleteBody = { path: image.path };
          }
          await api('DELETE', '/images/delete', deleteBody);
        } catch {
          toast('Could not delete image from storage', 'error');
        }
      }
      card.images = card.images.filter((other) => {
        return other.id !== image.id;
      });
      if (card.thumbnailId === image.id) {
        const firstImage = card.images[0];
        let newThumbnailId;
        if (firstImage !== null && firstImage !== undefined) {
          newThumbnailId = firstImage.id;
        }
        if (newThumbnailId === null || newThumbnailId === undefined) {
          newThumbnailId = null;
        }
        card.thumbnailId = newThumbnailId;
      }
      renderCardImages(card);
    });
    grid.appendChild(item);
  });
  hydrateIcons(grid);
}

// Images picked for the open card: each is shrunk, then kept in this browser (guest) or
// uploaded to this account's storage. The first one becomes the thumbnail if there is none.
elementById('card-img-input').addEventListener('change', async (event) => {
  const files = [...event.target.files];
  if (!files.length) {
    return;
  }
  const board = getActiveBoard();
  let column;
  if (board !== null && board !== undefined) {
    column = board.columns.find((candidate) => {
      return candidate.id === state.editingColumnId;
    });
  }
  let card;
  if (column !== undefined) {
    card = column.cards.find((candidate) => {
      return candidate.id === state.editingCardId;
    });
  }
  if (!card) {
    return;
  }
  if (!card.images) {
    card.images = [];
  }
  for (const file of files) {
    const imageData = await resizeImage(file);
    if (state.isGuest) {
      card.images.push({ id: makeId(), data: imageData, name: file.name });
    } else {
      try {
        // The image's name in this account's storage; its bytes come from /api/images/get.
        const result = await api('POST', '/images/upload', { imageData, fileName: file.name });
        card.images.push({ id: makeId(), file: result.file, name: file.name });
      } catch {
        toast('Image upload failed', 'error');
      }
    }
  }
  if (!card.thumbnailId && card.images.length) {
    card.thumbnailId = card.images[0].id;
  }
  renderCardImages(card);
  event.target.value = '';
});

/* ── Rename/delete column modal ── */
function openRenameColumnModal(column) {
  state.editingColumnId = column.id;
  // On a timeline, a column is a phase.
  let word;
  if (isTimeline(getActiveBoard())) {
    word = 'Phase';
  } else {
    word = 'Column';
  }
  elementById('rename-col-heading').textContent = `Rename ${word}`;
  elementById('rename-col-label').textContent = `${word} Name`;
  elementById('delete-col-btn').textContent = `Delete ${word}`;
  elementById('rename-col-input').value = column.name;
  elementById('rename-col-modal').classList.remove('hidden');
}

elementById('save-col-name-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  const column = board.columns.find((candidate) => {
    return candidate.id === state.editingColumnId;
  });
  if (!column) {
    return;
  }
  let name = elementById('rename-col-input').value.trim();
  if (!name) {
    name = column.name;
  }
  column.name = name;
  touch(column);
  elementById('rename-col-modal').classList.add('hidden');
  persistBoard(board);
  renderBoard(board);
});

elementById('delete-col-btn').addEventListener('click', () => {
  let question;
  if (isTimeline(getActiveBoard())) {
    question = 'Delete this phase and all its tasks?';
  } else {
    question = 'Delete this column and all its cards?';
  }
  if (!confirm(question)) {
    return;
  }
  const board = getActiveBoard();
  board.columns = board.columns.filter((candidate) => {
    return candidate.id !== state.editingColumnId;
  });
  Timeline.pruneDependencies(board);
  elementById('rename-col-modal').classList.add('hidden');
  persistBoard(board);
  renderBoard(board);
  if (isTimeline(board)) {
    toast('Phase deleted');
  } else {
    toast('Column deleted');
  }
});

elementById('rename-col-close').addEventListener('click', () => {
  elementById('rename-col-modal').classList.add('hidden');
});
elementById('rename-col-modal').addEventListener('click', (event) => {
  if (event.target === elementById('rename-col-modal')) {
    elementById('rename-col-modal').classList.add('hidden');
  }
});

/* ── Add column ── */
function addColumn() {
  const board = getActiveBoard();
  let question;
  if (isTimeline(board)) {
    question = 'Phase name:';
  } else {
    question = 'Column name:';
  }
  const name = prompt(question);
  if (name === null || name === undefined || !name.trim()) {
    return;
  }
  board.columns.push(touch({ id: makeId(), name: name.trim(), cards: [] }));
  persistBoard(board);
  renderBoard(board);
}

/* ── New board modal ── */
elementById('new-board-btn').addEventListener('click', openNewBoardModal);
elementById('empty-new-board-btn').addEventListener('click', openNewBoardModal);

// What each type of board starts with: a kanban's columns, a timeline's waterfall phases.
const STARTING_COLUMNS = {
  kanban: ['To Do', 'In Progress', 'Done'],
  timeline: ['Requirements', 'Design', 'Build', 'Test', 'Release'],
};

function openNewBoardModal() {
  // A fresh start each time: Kanban, with its usual columns.
  state.newBoardType = null;
  setNewBoardType('kanban');
  elementById('new-board-name').value = '';
  elementById('new-board-modal').classList.remove('hidden');
  pageChanged();
  setTimeout(() => {
    elementById('new-board-name').focus();
  }, 50);
}

// Kanban or Timeline. The starting columns follow, unless they've been changed by hand.
function setNewBoardType(type) {
  const previousType = state.newBoardType;
  state.newBoardType = type;
  document.querySelectorAll('#new-board-type [data-type]').forEach((button) => {
    const selected = button.dataset.type === type;
    button.classList.toggle('active', selected);
    button.setAttribute('aria-checked', String(selected));
  });
  let columnsLabel;
  if (type === 'timeline') {
    columnsLabel = 'Starting phases';
  } else {
    columnsLabel = 'Starting columns';
  }
  elementById('new-board-cols-label').textContent = columnsLabel;
  const untouched = !previousType || JSON.stringify(state.columnChips) === JSON.stringify(STARTING_COLUMNS[previousType]);
  if (untouched) {
    state.columnChips = [...STARTING_COLUMNS[type]];
  }
  renderColumnChips();
}

elementById('new-board-type').addEventListener('click', (event) => {
  const button = event.target.closest('[data-type]');
  if (button) {
    setNewBoardType(button.dataset.type);
  }
});

// Arrow keys move between the two, as in any radio group.
elementById('new-board-type').addEventListener('keydown', (event) => {
  if (!['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(event.key)) {
    return;
  }
  event.preventDefault();
  if (state.newBoardType === 'kanban') {
    setNewBoardType('timeline');
  } else {
    setNewBoardType('kanban');
  }
  document.querySelector(`#new-board-type [data-type="${state.newBoardType}"]`).focus();
});

// The new board's starting columns as chips (clicking one removes it), and a "+ Add" button
// that shows the box for typing another.
function renderColumnChips() {
  const container = elementById('new-board-cols');
  container.innerHTML = '';
  state.columnChips.forEach((name, index) => {
    const chip = document.createElement('span');
    chip.className = 'col-chip removable';
    chip.innerHTML = `${escapeHtml(name)}<span class="chip-x" data-icon="close"></span>`;
    chip.addEventListener('click', () => {
      state.columnChips.splice(index, 1);
      renderColumnChips();
    });
    container.appendChild(chip);
  });
  hydrateIcons(container);
  const addButton = document.createElement('button');
  addButton.className = 'btn-ghost small';
  addButton.id = 'add-default-col-btn';
  addButton.textContent = '+ Add';
  addButton.addEventListener('click', () => {
    const chipInput = elementById('new-col-chip-input');
    chipInput.classList.toggle('hidden');
    if (!chipInput.classList.contains('hidden')) {
      chipInput.focus();
    }
  });
  container.appendChild(addButton);
}

elementById('new-col-chip-input').addEventListener('keydown', (event) => {
  if (event.key === 'Enter') {
    const columnName = event.target.value.trim();
    if (columnName) {
      state.columnChips.push(columnName);
      event.target.value = '';
      event.target.classList.add('hidden');
      renderColumnChips();
    }
  }
  if (event.key === 'Escape') {
    event.target.value = '';
    event.target.classList.add('hidden');
  }
});

// Create in the new board window: makes the board with its starting columns, saves it,
// and opens it.
elementById('create-board-btn').addEventListener('click', async () => {
  const name = elementById('new-board-name').value.trim();
  if (!name) {
    return;
  }
  let view;
  if (state.newBoardType === 'timeline') {
    view = 'timeline';
  } else {
    view = 'kanban';
  }
  const board = touch({
    id: makeId(),
    name,
    view: view,
    columns: state.columnChips.map((columnName) => {
      return touch({ id: makeId(), name: columnName, cards: [] });
    }),
  });
  state.boards.push(board);

  if (!state.isGuest) {
    try {
      await api('POST', '/boards/create', { board });
    } catch (error) {
      toast('Save error', 'error');
    }
    if (window.Sync !== null && window.Sync !== undefined) {
      window.Sync.changed();
    }
  } else {
    saveGuest();
  }

  closeNewBoardModal();
  renderBoardList();
  selectBoard(board.id);
  toast(`Board "${name}" created`);
});

function closeNewBoardModal() {
  if (elementById('new-board-modal').classList.contains('hidden')) {
    return;
  }
  elementById('new-board-modal').classList.add('hidden');
  pageChanged();
}

elementById('new-board-cancel').addEventListener('click', closeNewBoardModal);
elementById('new-board-modal-close').addEventListener('click', closeNewBoardModal);
elementById('new-board-modal').addEventListener('click', (event) => {
  if (event.target === elementById('new-board-modal')) {
    closeNewBoardModal();
  }
});

/* ── Rename board ── */
elementById('edit-board-title-btn').addEventListener('click', () => {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  const name = prompt('Board name:', board.name);
  if (name === null || name === undefined || !name.trim()) {
    return;
  }
  board.name = name.trim();
  touch(board);
  elementById('board-title').textContent = board.name;
  persistBoard(board);
  renderBoardList();
});

/* ── Delete board ── */
elementById('delete-board-btn').addEventListener('click', async () => {
  const board = getActiveBoard();
  if (!board || !confirm(`Delete board "${board.name}"?`)) {
    return;
  }

  if (!state.isGuest) {
    try {
      await api('DELETE', '/boards/delete', { boardId: board.id });
    } catch (error) {
      toast('Delete error', 'error');
    }
  }

  state.boards = state.boards.filter((other) => {
    return other.id !== board.id;
  });
  state.activeBoardId = null;
  saveGuest();
  if (!state.isGuest) {
    if (window.Sync !== null && window.Sync !== undefined) {
      window.Sync.changed();
    }
  }
  renderBoardList();
  elementById('board-title').textContent = 'Select a board';
  hideBoardViews();
  elementById('empty-state').classList.remove('hidden');
  elementById('edit-board-title-btn').classList.add('hidden');
  setBoardActions(false);
  toast('Board deleted');
  if (state.boards.length) {
    selectBoard(state.boards[0].id);
  }
});

/* ── Export / Import ── */
// The file carries each image's bytes as a data URL, so it opens anywhere: in a guest
// browser, or another account. It names no storage address.
elementById('board-export-btn').addEventListener('click', async () => {
  const board = getActiveBoard();
  if (!board) {
    return;
  }
  const copy = JSON.parse(JSON.stringify(board));
  let missing = 0;
  for (const column of copy.columns) {
    for (const card of column.cards) {
      const images = [];
      let cardImages = card.images;
      if (!cardImages) {
        cardImages = [];
      }
      for (const image of cardImages) {
        try {
          images.push({ id: image.id, name: image.name, data: await ImageStore.dataUrl(image) });
        } catch {
          missing = missing + 1;
        }
      }
      card.images = images;
    }
  }
  const blob = new Blob([JSON.stringify(copy, null, 2)], { type: 'application/json' });
  ImageStore.save(blob, `${board.name.replace(/\s+/g, '_')}_kanban.json`);
  let message;
  if (missing) {
    let missingText;
    if (missing === 1) {
      missingText = '1 image';
    } else {
      missingText = `${missing} images`;
    }
    message = `Board exported, without ${missingText} that wouldn’t load`;
  } else {
    message = 'Board exported';
  }
  toast(message);
});

elementById('board-import-btn').addEventListener('click', () => {
  elementById('board-import-file').click();
});
setupFileImport(elementById('board-import-file'), null, (json) => {
  return importBoardFromJSON(json, false);
});

// Reads a JSON file picked with the file input, or dropped on the drop zone if there is one,
// and hands the parsed contents to callback.
function setupFileImport(input, dropZone, callback) {
  if (input !== null && input !== undefined) {
    input.addEventListener('change', (event) => {
      const file = event.target.files[0];
      if (!file) {
        return;
      }
      readJSON(file, callback);
      input.value = '';
    });
  }

  if (dropZone) {
    dropZone.addEventListener('dragover', (event) => {
      event.preventDefault();
      dropZone.classList.add('drag-over');
    });
    dropZone.addEventListener('dragleave', () => {
      dropZone.classList.remove('drag-over');
    });
    dropZone.addEventListener('drop', (event) => {
      event.preventDefault();
      dropZone.classList.remove('drag-over');
      const file = event.dataTransfer.files[0];
      if (file) {
        readJSON(file, callback);
      }
    });
  }
}

function readJSON(file, callback) {
  const reader = new FileReader();
  reader.onload = (event) => {
    try {
      const json = JSON.parse(event.target.result);
      callback(json);
    } catch {
      toast('Invalid JSON file', 'error');
    }
  };
  reader.readAsText(file);
}

// Signed in, an imported board's images go into this account's storage, so they're kept by
// name like any other (an export carries them as data; a file from before, as a public URL).
async function uploadImportedImages(board) {
  let columns = board.columns;
  if (!columns) {
    columns = [];
  }
  for (const column of columns) {
    let cards = column.cards;
    if (!cards) {
      cards = [];
    }
    for (const card of cards) {
      if (!Array.isArray(card.images)) {
        continue;
      }
      const kept = [];
      for (const image of card.images) {
        const imageExists = image !== null && image !== undefined;
        // Already in storage (kept as it is), or with nothing to upload (left out).
        if ((imageExists && image.file) || !(imageExists && (image.data || image.url))) {
          if (imageExists && image.file) {
            kept.push(image);
          }
          continue;
        }
        try {
          const imageData = await ImageStore.dataUrl(image);
          let fileName = image.name;
          if (!fileName) {
            fileName = 'image';
          }
          const result = await api('POST', '/images/upload', { imageData, fileName: fileName });
          let keptId = image.id;
          if (!keptId) {
            keptId = makeId();
          }
          let keptName = image.name;
          if (!keptName) {
            keptName = '';
          }
          kept.push({ id: keptId, file: result.file, name: keptName });
        } catch { /* left out */ }
      }
      card.images = kept;
      const thumbnailKept = kept.some((image) => {
        return image.id === card.thumbnailId;
      });
      if (!thumbnailKept) {
        const firstKept = kept[0];
        let newThumbnailId;
        if (firstKept !== null && firstKept !== undefined) {
          newThumbnailId = firstKept.id;
        }
        if (newThumbnailId === null || newThumbnailId === undefined) {
          newThumbnailId = null;
        }
        card.thumbnailId = newThumbnailId;
      }
    }
  }
}

// Adds an imported board file: as a new board, or (asNew false with a board open) in place
// of the open board. Its images are uploaded first when signed in.
async function importBoardFromJSON(json, asNew) {
  if (!json.id || !json.name || !Array.isArray(json.columns)) {
    toast('Invalid board file', 'error');
    return;
  }
  if (asNew || !state.activeBoardId) {
    json.id = makeId();
  } else {
    json.id = state.activeBoardId;
  }
  if (!state.isGuest) {
    await uploadImportedImages(json);
  }
  const index = state.boards.findIndex((board) => {
    return board.id === json.id;
  });
  if (index !== -1) {
    state.boards[index] = json;
  } else {
    state.boards.push(json);
  }
  await persistBoard(json);
  renderBoardList();
  selectBoard(json.id);
  toast('Board imported');
}

/* ── Persist board ── */
async function persistBoard(board) {
  if (state.isGuest) {
    saveGuest();
    return;
  }
  try {
    await api('PUT', '/boards/update', { board });
  } catch (error) {
    toast('Sync error', 'error');
  }
  if (window.Sync !== null && window.Sync !== undefined) {
    window.Sync.changed();
  }
}

/* ── Sidebar toggle ── */
// On a phone the sidebar slides in over the page, with a dim layer over the rest; a tap
// anywhere outside it (on that layer) closes it. On a computer it collapses to icons instead.
const isPhone = () => {
  return window.innerWidth <= 720;
};

function setSidebarOpen(open) {
  elementById('sidebar').classList.toggle('open', open);
  elementById('sidebar-scrim').classList.toggle('show', open);
}

elementById('sidebar-toggle').addEventListener('click', () => {
  if (isPhone()) {
    setSidebarOpen(false);
  } else {
    elementById('sidebar').classList.toggle('collapsed');
  }
});

elementById('mobile-menu-btn').addEventListener('click', () => {
  if (isPhone()) {
    setSidebarOpen(!elementById('sidebar').classList.contains('open'));
  } else {
    elementById('sidebar').classList.toggle('collapsed');
  }
});

elementById('sidebar-scrim').addEventListener('click', () => {
  setSidebarOpen(false);
});

// Grown past phone width with it open: no dim layer left behind.
window.addEventListener('resize', () => {
  if (!isPhone() && elementById('sidebar').classList.contains('open')) {
    setSidebarOpen(false);
  }
});

/* ── Escape closes modals ── */
document.addEventListener('keydown', (event) => {
  // A tour handles its own Escape (js/tour.js), and leaves the windows under it be.
  if (event.key === 'Escape' && !event.defaultPrevented) {
    if (elementById('sidebar').classList.contains('open')) {
      setSidebarOpen(false);
    }
    closeCardModal();
    closeModal('syncModal');
    closeModal('tourModal');
    elementById('rename-col-modal').classList.add('hidden');
    closeNewBoardModal();
    elementById('col-picker-sheet').classList.add('hidden');
    closeModal('themeModal');
    elementById('profile-modal').classList.add('hidden');
    elementById('delete-account-modal').classList.add('hidden');
    elementById('reorder-cols-modal').classList.add('hidden');
  }
});

/* ── Escape helper ── */
// Makes text safe to put inside HTML: & < > and " become their HTML entities.
function escapeHtml(text) {
  let value = text;
  if (value === null || value === undefined) {
    value = '';
  }
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/* ── Profile Modal ── */
function openProfileModal() {
  if (state.isGuest) {
    toast('Sign in to edit your profile', 'error');
    return;
  }
  let username = state.username;
  if (!username) {
    username = '';
  }
  elementById('profile-username-display').textContent = username;
  elementById('profile-display-name').value = elementById('user-name').textContent;
  elementById('profile-new-pass').value = '';
  elementById('profile-confirm-pass').value = '';
  clearError('profile-error');
  state._pendingAvatarData = null;
  showAvatar(elementById('profile-modal-avatar'), false);
  elementById('profile-modal').classList.remove('hidden');
}

elementById('user-avatar').addEventListener('click', openProfileModal);
elementById('profile-modal-close').addEventListener('click', () => {
  elementById('profile-modal').classList.add('hidden');
});
elementById('profile-modal').addEventListener('click', (event) => {
  if (event.target === elementById('profile-modal')) {
    elementById('profile-modal').classList.add('hidden');
  }
});

elementById('profile-avatar-wrap').addEventListener('click', () => {
  elementById('profile-pic-input').click();
});

elementById('profile-pic-input').addEventListener('change', async (event) => {
  const file = event.target.files[0];
  if (!file) {
    return;
  }
  event.target.value = '';
  const dataUrl = await resizeImage(file, 200);
  // Preview immediately
  elementById('profile-modal-avatar').innerHTML = `<img src="${dataUrl}" alt="" style="width:100%;height:100%;object-fit:cover;" />`;
  state._pendingAvatarData = dataUrl;
});

// Save in the profile window: checks the name and password, then sends whichever of the
// display name, password and new picture changed.
elementById('save-profile-btn').addEventListener('click', async () => {
  const displayName = elementById('profile-display-name').value.trim();
  const newPassword = elementById('profile-new-pass').value;
  const confirmPassword = elementById('profile-confirm-pass').value;
  clearError('profile-error');
  if (!displayName) {
    return showError('profile-error', 'Display name cannot be empty.');
  }
  if (!/^[a-zA-Z0-9_]{3,24}$/.test(displayName)) {
    return showError('profile-error', 'Name must be 3–24 characters (letters, numbers, underscore).');
  }
  if (newPassword && newPassword.length < 8) {
    return showError('profile-error', 'Password must be at least 8 characters.');
  }
  if (newPassword && newPassword !== confirmPassword) {
    return showError('profile-error', 'Passwords do not match.');
  }

  const currentName = elementById('user-name').textContent;
  const payload = {};
  if (displayName !== currentName) {
    payload.displayName = displayName;
  }
  if (newPassword) {
    payload.newPassword = newPassword;
  }

  try {
    elementById('save-profile-btn').disabled = true;
    if (Object.keys(payload).length > 0) {
      const result = await api('PUT', '/auth/update-profile', payload);
      if (result.displayName) {
        elementById('user-name').textContent = result.displayName;
        saveSession({ displayName: result.displayName });
      }
    }
    if (state._pendingAvatarData) {
      await api('PUT', '/auth/update-avatar', { imageData: state._pendingAvatarData });
      state.hasAvatar = true;
      state._pendingAvatarData = null;
      saveSession({ hasAvatar: true });
      // The new one, not the copy of the old one this session already has.
      ImageStore.avatar({ fresh: true }).catch(() => {});
      updateSidebarAvatar();
    }
    elementById('profile-modal').classList.add('hidden');
    toast('Profile updated');
  } catch (error) {
    showError('profile-error', error.message);
  } finally {
    elementById('save-profile-btn').disabled = false;
  }
});

/* ── Delete Account ── */
function showDeleteStep(stepNumber) {
  [1, 2, 3].forEach((step) => {
    elementById(`delete-step-${step}`).classList.toggle('hidden', step !== stepNumber);
  });
}

elementById('delete-account-btn').addEventListener('click', () => {
  elementById('profile-modal').classList.add('hidden');
  showDeleteStep(1);
  elementById('delete-account-modal').classList.remove('hidden');
});

elementById('delete-step1-cancel').addEventListener('click', () => {
  elementById('delete-account-modal').classList.add('hidden');
});
elementById('delete-step1-confirm').addEventListener('click', () => {
  showDeleteStep(2);
});
elementById('delete-step2-cancel').addEventListener('click', () => {
  elementById('delete-account-modal').classList.add('hidden');
});
elementById('delete-step2-confirm').addEventListener('click', () => {
  elementById('delete-confirm-pass').value = '';
  clearError('delete-error');
  showDeleteStep(3);
});
elementById('delete-step3-cancel').addEventListener('click', () => {
  elementById('delete-account-modal').classList.add('hidden');
});
elementById('delete-step3-confirm').addEventListener('click', async () => {
  const password = elementById('delete-confirm-pass').value;
  clearError('delete-error');
  if (!password) {
    return showError('delete-error', 'Please enter your password.');
  }
  try {
    elementById('delete-step3-confirm').disabled = true;
    await api('DELETE', '/auth/delete-account', { password: password });
    localStorage.removeItem('uwuboard_avatar_' + state.session.userId);
    elementById('delete-account-modal').classList.add('hidden');
    logout();
    toast('Account deleted');
  } catch (error) {
    showError('delete-error', error.message);
    elementById('delete-step3-confirm').disabled = false;
  }
});

/* ── Restore session on load ── */
// A session kept in this browser from last time: checked by loading the boards with it,
// and forgotten if that fails.
(async () => {
  const saved = localStorage.getItem('uwuboard_session');
  if (!saved) {
    return;
  }
  let parsed;
  try {
    parsed = JSON.parse(saved);
  } catch {
    localStorage.removeItem('uwuboard_session');
    return;
  }
  const { session, username, displayName } = parsed;
  // A session saved before images were hidden kept the avatar's address; only whether there
  // is one matters now, and setSession() saves it that way.
  let hasAvatar = parsed.hasAvatar;
  if (hasAvatar === null || hasAvatar === undefined) {
    hasAvatar = Boolean(parsed.avatarUrl);
  }
  state.session = session;
  try {
    const data = await api('GET', '/boards/list');
    setSession(session, username, displayName, hasAvatar);
    state.boards = data.boards;
    state.boardsReady = true;
    renderBoardList();
    if (state.boards.length) {
      selectBoard(state.boards[0].id);
    }
  } catch {
    state.session = null;
    localStorage.removeItem('uwuboard_session');
  }
})();

/* ── Show me around (js/tour.js) ── */
elementById('tourBtn').addEventListener('click', () => {
  elementById('tourPicks').innerHTML = Tour.pickers();
  openModal('tourModal');
});

elementById('tourPicks').addEventListener('click', (event) => {
  const button = event.target.closest('[data-tour]');
  if (!button || button.disabled) {
    return;
  }
  closeModal('tourModal');
  // After the window has gone.
  setTimeout(() => {
    Tour.start(button.dataset.tour);
  }, 300);
});

elementById('tourModal').addEventListener('click', (event) => {
  if (event.target === elementById('tourModal')) {
    closeModal('tourModal');
  }
});

/* ── Sync with another device (js/sync.js) ── */
Sync.init();
