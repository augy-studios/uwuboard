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
   nothing here runs until script.js calls Sync.init().

   Note for maintainers: flutter/tool/expected.mjs copies some of the functions and constants
   below out of this file by name (searching for `function name(` and `const name = `), so keep
   those in that shape. */
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

  const elementById = (id) => {
    return document.getElementById(id);
  };
  const allElements = (selector) => {
    return [...document.querySelectorAll(selector)];
  };
  // Presses the element matching `selector`, if there is one.
  const tap = (selector) => {
    const element = document.querySelector(selector);
    if (element !== null && element !== undefined) {
      element.click();
    }
  };

  /* ---- the theme ---- */

  // Each: its label, what it starts as (only one changed from that is offered, so taking the
  // other's never just undoes a choice), its value as words, and how it's read and put in
  // place, through the theme window's own buttons so the window follows as if tapped.
  const SETTINGS = {
    mode: {
      label: 'Light or dark', start: 'light',
      values: () => {
        if (window.MODE_PREFERENCES) {
          return window.MODE_PREFERENCES;
        }
        return [];
      },
      text: (value) => {
        const words = ({ light: 'Light', dark: 'Dark', time: 'Time-based' })[value];
        if (words) {
          return words;
        }
        return value;
      },
      get: () => {
        let preference;
        if (window.getModePreference !== null && window.getModePreference !== undefined) {
          preference = window.getModePreference();
        }
        if (preference) {
          return preference;
        }
        return 'light';
      },
      set: (value) => {
        tap(`#modeToggle [data-mode="${value}"]`);
      },
    },
    colour: {
      label: 'Brand colour', start: 'classic',
      values: () => {
        let themes = window.COLOR_THEMES;
        if (!themes) {
          themes = [];
        }
        return themes.map((theme) => {
          return theme.id;
        });
      },
      text: (value) => {
        let themes = window.COLOR_THEMES;
        if (!themes) {
          themes = [];
        }
        const theme = themes.find((candidate) => {
          return candidate.id === value;
        });
        let label;
        if (theme !== null && theme !== undefined) {
          label = theme.label;
        }
        if (label) {
          return label;
        }
        return value;
      },
      get: () => {
        let storedTheme;
        if (window.getStoredColorTheme !== null && window.getStoredColorTheme !== undefined) {
          storedTheme = window.getStoredColorTheme();
        }
        if (storedTheme) {
          return storedTheme;
        }
        return 'classic';
      },
      set: (value) => {
        tap(`#swatchGrid [data-theme-id="${value}"]`);
      },
    },
  };

  // Whether `value` is one of the values the setting `field` can take.
  const isValidSetting = (field, value) => {
    if (!SETTINGS[field]) {
      return false;
    }
    return typeof value === 'string' && SETTINGS[field].values().includes(value);
  };

  // This device's theme settings that differ from where they start, as { field, value }.
  function ownTheme() {
    return Object.entries(SETTINGS)
      .filter(([, setting]) => {
        return setting.get() !== setting.start;
      })
      .map(([field, setting]) => {
        return { field, value: setting.get() };
      });
  }

  /* ---- boards ---- */

  const clone = (value) => {
    return JSON.parse(JSON.stringify(value));
  };
  // A time stamp as a number to compare: anything that isn't a positive number counts as 0.
  const stamp = (value) => {
    if (Number.isFinite(value) && value > 0) {
      return value;
    } else {
      return 0;
    }
  };

  // A board as another device gets it in a list: each image by id and name, no bytes.
  function listBoard(board) {
    const copy = clone(board);
    let columns = copy.columns;
    if (!columns) {
      columns = [];
    }
    for (const column of columns) {
      let cards = column.cards;
      if (!cards) {
        cards = [];
      }
      for (const card of cards) {
        let images = card.images;
        if (!images) {
          images = [];
        }
        card.images = images.map((image) => {
          let name = image.name;
          if (!name) {
            name = '';
          }
          return { id: image.id, name };
        });
      }
    }
    return copy;
  }

  const ownBoards = () => {
    return S.boards.map(listBoard);
  };

  // Boards from the other device, checked field by field. They're input from another machine,
  // so anything malformed is dropped rather than stored, and duplicates go too.
  const ID_PATTERN = /^[\w-]{1,64}$/;
  const isId = (value) => {
    return typeof value === 'string' && ID_PATTERN.test(value);
  };
  // A string cut to `max` characters, or '' for anything that isn't a string.
  const text = (value, max) => {
    if (typeof value === 'string') {
      return value.slice(0, max);
    } else {
      return '';
    }
  };
  // An array cut to `max` items, or [] for anything that isn't an array.
  const list = (value, max) => {
    if (Array.isArray(value)) {
      return value.slice(0, max);
    } else {
      return [];
    }
  };
  const PRIORITIES = ['', 'low', 'medium', 'high', 'urgent'];

  // One card from the other device, checked and rebuilt field by field, or null when it hasn't
  // a valid id. Text is cut to length, dates and colours must be well formed, and the
  // timeline's fields are only there when set.
  function cleanCard(raw) {
    if (!raw || !isId(raw.id)) {
      return null;
    }
    const images = list(raw.images, MAX_IMAGES)
      .filter((image) => {
        return image && isId(image.id);
      })
      .map((image) => {
        return { id: image.id, name: text(image.name, 200) };
      });
    let title = text(raw.title, 500);
    if (!title) {
      title = 'Untitled';
    }
    let due;
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw.due)) {
      due = raw.due;
    } else {
      due = '';
    }
    let priority;
    if (PRIORITIES.includes(raw.priority)) {
      priority = raw.priority;
    } else {
      priority = '';
    }
    // The thumbnail must be one of the card's images; otherwise the first image, or none.
    let thumbnailId;
    if (images.some((image) => { return image.id === raw.thumbnailId; })) {
      thumbnailId = raw.thumbnailId;
    } else {
      thumbnailId = null;
      const firstImage = images[0];
      if (firstImage !== null && firstImage !== undefined && firstImage.id !== null && firstImage.id !== undefined) {
        thumbnailId = firstImage.id;
      }
    }
    const card = {
      id: raw.id,
      title,
      description: text(raw.description, 20000),
      due,
      priority,
      labels: list(raw.labels, 30)
        .filter((label) => {
          return label && typeof label.text === 'string' && label.text.trim() && /^#[0-9a-f]{6}$/i.test(label.color);
        })
        .map((label) => {
          return { text: label.text.trim().slice(0, 60), color: label.color };
        }),
      checklist: list(raw.checklist, 300)
        .filter((item) => {
          return item && typeof item.text === 'string' && item.text.trim();
        })
        .map((item) => {
          return { text: item.text.slice(0, 500), done: item.done === true };
        }),
      images,
      thumbnailId,
    };
    // A timeline's (js/timeline.js): when it starts, whether it's a milestone, and the cards
    // it waits for, by id. Only there when set, as on the board they came from.
    if (/^\d{4}-\d{2}-\d{2}$/.test(raw.start)) {
      card.start = raw.start;
    }
    if (raw.milestone === true) {
      card.milestone = true;
    }
    if (Array.isArray(raw.dependsOn) && raw.dependsOn.length) {
      card.dependsOn = [...new Set(raw.dependsOn.filter((dependencyId) => {
        return isId(dependencyId) && dependencyId !== raw.id;
      }))].slice(0, 50);
    }
    card.updatedAt = stamp(raw.updatedAt);
    return card;
  }

  // The boards from the other device, checked and rebuilt, or null when it isn't a list at
  // all. A board, column or card whose id was already seen is dropped, as is a board with no
  // name.
  function cleanBoards(raw) {
    if (!Array.isArray(raw)) {
      return null;
    }
    const seen = new Set();
    // True the first time a key is passed, false after that.
    const once = (key) => {
      if (seen.has(key)) {
        return false;
      }
      seen.add(key);
      return true;
    };
    return raw.slice(0, MAX_BOARDS)
      .filter((board) => {
        if (!(board && isId(board.id) && typeof board.name === 'string' && board.name.trim())) {
          return false;
        }
        return once(`board:${board.id}`);
      })
      .map((board) => {
        // Shown as columns or as a timeline; a board from before there was a choice is columns.
        let view;
        if (board.view === 'timeline') {
          view = 'timeline';
        } else {
          view = 'kanban';
        }
        return {
          id: board.id,
          name: board.name.trim().slice(0, 120),
          view,
          updatedAt: stamp(board.updatedAt),
          columns: list(board.columns, MAX_COLUMNS)
            .filter((column) => {
              if (!(column && isId(column.id) && typeof column.name === 'string')) {
                return false;
              }
              return once(`col:${board.id}/${column.id}`);
            })
            .map((column) => {
              let name = column.name.trim().slice(0, 120);
              if (!name) {
                name = 'Column';
              }
              return {
                id: column.id,
                name,
                updatedAt: stamp(column.updatedAt),
                cards: list(column.cards, MAX_CARDS).map(cleanCard).filter((card) => {
                  if (!card) {
                    return false;
                  }
                  return once(`card:${board.id}/${card.id}`);
                }),
              };
            }),
        };
      });
  }

  // The theme settings from the other device: only valid ones, and each setting once.
  function cleanTheme(raw) {
    const seen = new Set();
    return list(raw, 10)
      .filter((setting) => {
        let field;
        let value;
        if (setting !== null && setting !== undefined) {
          field = setting.field;
          value = setting.value;
        }
        if (!isValidSetting(field, value)) {
          return false;
        }
        if (seen.has(setting.field)) {
          return false;
        }
        seen.add(setting.field);
        return true;
      })
      .map((setting) => {
        return { field: setting.field, value: setting.value };
      });
  }

  // What a card is, for telling whether two copies differ: everything but when it was stamped,
  // and its images by id.
  const cardSignature = (card) => {
    let description = card.description;
    if (!description) {
      description = '';
    }
    let due = card.due;
    if (!due) {
      due = '';
    }
    let priority = card.priority;
    if (!priority) {
      priority = '';
    }
    let labels = card.labels;
    if (!labels) {
      labels = [];
    }
    let checklist = card.checklist;
    if (!checklist) {
      checklist = [];
    }
    let images = card.images;
    if (!images) {
      images = [];
    }
    let thumbnailId = card.thumbnailId;
    if (!thumbnailId) {
      thumbnailId = null;
    }
    let start = card.start;
    if (!start) {
      start = '';
    }
    let dependsOn = card.dependsOn;
    if (!dependsOn) {
      dependsOn = [];
    }
    return JSON.stringify([
      card.title, description, due, priority, labels, checklist,
      images.map((image) => { return image.id; }), thumbnailId,
      start, Boolean(card.milestone), [...dependsOn].sort(),
    ]);
  };

  // Merges `source` into `destination` in place and says how many things that changed. Adds
  // what `destination` hasn't got; for what both have, the copy changed last wins. Never
  // removes anything.
  function mergeBoardInto(destination, source) {
    let changes = 0;
    if (stamp(source.updatedAt) > stamp(destination.updatedAt)) {
      if (source.name !== destination.name) {
        destination.name = source.name;
        changes = changes + 1;
      }
      // How it's shown goes with the name: whichever was changed last.
      let sourceView = source.view;
      if (!sourceView) {
        sourceView = 'kanban';
      }
      let destinationView = destination.view;
      if (!destinationView) {
        destinationView = 'kanban';
      }
      if (sourceView !== destinationView) {
        destination.view = source.view;
        changes = changes + 1;
      }
      destination.updatedAt = source.updatedAt;
    }

    // The columns: new ones added (empty for now), and a renamed one renamed if renamed last.
    const columnsById = new Map(destination.columns.map((column) => {
      return [column.id, column];
    }));
    for (const sourceColumn of source.columns) {
      const destinationColumn = columnsById.get(sourceColumn.id);
      if (!destinationColumn) {
        const added = { id: sourceColumn.id, name: sourceColumn.name, updatedAt: stamp(sourceColumn.updatedAt), cards: [] };
        destination.columns.push(added);
        columnsById.set(sourceColumn.id, added);
        changes = changes + 1;
      } else if (stamp(sourceColumn.updatedAt) > stamp(destinationColumn.updatedAt)) {
        if (sourceColumn.name !== destinationColumn.name) {
          destinationColumn.name = sourceColumn.name;
          changes = changes + 1;
        }
        destinationColumn.updatedAt = sourceColumn.updatedAt;
      }
    }

    // Where each of destination's cards is now.
    const columnOfCard = new Map();
    for (const column of destination.columns) {
      for (const card of column.cards) {
        columnOfCard.set(card.id, column);
      }
    }

    // The cards: new ones added, and for one on both, the copy changed last kept, in the
    // column the source has it in.
    for (const sourceColumn of source.columns) {
      const targetColumn = columnsById.get(sourceColumn.id);
      for (const card of sourceColumn.cards) {
        const currentColumn = columnOfCard.get(card.id);
        if (!currentColumn) {
          targetColumn.cards.push(clone(card));
          columnOfCard.set(card.id, targetColumn);
          changes = changes + 1;
          continue;
        }
        const cardIndex = currentColumn.cards.findIndex((existingCard) => {
          return existingCard.id === card.id;
        });
        const existing = currentColumn.cards[cardIndex];
        if (stamp(card.updatedAt) <= stamp(existing.updatedAt)) {
          continue;
        }
        if (currentColumn === targetColumn && cardSignature(existing) === cardSignature(card)) {
          existing.updatedAt = card.updatedAt;
          continue;
        }
        // Its own images come along by id; resolveImages() fills in the ones this device has.
        const copy = clone(card);
        if (currentColumn === targetColumn) {
          currentColumn.cards[cardIndex] = copy;
        } else {
          currentColumn.cards.splice(cardIndex, 1);
          targetColumn.cards.push(copy);
          columnOfCard.set(card.id, targetColumn);
        }
        changes = changes + 1;
      }
    }
    return changes;
  }

  // Whether merging `source` into the list of boards `boards` would change anything there.
  function wouldChange(boards, source) {
    const destination = boards.find((board) => {
      return board.id === source.id;
    });
    if (!destination) {
      return true;
    }
    return mergeBoardInto(clone(destination), source) > 0;
  }

  // Every image this device has, by id, wherever it is.
  function ownImages() {
    const images = new Map();
    for (const board of S.boards) {
      for (const column of board.columns) {
        for (const card of column.cards) {
          let cardImages = card.images;
          if (!cardImages) {
            cardImages = [];
          }
          for (const image of cardImages) {
            images.set(image.id, image);
          }
        }
      }
    }
    return images;
  }

  // A merged card's images as this device keeps them: its own copy where it has the image,
  // otherwise the bytes that came over (uploaded first when signed in). One that didn't arrive
  // is left out, and the thumbnail moves to one that's there.
  async function resolveImages(board, local) {
    for (const column of board.columns) {
      for (const card of column.cards) {
        if (card.images === null || card.images === undefined || !card.images.length) {
          continue;
        }
        const kept = [];
        for (const image of card.images) {
          if (image.file || image.data || image.url) {
            kept.push(image);
            continue;
          }
          if (local.has(image.id)) {
            kept.push(local.get(image.id));
            continue;
          }
          const data = sync.received.get(image.id);
          if (!data) {
            continue;
          }
          if (S.isGuest) {
            kept.push({ id: image.id, name: image.name, data });
            continue;
          }
          try {
            let fileName = image.name;
            if (!fileName) {
              fileName = 'image';
            }
            const response = await api('POST', '/images/upload', { imageData: data, fileName });
            const entry = { id: image.id, name: image.name, file: response.file };
            local.set(image.id, entry);
            kept.push(entry);
          } catch { /* left out; the card keeps the rest */ }
        }
        card.images = kept;
        if (!kept.some((image) => { return image.id === card.thumbnailId; })) {
          let thumbnailId = null;
          const firstKept = kept[0];
          if (firstKept !== null && firstKept !== undefined && firstKept.id !== null && firstKept.id !== undefined) {
            thumbnailId = firstKept.id;
          }
          card.thumbnailId = thumbnailId;
        }
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
        count = count + 1;
      }
    }

    const local = ownImages();
    const changed = [];
    for (const source of boards) {
      let destination = S.boards.find((board) => {
        return board.id === source.id;
      });
      if (!destination) {
        destination = { id: source.id, name: source.name, view: source.view, updatedAt: stamp(source.updatedAt), columns: [] };
        mergeBoardInto(destination, source);
        S.boards.push(destination);
        changed.push(destination);
      } else if (mergeBoardInto(destination, source) > 0) {
        changed.push(destination);
      }
    }
    for (const board of changed) {
      await resolveImages(board, local);
    }

    if (changed.length) {
      if (S.isGuest) {
        saveGuest();
      } else {
        await Promise.all(changed.map((board) => {
          return api('PUT', '/boards/update', { board }).catch(() => {
            return toast('Sync error', 'error');
          });
        }));
      }
      boardsChanged(changed);
    }
    return count + changed.length;
  }

  /* ---- sessions ---- */

  const sync = {
    role: null,        // 'host' | 'guest' while a session runs
    connection: null,  // its P2P.Host or P2P.Guest
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
    try {
      const stored = localStorage.getItem(key);
      if (stored) {
        return stored;
      }
      return '';
    } catch {
      return '';
    }
  }

  function writeKey(key, value) {
    try {
      if (value) {
        localStorage.setItem(key, value);
      } else {
        localStorage.removeItem(key);
      }
    } catch { /* private mode: codes just aren't remembered */ }
  }

  const syncLink = (code) => {
    return `${location.origin}/#sync/${code}`;
  };

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
    const connection = sync.connection;
    // Cleared first, so the status the closing connection reports on its way out is ignored.
    sync.connection = null;
    if (connection) {
      if (bye && sync.role === 'guest') {
        connection.leave();
      } else {
        connection.close();
      }
    }
    for (const timer of [...sync.pending.values(), ...sync.pulls.values()]) {
      clearTimeout(timer);
    }
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
    if (sync.role) {
      endSession({ bye: true });
    }
  }

  // Starts showing a code for the other device to enter: the one used last time if it's still
  // valid, with its link and QR code, and listens for the other device joining and talking.
  async function startHosting() {
    if (sync.role) {
      return;
    }
    const stored = readKey(HOST_KEY);
    let code;
    if (P2P.isValidCode(stored)) {
      code = stored;
    } else {
      code = P2P.generateCode();
    }
    writeKey(HOST_KEY, code);

    beginSession('host');
    elementById('syncCode').textContent = code;
    elementById('syncLink').textContent = syncLink(code);
    if (window.qrToSvg) {
      elementById('syncQr').innerHTML = qrToSvg(syncLink(code));
    } else {
      elementById('syncQr').innerHTML = '';
    }

    const host = new P2P.Host({ maxGuests: 1 });
    sync.connection = host;
    host.addEventListener('status', ({ detail }) => {
      if (sync.connection !== host) {
        return;
      }
      // The stored code is held by something else: another tab, or the broker not yet letting
      // go of it after a reload. A fresh one, once; a second collision in a row is not stale.
      if (detail.taken && !sync.retriedTaken) {
        sync.retriedTaken = true;
        newHostCode();
        return;
      }
      if (detail.status === 'error') {
        if (detail.taken) {
          writeKey(HOST_KEY, '');
        }
        endSession({ text: detail.message, tone: 'error' });
        return;
      }
      if (detail.status === 'waiting') {
        sync.retriedTaken = false;
      }
      onStatus(detail.status);
    });
    // A newcomer replaces the device that was connected, whose boards no longer apply.
    host.addEventListener('join', () => {
      if (sync.connection !== host) {
        return;
      }
      sync.theirs = null;
      renderList();
    });
    host.addEventListener('message', ({ detail }) => {
      if (sync.connection === host) {
        onMessage(detail.message);
      }
    });
    render();

    try {
      await host.start(code);
    } catch {
      if (sync.connection === host) {
        endSession({ text: 'Could not load syncing. Check your connection.', tone: 'error' });
      }
    }
  }

  // Gives up the code on show for a fresh one, which the old one stops working the moment it does.
  async function newHostCode(note = '') {
    endSession();
    writeKey(HOST_KEY, '');
    await startHosting();
    if (note) {
      showNote(note);
    }
  }

  // Connects to the device showing the code typed in `input`, and listens for what it says.
  async function join(input) {
    const code = P2P.normaliseCode(input);
    if (!P2P.isValidCode(code)) {
      showStatus(`The code is the ${P2P.CODE_LENGTH} letters and numbers on the other device’s screen.`, 'error');
      return;
    }
    if (sync.role) {
      endSession();
    }

    beginSession('guest');
    writeKey(LAST_KEY, code);
    elementById('syncCodeInput').value = code;

    const guest = new P2P.Guest();
    sync.connection = guest;
    guest.addEventListener('status', ({ detail }) => {
      if (sync.connection !== guest) {
        return;
      }
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
      if (sync.connection === guest) {
        onMessage(detail.message);
      }
    });
    render();

    try {
      await guest.connect(code);
    } catch {
      if (sync.connection === guest) {
        endSession({ text: 'Could not load syncing. Check your connection.', tone: 'error' });
      }
    }
  }

  function onStatus(status) {
    const previousStatus = sync.status;
    sync.status = status;
    if (status !== 'connected') {
      sync.theirs = null;
    } else if (previousStatus !== 'connected' && sync.role === 'guest') {
      // The host answers p2p.js's hello with its boards; these are ours for it.
      sendBoards();
    }
    render();
  }

  const send = (message) => {
    if (sync.connection !== null && sync.connection !== undefined) {
      sync.connection.send(message);
    }
  };

  // Ids for add and pull, odd on the host and even on the guest, so an answer to one side's
  // request is never taken for an answer to the other's.
  const nextId = () => {
    sync.lastId = sync.lastId + 1;
    let oddOrEven;
    if (sync.role === 'host') {
      oddOrEven = 1;
    } else {
      oddOrEven = 0;
    }
    return sync.lastId * 2 + oddOrEven;
  };

  function sendBoards() {
    send({ type: 'boards', boards: ownBoards(), theme: ownTheme() });
  }

  // This device's boards changed (script.js): the other side's lists follow.
  let changeTimer = null;
  function changed() {
    if (sync.status !== 'connected') {
      return;
    }
    clearTimeout(changeTimer);
    changeTimer = setTimeout(() => {
      if (sync.status === 'connected') {
        sendBoards();
      }
      renderList();
    }, 300);
  }

  /* ---- images over the channel ---- */

  // Sends the images in `boards` that the other side hasn't got, ahead of whatever needs them,
  // and says how many characters that was. Stops if the session ends meanwhile.
  async function sendImages(boards) {
    const connection = sync.connection;
    const theirs = new Set();
    let theirBoards;
    if (sync.theirs !== null && sync.theirs !== undefined) {
      theirBoards = sync.theirs.boards;
    }
    if (!theirBoards) {
      theirBoards = [];
    }
    for (const board of theirBoards) {
      for (const column of board.columns) {
        for (const card of column.cards) {
          for (const image of card.images) {
            theirs.add(image.id);
          }
        }
      }
    }
    let sent = 0;
    for (const board of boards) {
      for (const column of board.columns) {
        for (const card of column.cards) {
          let images = card.images;
          if (!images) {
            images = [];
          }
          for (const image of images) {
            if (theirs.has(image.id)) {
              continue;
            }
            theirs.add(image.id);
            let data;
            try {
              data = await ImageStore.dataUrl(image);
            } catch {
              continue;
            }
            if (sync.connection !== connection) {
              return sent;
            }
            if (typeof data !== 'string' || data.length > MAX_IMAGE_CHARS) {
              continue;
            }
            const total = Math.ceil(data.length / CHUNK);
            for (let seq = 0; seq < total; seq = seq + 1) {
              send({ type: 'img', img: image.id, seq, total, part: data.slice(seq * CHUNK, (seq + 1) * CHUNK) });
            }
            sent = sent + data.length;
          }
        }
      }
    }
    return sent;
  }

  const DATA_URL_PATTERN = /^data:image\/(png|jpeg|webp|gif);base64,[A-Za-z0-9+/=]+$/;

  // One chunk of an image. Kept until the image is whole, then checked as a whole.
  function onChunk(message) {
    const total = Math.floor(Number(message.total));
    const seq = Math.floor(Number(message.seq));
    if (!isId(message.img) || typeof message.part !== 'string' || message.part.length > CHUNK
      || !(total >= 1 && total <= Math.ceil(MAX_IMAGE_CHARS / CHUNK)) || !(seq >= 0 && seq < total)) {
      return;
    }
    if (sync.received.has(message.img)) {
      return;
    }
    let entry = sync.incoming.get(message.img);
    if (!entry || entry.total !== total) {
      entry = { total, parts: new Array(total), have: 0 };
      sync.incoming.set(message.img, entry);
    }
    if (entry.parts[seq] === undefined) {
      entry.parts[seq] = message.part;
      entry.have = entry.have + 1;
    }
    // An import still arriving is still alive.
    for (const [id, timer] of sync.pulls) {
      clearTimeout(timer);
      sync.pulls.set(id, pullTimer(id));
    }
    if (entry.have < total) {
      return;
    }
    sync.incoming.delete(message.img);
    const data = entry.parts.join('');
    if (DATA_URL_PATTERN.test(data)) {
      sync.received.set(message.img, data);
    }
  }

  /* ---- messages ---- */

  // Everything the other device sends goes through here. Unknown types are ignored, never
  // thrown on: the other device may be a version ahead or behind.
  function onMessage(message) {
    switch (message.type) {
      case 'hello':
        if (sync.role === 'host') {
          sendBoards();
        }
        break;

      case 'boards': {
        const boards = cleanBoards(message.boards);
        if (!boards) {
          break;
        }
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
        if (timer === undefined) {
          break;
        }
        clearTimeout(timer);
        sync.pending.delete(message.id);
        let reportedCount = Math.floor(Number(message.count));
        if (!reportedCount) {
          reportedCount = 0;
        }
        const count = Math.max(0, Math.min(MAX_BOARDS + 10, reportedCount));
        if (count) {
          let things;
          if (count === 1) {
            things = '1 new thing';
          } else {
            things = `${count} new things`;
          }
          showNote(`Sent. The other device took ${things}.`);
        } else {
          showNote('Sent. The other device already had all of those.');
        }
        break;
      }

      case 'pull':
        onPull(message);
        break;

      // The guest is finished with this code, so nobody else gets to use it.
      case 'bye':
        if (sync.role === 'host') {
          newHostCode('The other device disconnected. The old code no longer works; this is a new one.');
        }
        break;

      default:
        break;
    }
  }

  // Boards (and maybe theme) the other device sent, or sent back in answer to this device's
  // import: merged in, answered with how many things changed, and said on screen.
  async function onAdd(message) {
    const boards = cleanBoards(message.boards);
    if (!boards || !Number.isInteger(message.id)) {
      return;
    }
    const connection = sync.connection;
    // An answer to this device's own import, or something the other side sent.
    const pulled = sync.pulls.has(message.id);
    if (pulled) {
      clearTimeout(sync.pulls.get(message.id));
      sync.pulls.delete(message.id);
    }
    const hasImages = boards.some((board) => {
      return board.columns.some((column) => {
        return column.cards.some((card) => {
          return card.images.length;
        });
      });
    });
    if (hasImages) {
      showNote('Saving…');
    }
    const count = await mergeIn(boards, cleanTheme(message.theme));
    if (sync.connection !== connection) {
      return;
    }
    send({ type: 'added', id: message.id, count });
    if (count) {
      sendBoards();
    }
    if (pulled) {
      if (count === 1) {
        showNote('Imported 1 thing to this device.');
      } else {
        showNote(`Imported ${count} things to this device.`);
      }
    } else if (count) {
      let things;
      if (count === 1) {
        things = '1 thing';
      } else {
        things = `${count} things`;
      }
      showNote(`The other device sent ${things}, now saved here.`);
    } else {
      showNote('The other device sent things this device already has.');
    }
    renderList();
  }

  // The other side importing some of this device's boards: they go as if sent from here.
  async function onPull(message) {
    if (!Number.isInteger(message.id) || !Array.isArray(message.boards)) {
      return;
    }
    const ids = new Set(message.boards.filter(isId));
    const chosen = S.boards.filter((board) => {
      return ids.has(board.id);
    }).map(clone);
    const connection = sync.connection;
    await sendImages(chosen);
    if (sync.connection !== connection) {
      return;
    }
    send({ type: 'add', id: message.id, boards: chosen.map(listBoard), theme: [] });
  }

  /* ---- copying ---- */

  // Every board and setting on one side as items, each keyed the same way on both devices.
  function items(side) {
    if (!side) {
      return [];
    }
    return [
      ...side.boards.map((board) => {
        return { key: `board:${board.id}`, kind: 'board', item: board };
      }),
      ...side.theme.map((setting) => {
        return { key: `setting:${setting.field}=${setting.value}`, kind: 'setting', item: setting };
      }),
    ];
  }

  // This device's boards and theme; and, for the tab on show, the side copied from and to.
  const ownSide = () => {
    return { boards: ownBoards(), theme: ownTheme() };
  };
  const sourceSide = () => {
    if (sync.tab === 'import') {
      return sync.theirs;
    } else {
      return ownSide();
    }
  };
  const destinationSide = () => {
    if (sync.tab === 'import') {
      return ownSide();
    } else {
      return sync.theirs;
    }
  };

  // What's on offer in the tab on show, and whether each would change anything at the other end.
  function offered() {
    const from = sourceSide();
    const to = destinationSide();
    if (!from || !to) {
      return [];
    }
    return items(from).map((offer) => {
      if (offer.kind === 'setting') {
        // The value the setting has at the other end now.
        let currentValue;
        if (sync.tab === 'import') {
          currentValue = SETTINGS[offer.item.field].get();
        } else {
          const theirSetting = to.theme.find((setting) => {
            return setting.field === offer.item.field;
          });
          if (theirSetting !== null && theirSetting !== undefined) {
            currentValue = theirSetting.value;
          }
          if (!currentValue) {
            currentValue = SETTINGS[offer.item.field].start;
          }
        }
        const there = offer.item.value === currentValue;
        return { ...offer, done: there, update: false };
      }
      const exists = to.boards.some((board) => {
        return board.id === offer.item.id;
      });
      const done = !wouldChange(to.boards, offer.item);
      return { ...offer, done, update: exists && !done };
    });
  }

  // Copies what's ticked in the tab on show. Importing applies the theme here straight away
  // and asks the other device for the boards; sending sends the images first, then the boards
  // and theme, and waits (longer for more images) for the other device to answer.
  async function copyPicked() {
    const picked = sync.picked[sync.tab];
    if (!picked.size || !sourceSide()) {
      return;
    }
    const chosen = items(sourceSide()).filter((offer) => {
      return picked.has(offer.key);
    });
    const boards = chosen.filter((offer) => {
      return offer.kind === 'board';
    }).map((offer) => {
      return offer.item;
    });
    const theme = chosen.filter((offer) => {
      return offer.kind === 'setting';
    }).map((offer) => {
      return offer.item;
    });
    picked.clear();

    if (sync.tab === 'import') {
      // The theme straight away; boards are pulled, so their images come with them.
      let count;
      if (theme.length) {
        count = await mergeIn([], theme);
      } else {
        count = 0;
      }
      if (boards.length) {
        const id = nextId();
        sync.pulls.set(id, pullTimer(id));
        send({
          type: 'pull',
          id,
          boards: boards.map((board) => {
            return board.id;
          }),
        });
        if (boards.length === 1) {
          showNote('Importing 1 board…');
        } else {
          showNote(`Importing ${boards.length} boards…`);
        }
      } else {
        if (count === 1) {
          showNote('Imported 1 thing to this device.');
        } else {
          showNote(`Imported ${count} things to this device.`);
        }
      }
      if (count) {
        sendBoards();
      }
    } else {
      const id = nextId();
      const chosenCount = chosen.length;
      if (chosenCount === 1) {
        showNote('Sending 1 thing…');
      } else {
        showNote(`Sending ${chosenCount} things…`);
      }
      const fullBoards = S.boards.filter((board) => {
        return boards.some((chosenBoard) => {
          return chosenBoard.id === board.id;
        });
      }).map(clone);
      const connection = sync.connection;
      const imageCharacters = await sendImages(fullBoards);
      if (sync.connection !== connection) {
        return;
      }
      send({ type: 'add', id, boards: fullBoards.map(listBoard), theme });
      // More time for every 100 KB of images.
      sync.pending.set(id, setTimeout(() => {
        sync.pending.delete(id);
        showNote('No answer from the other device. Check it still says connected, then try again.', 'error');
      }, ACK_MS + Math.ceil(imageCharacters / 100000) * 2000));
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
    const link = elementById('syncLink').textContent;
    if (!link || !navigator.clipboard) {
      return;
    }
    navigator.clipboard.writeText(link)
      .then(() => {
        return showNote('Link copied.');
      })
      .catch(() => {
        return showNote('Couldn’t copy the link. Type the code on the other device instead.', 'error');
      });
  }

  /* ---- screen wake lock ---- */

  // A phone that locks mid-sync suspends the page and drops the channel with it.
  async function holdScreenOn() {
    if (!sync.role || sync.wakeLock || !navigator.wakeLock) {
      return;
    }
    try {
      const lock = await navigator.wakeLock.request('screen');
      if (!sync.role) {
        lock.release().catch(() => {});
        return;
      }
      sync.wakeLock = lock;
      lock.addEventListener('release', () => {
        if (sync.wakeLock === lock) {
          sync.wakeLock = null;
        }
      });
    } catch { /* battery saver, or not allowed: the session carries on without it */ }
  }

  function releaseScreen() {
    if (sync.wakeLock !== null && sync.wakeLock !== undefined) {
      sync.wakeLock.release().catch(() => {});
    }
    sync.wakeLock = null;
  }

  /* ---- rendering ---- */

  function showStatus(message, tone = 'busy') {
    elementById('syncStatus').hidden = !message;
    elementById('syncStatusText').textContent = message;
    elementById('syncStatus').querySelector('.statusDot').className = `statusDot ${tone}`;
  }

  function showNote(message, tone = '') {
    elementById('syncNote').hidden = !message;
    elementById('syncNote').textContent = message;
    elementById('syncNote').classList.toggle('error', tone === 'error');
  }

  // Shows the parts of the window that fit the session's state (start, hosting, connected),
  // the end button's label, the status line, and the list.
  function render() {
    const { role, status } = sync;
    const connected = status === 'connected';

    elementById('syncStart').hidden = Boolean(role);
    elementById('syncHost').hidden = role !== 'host' || connected;
    elementById('syncLive').hidden = !connected;
    elementById('syncControls').hidden = !role;
    elementById('syncNewCode').hidden = role !== 'host';
    if (connected) {
      elementById('syncEnd').textContent = 'Disconnect';
    } else if (role === 'host') {
      elementById('syncEnd').textContent = 'Stop';
    } else {
      elementById('syncEnd').textContent = 'Cancel';
    }

    if (role === 'host' && status === 'waiting') {
      showStatus('Waiting for the other device. On it, open Sync and enter this code, or scan the QR code with its camera.', 'warn');
    } else if (role && status === 'connecting') {
      if (role === 'host') {
        showStatus('Getting the code ready…', 'busy');
      } else {
        showStatus('Connecting to the other device…', 'busy');
      }
    } else if (connected) {
      showStatus('Connected to the other device.', 'ok');
    }

    renderList();
  }

  // A board's size in words, for under its name: "3 columns · 12 cards · 2 images".
  function boardSummary(board) {
    const cards = board.columns.reduce((total, column) => {
      return total + column.cards.length;
    }, 0);
    const images = board.columns.reduce((total, column) => {
      return total + column.cards.reduce((columnTotal, card) => {
        let imageCount = 0;
        if (card.images !== null && card.images !== undefined && card.images.length) {
          imageCount = card.images.length;
        }
        return columnTotal + imageCount;
      }, 0);
    }, 0);
    const parts = [];
    if (board.columns.length === 1) {
      parts.push('1 column');
    } else {
      parts.push(`${board.columns.length} columns`);
    }
    if (cards === 1) {
      parts.push('1 card');
    } else {
      parts.push(`${cards} cards`);
    }
    if (images) {
      if (images === 1) {
        parts.push('1 image');
      } else {
        parts.push(`${images} images`);
      }
    }
    return parts.join(' · ');
  }

  // Draws the tabs and the list of what's on offer in the tab on show: a row with a tick box
  // for each board and setting, those already at the other end ticked off and disabled.
  function renderList() {
    if (sync.status !== 'connected') {
      return;
    }
    const importing = sync.tab === 'import';
    allElements('#syncTabs [data-sync-tab]').forEach((tab) => {
      const isActive = tab.dataset.syncTab === sync.tab;
      tab.classList.toggle('active', isActive);
      tab.setAttribute('aria-selected', String(isActive));
    });
    if (importing) {
      elementById('syncListNote').textContent = 'The other device’s boards and theme. Tick the ones to copy to this device.';
    } else {
      elementById('syncListNote').textContent = 'This device’s boards and theme. Tick the ones to copy to the other device.';
    }

    const picked = sync.picked[sync.tab];
    if (!sync.theirs) {
      picked.clear();
      elementById('syncList').innerHTML = '<div class="syncEmpty">Waiting for the other device…</div>';
      renderPicks([]);
      return;
    }

    const offers = offered();
    // A pick the other end has since got some other way isn't on offer any more.
    const openKeys = new Set(offers.filter((offer) => {
      return !offer.done;
    }).map((offer) => {
      return offer.key;
    }));
    for (const key of picked) {
      if (!openKeys.has(key)) {
        picked.delete(key);
      }
    }

    // One row of the list, as HTML.
    const row = ({ key, kind, item, done, update }) => {
      let title;
      let summary;
      if (kind === 'board') {
        title = item.name;
        summary = boardSummary(item);
      } else {
        title = SETTINGS[item.field].label;
        summary = SETTINGS[item.field].text(item.value);
      }
      let tag;
      if (done) {
        if (importing) {
          tag = 'Already here';
        } else {
          tag = 'Already there';
        }
      } else if (update) {
        tag = 'Has changes';
      } else {
        tag = '';
      }
      let doneClass;
      let checkboxState;
      if (done) {
        doneClass = ' done';
        checkboxState = ' disabled';
      } else {
        doneClass = '';
        if (picked.has(key)) {
          checkboxState = ' checked';
        } else {
          checkboxState = '';
        }
      }
      let tagHtml;
      if (tag) {
        tagHtml = `<span class="syncTag">${tag}</span>`;
      } else {
        tagHtml = '';
      }
      return `<label class="syncItem${doneClass}">` +
        `<input type="checkbox" data-sync-key="${esc(key)}"${checkboxState}>` +
        `<span class="syncItemText"><span class="name">${esc(title)}</span><span class="sub">${esc(summary)}</span></span>` +
        tagHtml +
        '</label>';
    };
    // The rows of one kind under a heading, or nothing when there are none.
    const group = (kind, label) => {
      const rows = offers.filter((offer) => {
        return offer.kind === kind;
      });
      if (rows.length) {
        return `<div class="syncGroupLabel">${label}</div>${rows.map(row).join('')}`;
      } else {
        return '';
      }
    };
    let listHtml = group('board', 'Boards') + group('setting', 'Theme');
    if (!listHtml) {
      let emptyText;
      if (importing) {
        emptyText = 'The other device has nothing to share yet.';
      } else {
        emptyText = 'This device has nothing to share yet.';
      }
      listHtml = `<div class="syncEmpty">${emptyText}</div>`;
    }
    elementById('syncList').innerHTML = listHtml;
    renderPicks(offers);
  }

  // The Select all box and the button under the list, which follow the ticks without
  // redrawing the list.
  function renderPicks(offers = offered()) {
    const importing = sync.tab === 'import';
    const picked = sync.picked[sync.tab];
    const openOffers = offers.filter((offer) => {
      return !offer.done;
    });
    const ticked = openOffers.filter((offer) => {
      return picked.has(offer.key);
    }).length;
    const box = elementById('syncAll');
    box.disabled = !openOffers.length;
    box.checked = openOffers.length > 0 && ticked === openOffers.length;
    box.indeterminate = ticked > 0 && ticked < openOffers.length;

    const pickedCount = picked.size;
    const goButton = elementById('syncGo');
    goButton.disabled = !pickedCount;
    if (!pickedCount) {
      if (importing) {
        goButton.textContent = 'Tick what to import';
      } else {
        goButton.textContent = 'Tick what to send';
      }
    } else if (importing) {
      if (pickedCount === 1) {
        goButton.textContent = 'Import 1 thing to this device';
      } else {
        goButton.textContent = `Import ${pickedCount} things to this device`;
      }
    } else {
      if (pickedCount === 1) {
        goButton.textContent = 'Send 1 thing to the other device';
      } else {
        goButton.textContent = `Send ${pickedCount} things to the other device`;
      }
    }
  }

  /* ---- the window ---- */

  const modalOpen = () => {
    return !elementById('syncModal').classList.contains('hidden');
  };

  // As the window opens: the last code this device joined with, ready to use again.
  function open() {
    openModal('syncModal');
    if (!sync.role && !elementById('syncCodeInput').value) {
      elementById('syncCodeInput').value = readKey(LAST_KEY);
    }
    render();
  }

  // A link from another device's QR code (#sync/CODE): the code filled in, waiting for a press
  // on Connect rather than connecting outright, since connecting shows this device's boards to
  // whoever made the link.
  function openLink(code) {
    history.replaceState(null, '', location.pathname + location.search);
    open();
    if (sync.role) {
      return;
    }
    elementById('syncCodeInput').value = P2P.normaliseCode(code);
    showStatus('Press Connect to sync with the device showing this code.', 'busy');
    elementById('syncJoinBtn').focus({ preventScroll: true });
  }

  // The app is on screen (signed in or as a guest): a sync link that opened the page can be used.
  function appShown() {
    if (!sync.pendingLink) {
      return;
    }
    const code = sync.pendingLink;
    sync.pendingLink = '';
    openLink(code);
  }

  function readLink() {
    const match = location.hash.match(/^#sync\/([A-Za-z0-9-]{1,20})$/);
    if (match) {
      return match[1];
    } else {
      return '';
    }
  }

  // Hooks up the Sync window: its buttons, the code box, the tabs and tick boxes, ending the
  // session when the window closes, waking up again when the page comes back on screen, and
  // sync links followed while the page is open.
  function init() {
    elementById('syncBtn').addEventListener('click', open);
    elementById('syncHostBtn').addEventListener('click', () => {
      sync.retriedTaken = false;
      startHosting();
    });
    elementById('syncJoinBtn').addEventListener('click', () => {
      return join(elementById('syncCodeInput').value);
    });
    elementById('syncCodeInput').addEventListener('keydown', (event) => {
      if (event.key === 'Enter') {
        join(event.target.value);
      }
    });
    elementById('syncCode').addEventListener('click', copyLink);
    elementById('syncNewCode').addEventListener('click', () => {
      return newHostCode();
    });
    elementById('syncEnd').addEventListener('click', stop);

    elementById('syncTabs').addEventListener('click', (event) => {
      const tab = event.target.closest('[data-sync-tab]');
      if (!tab) {
        return;
      }
      sync.tab = tab.dataset.syncTab;
      renderList();
      elementById('syncList').scrollTop = 0;
    });
    elementById('syncList').addEventListener('change', (event) => {
      const key = event.target.dataset.syncKey;
      if (!key) {
        return;
      }
      const picked = sync.picked[sync.tab];
      if (event.target.checked) {
        picked.add(key);
      } else {
        picked.delete(key);
      }
      renderPicks();
    });
    elementById('syncAll').addEventListener('change', (event) => {
      const picked = sync.picked[sync.tab];
      for (const { key, done } of offered()) {
        if (done) {
          continue;
        }
        if (event.target.checked) {
          picked.add(key);
        } else {
          picked.delete(key);
        }
      }
      allElements('#syncList [data-sync-key]:not(:disabled)').forEach((box) => {
        box.checked = picked.has(box.dataset.syncKey);
      });
      renderPicks();
    });
    elementById('syncGo').addEventListener('click', copyPicked);

    elementById('syncModal').addEventListener('click', (event) => {
      if (event.target === elementById('syncModal')) {
        closeModal('syncModal');
      }
    });
    // A session belongs to the open window, so nothing is left running out of sight. Watched
    // rather than hooked, as the window closes in several ways (its button, the backdrop,
    // Escape, signing out).
    new MutationObserver(() => {
      if (modalOpen()) {
        return;
      }
      stop();
      showStatus('');
      showNote('');
    }).observe(elementById('syncModal'), { attributes: true, attributeFilter: ['class'] });

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible') {
        return;
      }
      if (sync.role) {
        // The browser lets go of the wake lock whenever the page is hidden.
        holdScreenOn();
      } else if (sync.droppedCode && modalOpen()) {
        // Back from the background with a channel that died meanwhile. An unreachable one isn't
        // retried: the network hasn't changed, so the result wouldn't either.
        join(sync.droppedCode);
      }
    });
    // A link followed in a page already open: used now, or kept until the app is on screen.
    addEventListener('hashchange', () => {
      const code = readLink();
      if (!code) {
        return;
      }
      if (elementById('app').classList.contains('hidden')) {
        sync.pendingLink = code;
      } else {
        openLink(code);
      }
    });

    sync.pendingLink = readLink();
    render();
  }

  window.Sync = { init, open, changed, appShown, stop };
})();
