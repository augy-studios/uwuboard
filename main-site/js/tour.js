'use strict';

/* First-visit tours (docs/page-tour-spec.md). The page dims, one thing on it is lit, and a
   chalk arrow runs to it from a line saying what it does.

   A tour for each thing that can be on screen, shown the first time it is:
     kanban    a board shown as columns
     timeline  a board shown as a Timeline (js/timeline.js)
     newboard  the New Board window: how to make a board
     card      the card details window
   and the welcome, the first time the app opens: where the boards are, the tray and Sync,
   joined onto the steps of the view on screen as one tour, after which that view counts as
   seen too. "Show me around" in the tray replays any of them. A view's tour shows the open
   board as that view while it runs and puts it back after, without changing the board.

   What it needs from script.js: getActiveBoard(), isTimeline(), setViewOverride(),
   firstCard(), openFirstCard(), closeCardModal(), openNewBoardModal() and
   closeNewBoardModal(); a `pagechange` event on window whenever what's on screen changes; and
   S.boardsReady once the boards have loaded. */
(function () {
  const WELCOME_KEY = 'uwuboard.tour.welcome';
  const PAGES_KEY = 'uwuboard.tour.pages';
  const PAD = 8;
  const WELCOME = 'welcome';
  const VIEWS = ['kanban', 'timeline'];

  const narrow = () => window.innerWidth <= 720;
  const hasBoard = () => !!window.getActiveBoard?.();

  // Each tour's steps: `el` a selector (alternatives allowed, the first visible match is
  // used), `text` one line, `when` an optional test for whether the step applies. `page` is
  // what has to be on screen for it; `available` whether it can be replayed just now, and
  // `why` what to do if not.
  const TOURS = {
    welcome: {
      label: 'Welcome',
      steps: [
        { el: '#empty-new-board-btn', text: 'Start here: make a board. It can be a Kanban board or a Timeline.' },
        { el: '#board-list', text: 'All your boards are listed here, with New Board below to make another.', when: () => !narrow() },
        { el: '#mobile-menu-btn', text: 'Your boards are in here, with New Board to make another.', when: narrow },
        { el: '#trayButtons, #trayTab', text: 'Theme, Show me around, and the open board’s view, Export, Import and Delete live here. Press and hold one to see what it does; the arrow tucks them away.' },
        { el: '#syncBtn, #trayTab', text: 'Sync copies boards straight to your other phone or computer, no account needed.' },
      ],
    },
    kanban: {
      label: 'Kanban board',
      page: 'kanban',
      available: hasBoard,
      why: 'Open a board first',
      steps: [
        { el: '.column .add-card-btn', text: 'Add a card to a column.' },
        { el: '.columns-container .card', text: 'Drag a card to the next column as the work moves along. Tap it for its details.' },
        { el: '.column .col-menu-btn', text: 'Rename or delete a column here.' },
        { el: '.add-col-circle-btn', text: 'Add another column.' },
        { el: '#board-view-btn, #trayTab', text: 'See this board as a Timeline: the same cards, as bars across dates.' },
      ],
    },
    timeline: {
      label: 'Timeline',
      page: 'timeline',
      available: hasBoard,
      why: 'Open a board first',
      steps: [
        { el: '.tl-bar, .tl-milestone', text: 'Each task is a bar across its dates. Drag it to move them, or drag an end to change how long it takes.' },
        { el: '.tl-row-task.undated', text: 'No dates yet: press a day in its row to give it some.' },
        { el: '.tl-dep', text: 'Arrows show what a task waits for, and turn red when the dates clash. Set them in a task’s details.' },
        { el: '.tl-zoom', text: 'See weeks in detail, or months and quarters at once. Today brings you back.' },
        { el: '.tl-phase', text: 'Phases are this board’s columns. Press one to rename it; add tasks and phases under them.' },
        { el: '#board-view-btn, #trayTab', text: 'Back to Kanban any time: the same cards, as columns.' },
      ],
    },
    newboard: {
      label: 'New board',
      page: 'newboard',
      steps: [
        { el: '#new-board-name', text: 'Name the board after what it’s for.' },
        { el: '#new-board-type', text: 'Kanban moves cards across columns; Timeline lays tasks out as bars across dates. You can switch later.' },
        { el: '#new-board-cols', text: 'The columns it starts with: phases, on a Timeline. Tap one to remove it, or Add for another.' },
        { el: '#create-board-btn', text: 'Create makes the board and opens it.' },
      ],
    },
    card: {
      label: 'Card details',
      page: 'card',
      available: () => !!window.firstCard?.(),
      why: 'Add a card first',
      steps: [
        { el: '#card-modal-desc', text: 'Notes on the card go here.' },
        { el: '#card-modal .modal-row', text: 'A due date and a priority, both shown on the card.' },
        { el: '#card-tl-fields', text: 'On a Timeline: when it starts, whether it’s a milestone, and what it waits for.' },
        { el: '#card-modal-col-btn', text: 'Move the card to another column without dragging it.' },
        { el: '#card-modal .img-upload-label', text: 'Add images. The one you star shows on the card.' },
        { el: '#card-modal .checklist-add-row', text: 'Break the card into steps; the card shows how many are done.' },
        { el: '#save-card-btn', text: 'Save keeps what you’ve changed.' },
      ],
    },
  };

  /* ---- what's on screen ---- */

  const isShown = (id) => !document.getElementById(id)?.classList.contains('hidden');

  const pages = {
    // `null` before the app is on screen; `empty` with no board open.
    active() {
      if (!isShown('app')) return null;
      if (isShown('new-board-modal')) return 'newboard';
      if (isShown('card-modal')) return 'card';
      const board = window.getActiveBoard?.();
      if (!board) return 'empty';
      return window.isTimeline?.(board) ? 'timeline' : 'kanban';
    },
    open(id) {
      if (id === 'newboard') {
        window.closeCardModal?.();
        window.openNewBoardModal?.();
        return;
      }
      window.closeNewBoardModal?.();
      if (id === 'card') return window.openFirstCard?.();
      window.closeCardModal?.();
      // A view: the open board shown as it, or as its own view again.
      if (VIEWS.includes(id)) window.setViewOverride?.(id);
    },
  };

  // A window open over the page: any but the one that is the page.
  const OWN = { card: 'card-modal', newboard: 'new-board-modal' };
  function windowOpen(id) {
    return [...document.querySelectorAll('.modal-backdrop:not(.hidden)')].some((el) => el.id !== OWN[id]);
  }

  // The views wait for the boards to load; the windows are drawn as they open.
  const ready = (id) => !(VIEWS.includes(id) || id === 'empty') || !!(typeof S !== 'undefined' && S.boardsReady);

  /* ---- state ---- */

  let steps = [];
  let at = 0;
  let root = null; // the layer, or `true` while a tour is getting ready
  let marks = [];  // the tours this one counts as, once it ends
  let began = null;

  function seen(id) {
    try {
      if (id === WELCOME) return localStorage.getItem(WELCOME_KEY) === 'done';
      return JSON.parse(localStorage.getItem(PAGES_KEY) || '[]').includes(id);
    } catch {
      // Broken storage counts every tour as seen, rather than showing one on every visit.
      return true;
    }
  }

  function markSeen(id) {
    try {
      if (id === WELCOME) return localStorage.setItem(WELCOME_KEY, 'done');
      const list = JSON.parse(localStorage.getItem(PAGES_KEY) || '[]');
      if (!list.includes(id)) localStorage.setItem(PAGES_KEY, JSON.stringify([...list, id]));
    } catch { /* shown again next time */ }
  }

  // On screen: not hidden, not tucked away (an inert tray, the off-canvas sidebar on a phone),
  // and at least partly inside the viewport.
  function visible(el) {
    if (!el || el.closest('[hidden], .hidden, [inert]')) return false;
    const r = el.getBoundingClientRect();
    if (r.width <= 0 || r.height <= 0 || getComputedStyle(el).visibility === 'hidden') return false;
    return r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight;
  }
  // The alternatives in the order they're written, not the page's: "the Sync button, or the
  // tray's tab while it's collapsed" must not pick the tab, which comes first in the page.
  function target(s) {
    for (const sel of s.el.split(',')) {
      const el = [...document.querySelectorAll(sel.trim())].find(visible);
      if (el) return el;
    }
    return null;
  }

  /* ---- drawing ---- */

  function build() {
    root = document.createElement('div');
    root.className = 'tour';
    root.setAttribute('role', 'dialog');
    root.setAttribute('aria-modal', 'true');
    root.setAttribute('aria-labelledby', 'tourText');
    root.innerHTML =
      '<div class="tourHole"></div>' +
      '<svg class="tourArrow" aria-hidden="true"><defs><filter id="tourChalk"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="2.5"/></filter></defs>' +
      '<path class="tourLine" filter="url(#tourChalk)"/><path class="tourHead" filter="url(#tourChalk)"/></svg>' +
      '<button class="tourSkip" type="button">Skip</button>' +
      '<div class="tourCard"><p id="tourText" class="tourText" aria-live="polite"></p>' +
      '<div class="tourFoot"><span class="tourDots" aria-hidden="true"></span><button class="tourNext" type="button">Next</button></div></div>';
    document.body.appendChild(root);
    root.querySelector('.tourSkip').addEventListener('click', end);
    root.querySelector('.tourNext').addEventListener('click', next);
    root.addEventListener('keydown', (e) => {
      // Handled here, so the page's own Escape (which closes every window) leaves it be.
      if (e.key === 'Escape') { e.preventDefault(); end(); }
      if (e.key === 'ArrowRight') { e.preventDefault(); next(); }
    });
    addEventListener('resize', place);
    addEventListener('scroll', place, true);
  }

  function show(i) {
    at = i;
    const el = steps[i].target;
    // A tall element from its top, so its top edge isn't lost.
    const tall = el.getBoundingClientRect().height > innerHeight * 0.6;
    el.scrollIntoView({ block: tall ? 'start' : 'center', inline: 'nearest', behavior: 'instant' });
    root.querySelector('.tourText').textContent = steps[i].text;
    root.querySelector('.tourDots').innerHTML = steps.map((_, n) => `<span${n === i ? ' class="on"' : ''}></span>`).join('');
    root.querySelector('.tourNext').textContent = i === steps.length - 1 ? 'Done' : 'Next';
    requestAnimationFrame(place);
    root.querySelector('.tourNext').focus({ preventScroll: true });
  }

  // The hole, the card on the side with room, lined up with the element, and the arrow
  // between them, all of it on screen (the spec's §3).
  const M = 12;
  const EDGE = 20;
  const GAP_MIN = 36;
  const GAP_MAX = 70;
  const CARD_MIN = 220;
  const clamp = (lo, v, hi) => Math.max(lo, Math.min(v, Math.max(lo, hi)));

  function place() {
    if (!root || root === true) return;
    const el = steps[at]?.target;
    if (!el) return;
    const r = el.getBoundingClientRect();
    const vw = innerWidth, vh = innerHeight;
    const hole = root.querySelector('.tourHole');
    Object.assign(hole.style, {
      left: `${r.left - PAD}px`, top: `${r.top - PAD}px`,
      width: `${r.width + PAD * 2}px`, height: `${r.height + PAD * 2}px`,
    });

    const v = {
      left: Math.max(r.left, 0), right: Math.min(r.right, vw),
      top: Math.max(r.top, 0), bottom: Math.min(r.bottom, vh),
    };
    const card = root.querySelector('.tourCard');
    card.classList.remove('solid');
    card.style.width = '';
    let cw = card.offsetWidth, ch = card.offsetHeight;
    const room = {
      below: vh - v.bottom - PAD - M, above: v.top - PAD - M,
      right: vw - v.right - PAD - M, left: v.left - PAD - M,
    };
    let side = null;
    if (Math.max(room.below, room.above) >= ch + GAP_MIN) side = room.below >= room.above ? 'below' : 'above';
    else {
      const s = room.right >= room.left ? 'right' : 'left';
      const fit = room[s] - GAP_MIN;
      if (fit >= Math.min(cw, CARD_MIN)) {
        if (fit < cw) {
          card.style.width = `${fit}px`;
          cw = card.offsetWidth;
          ch = card.offsetHeight;
        }
        if (ch <= vh - M * 2) side = s;
        else card.style.width = '';
      }
    }

    const line = root.querySelector('.tourLine');
    const head = root.querySelector('.tourHead');
    let left, top;
    if (!side) {
      // No room for an arrow: the card on a backing, at the end away from most of the element.
      card.classList.add('solid');
      cw = card.offsetWidth;
      ch = card.offsetHeight;
      left = (vw - cw) / 2;
      top = (v.top + v.bottom) / 2 > vh / 2 ? M : vh - ch - M;
      Object.assign(card.style, { left: `${left}px`, top: `${top}px` });
      line.setAttribute('d', '');
      head.setAttribute('d', '');
      return;
    }

    const midX = (v.left + v.right) / 2, midY = (v.top + v.bottom) / 2;
    let sx, sy, tx, ty;
    if (side === 'below' || side === 'above') {
      const gap = clamp(GAP_MIN, room[side] - ch, GAP_MAX);
      left = clamp(M, midX - cw / 2, vw - cw - M);
      top = side === 'below' ? v.bottom + PAD + gap : v.top - PAD - gap - ch;
      top = clamp(M, top, vh - ch - M);
      tx = clamp(v.left + 12, midX, v.right - 12);
      ty = side === 'below' ? v.bottom + PAD + 4 : v.top - PAD - 4;
      sx = clamp(left + 24, tx, left + cw - 24);
      sy = side === 'below' ? top - 6 : top + ch + 6;
    } else {
      const gap = clamp(GAP_MIN, room[side] - cw, GAP_MAX);
      left = side === 'right' ? v.right + PAD + gap : v.left - PAD - gap - cw;
      left = clamp(M, left, vw - cw - M);
      top = clamp(M, midY - ch / 2, vh - ch - M);
      tx = side === 'right' ? v.right + PAD + 4 : v.left - PAD - 4;
      ty = clamp(v.top + 12, midY, v.bottom - 12);
      sx = side === 'right' ? left - 6 : left + cw + 6;
      sy = clamp(top + 16, ty, top + ch - 16);
    }
    Object.assign(card.style, { left: `${left}px`, top: `${top}px` });

    // Every point of the arrow EDGE in from the viewport, so none of it is cut off.
    const inX = (x) => clamp(EDGE, x, vw - EDGE);
    const inY = (y) => clamp(EDGE, y, vh - EDGE);
    tx = inX(tx); ty = inY(ty); sx = inX(sx); sy = inY(sy);
    const dx = tx - sx, dy = ty - sy;
    const mx = inX((sx + tx) / 2 - dy * 0.2);
    const my = inY((sy + ty) / 2 + dx * 0.2);

    root.querySelector('.tourArrow').setAttribute('viewBox', `0 0 ${vw} ${vh}`);
    line.setAttribute('d', `M${sx},${sy} Q${mx},${my} ${tx},${ty}`);
    line.style.setProperty('--len', Math.ceil(line.getTotalLength()) + 10);
    const ang = Math.atan2(ty - my, tx - mx);
    const a1 = ang + Math.PI * 0.8, a2 = ang - Math.PI * 0.8, len = 14;
    head.setAttribute('d',
      `M${tx + Math.cos(a1) * len},${ty + Math.sin(a1) * len} L${tx},${ty} L${tx + Math.cos(a2) * len},${ty + Math.sin(a2) * len}`);
  }

  /* ---- running ---- */

  function next() {
    if (at < steps.length - 1) show(at + 1);
    else end();
  }

  function end() {
    for (const id of marks) markSeen(id);
    marks = [];
    removeEventListener('resize', place);
    removeEventListener('scroll', place, true);
    if (root && root !== true) root.remove();
    root = null;
    document.body.classList.remove('touring');
    const back = began;
    began = null;
    // Back where it began (its own view again, if it was shown as the other), which may be a
    // page whose own tour is still to see.
    if (back && pages.active() !== back) pages.open(back);
    else setTimeout(forPage, 600);
  }

  // `id`'s tour, on its page. With `withWelcome`, the welcome's steps follow its own, as the
  // first tour anyone sees; `id` may then be `empty`, which has no steps of its own.
  function start(id, { withWelcome = false } = {}) {
    const tour = TOURS[id];
    if (root || (!tour && !withWelcome)) return;
    const from = pages.active();
    if (!from) return;
    const goTo = tour?.page;
    if (goTo && from !== goTo) pages.open(goTo);
    root = true; // taken, while the page draws
    setTimeout(() => {
      root = null;
      const list = [...(tour?.steps || []), ...(withWelcome && id !== WELCOME ? TOURS.welcome.steps : [])];
      steps = list
        .filter((s) => !s.when || s.when())
        .map((s) => ({ ...s, target: target(s) }))
        .filter((s) => s.target);
      // Two steps can land on the same thing, such as the collapsed tray's tab.
      steps = steps.filter((s, i) => i === 0 || s.target !== steps[i - 1].target);
      const done = [...(withWelcome ? [WELCOME] : []), ...(tour ? [id] : [])];
      if (!steps.length) {
        done.forEach(markSeen);
        if (pages.active() !== from) pages.open(from);
        return;
      }
      marks = done;
      began = from;
      document.body.classList.add('touring');
      build();
      show(0);
    }, !goTo || from === goTo ? 0 : 400);
  }

  // The tour for what's on screen, the first time, once it's drawn: the welcome joined to the
  // view's own steps if the welcome's still to see, or that page's own tour.
  let waiting = null;
  function forPage() {
    if (root) return;
    const id = pages.active();
    if (!id) return;
    const welcome = !seen(WELCOME) && (VIEWS.includes(id) || id === 'empty');
    if (!welcome && (!TOURS[id] || seen(id))) return;
    clearInterval(waiting);
    let tries = 0;
    waiting = setInterval(() => {
      tries++;
      if (pages.active() !== id || root) return clearInterval(waiting);
      if (ready(id) ? tries < 2 : tries <= 16) return;
      clearInterval(waiting);
      if (!windowOpen(id)) start(id, { withWelcome: welcome });
    }, 500);
  }

  // Once the app is on screen: the first tour, unless a link opened something.
  let started = false;
  function init() {
    if (started) return;
    started = true;
    addEventListener('pagechange', forPage);
    if (location.hash.length > 1 || location.search) return;
    forPage();
  }

  // "Show me around": a button per tour, each only while there's something for it to show.
  const ORDER = ['welcome', 'kanban', 'timeline', 'newboard', 'card'];
  function pickers() {
    return ORDER.map((id) => {
      const t = TOURS[id];
      const off = t.available && !t.available();
      return `<button class="btn-ghost" type="button" data-tour="${id}"${off ? ` disabled title="${t.why}"` : ''}>${t.label}</button>`;
    }).join('');
  }

  window.Tour = { init, start, end, pickers, active: () => !!root };
})();
