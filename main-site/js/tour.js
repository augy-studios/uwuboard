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
   state.boardsReady once the boards have loaded. */
(function () {
  const WELCOME_KEY = 'uwuboard.tour.welcome';
  const PAGES_KEY = 'uwuboard.tour.pages';
  const PADDING = 8;
  const WELCOME = 'welcome';
  const VIEWS = ['kanban', 'timeline'];

  // Calls the function script.js put on window under `name`, if it is there, with the
  // arguments given, and returns what it answers; undefined when there is no such function.
  function callIfPresent(name, ...argumentList) {
    if (window[name] === null || window[name] === undefined) {
      return undefined;
    }
    return window[name](...argumentList);
  }

  const narrow = () => {
    return window.innerWidth <= 720;
  };
  const hasBoard = () => {
    return Boolean(callIfPresent('getActiveBoard'));
  };

  // Each tour's steps: `selector` a selector (alternatives allowed, the first visible match is
  // used), `text` one line, `when` an optional test for whether the step applies. `page` is
  // what has to be on screen for it; `available` whether it can be replayed just now, and
  // `why` what to do if not.
  const TOURS = {
    welcome: {
      label: 'Welcome',
      steps: [
        { selector: '#empty-new-board-btn', text: 'Start here: make a board. It can be a Kanban board or a Timeline.' },
        { selector: '#board-list', text: 'All your boards are listed here, with New Board below to make another.', when: () => { return !narrow(); } },
        { selector: '#mobile-menu-btn', text: 'Your boards are in here, with New Board to make another.', when: narrow },
        { selector: '#trayButtons, #trayTab', text: 'Theme, Show me around, and the open board’s view, Export, Import and Delete live here. Press and hold one to see what it does; the arrow tucks them away.' },
        { selector: '#syncBtn, #trayTab', text: 'Sync copies boards straight to your other phone or computer, no account needed.' },
      ],
    },
    kanban: {
      label: 'Kanban board',
      page: 'kanban',
      available: hasBoard,
      why: 'Open a board first',
      steps: [
        { selector: '.column .add-card-btn', text: 'Add a card to a column.' },
        { selector: '.columns-container .card', text: 'Drag a card to the next column as the work moves along. Tap it for its details.' },
        { selector: '.column .col-menu-btn', text: 'Rename or delete a column here.' },
        { selector: '.add-col-circle-btn', text: 'Add another column.' },
        { selector: '#board-view-btn, #trayTab', text: 'See this board as a Timeline: the same cards, as bars across dates.' },
      ],
    },
    timeline: {
      label: 'Timeline',
      page: 'timeline',
      available: hasBoard,
      why: 'Open a board first',
      steps: [
        { selector: '.tl-bar, .tl-milestone', text: 'Each task is a bar across its dates. Drag it to move them, or drag an end to change how long it takes.' },
        { selector: '.tl-row-task.undated', text: 'No dates yet: press a day in its row to give it some.' },
        { selector: '.tl-dep', text: 'Arrows show what a task waits for, and turn red when the dates clash. Set them in a task’s details.' },
        { selector: '.tl-zoom', text: 'See weeks in detail, or months and quarters at once. Today brings you back.' },
        { selector: '.tl-phase', text: 'Phases are this board’s columns. Press one to rename it; add tasks and phases under them.' },
        { selector: '#board-view-btn, #trayTab', text: 'Back to Kanban any time: the same cards, as columns.' },
      ],
    },
    newboard: {
      label: 'New board',
      page: 'newboard',
      steps: [
        { selector: '#new-board-name', text: 'Name the board after what it’s for.' },
        { selector: '#new-board-type', text: 'Kanban moves cards across columns; Timeline lays tasks out as bars across dates. You can switch later.' },
        { selector: '#new-board-cols', text: 'The columns it starts with: phases, on a Timeline. Tap one to remove it, or Add for another.' },
        { selector: '#create-board-btn', text: 'Create makes the board and opens it.' },
      ],
    },
    card: {
      label: 'Card details',
      page: 'card',
      available: () => {
        return Boolean(callIfPresent('firstCard'));
      },
      why: 'Add a card first',
      steps: [
        { selector: '#card-modal-desc', text: 'Notes on the card go here.' },
        { selector: '#card-modal .modal-row', text: 'A due date and a priority, both shown on the card.' },
        { selector: '#card-tl-fields', text: 'On a Timeline: when it starts, whether it’s a milestone, and what it waits for.' },
        { selector: '#card-modal-col-btn', text: 'Move the card to another column without dragging it.' },
        { selector: '#card-modal .img-upload-label', text: 'Add images. The one you star shows on the card.' },
        { selector: '#card-modal .checklist-add-row', text: 'Break the card into steps; the card shows how many are done.' },
        { selector: '#save-card-btn', text: 'Save keeps what you’ve changed.' },
      ],
    },
  };

  /* ---- what's on screen ---- */

  // Whether the element with this id is not hidden (a missing element counts as shown).
  const isShown = (id) => {
    const element = document.getElementById(id);
    if (element === null || element === undefined) {
      return true;
    }
    return !element.classList.contains('hidden');
  };

  const pages = {
    // `null` before the app is on screen; `empty` with no board open.
    active() {
      if (!isShown('app')) {
        return null;
      }
      if (isShown('new-board-modal')) {
        return 'newboard';
      }
      if (isShown('card-modal')) {
        return 'card';
      }
      const board = callIfPresent('getActiveBoard');
      if (!board) {
        return 'empty';
      }
      if (callIfPresent('isTimeline', board)) {
        return 'timeline';
      } else {
        return 'kanban';
      }
    },
    // Puts the page `id` on screen: opens or closes the windows, or shows the board as a view.
    open(id) {
      if (id === 'newboard') {
        callIfPresent('closeCardModal');
        callIfPresent('openNewBoardModal');
        return;
      }
      callIfPresent('closeNewBoardModal');
      if (id === 'card') {
        callIfPresent('openFirstCard');
        return;
      }
      callIfPresent('closeCardModal');
      // A view: the open board shown as it, or as its own view again.
      if (VIEWS.includes(id)) {
        callIfPresent('setViewOverride', id);
      }
    },
  };

  // A window open over the page: any but the one that is the page.
  const OWN_WINDOWS = { card: 'card-modal', newboard: 'new-board-modal' };
  function windowOpen(id) {
    return [...document.querySelectorAll('.modal-backdrop:not(.hidden)')].some((element) => {
      return element.id !== OWN_WINDOWS[id];
    });
  }

  // The views wait for the boards to load; the windows are drawn as they open.
  const ready = (id) => {
    if (!(VIEWS.includes(id) || id === 'empty')) {
      return true;
    }
    if (typeof state === 'undefined') {
      return false;
    }
    return Boolean(state.boardsReady);
  };

  /* ---- state ---- */

  let steps = [];
  let stepIndex = 0;
  let root = null; // the layer, or `true` while a tour is getting ready
  let toursToMark = [];  // the tours this one counts as, once it ends
  let startPage = null;

  // The ids of the page tours already seen, as stored.
  function storedPages() {
    let stored = localStorage.getItem(PAGES_KEY);
    if (!stored) {
      stored = '[]';
    }
    return JSON.parse(stored);
  }

  function seen(id) {
    try {
      if (id === WELCOME) {
        return localStorage.getItem(WELCOME_KEY) === 'done';
      }
      return storedPages().includes(id);
    } catch {
      // Broken storage counts every tour as seen, rather than showing one on every visit.
      return true;
    }
  }

  function markSeen(id) {
    try {
      if (id === WELCOME) {
        localStorage.setItem(WELCOME_KEY, 'done');
        return;
      }
      const seenPages = storedPages();
      if (!seenPages.includes(id)) {
        localStorage.setItem(PAGES_KEY, JSON.stringify([...seenPages, id]));
      }
    } catch { /* shown again next time */ }
  }

  // On screen: not hidden, not tucked away (an inert tray, the off-canvas sidebar on a phone),
  // and at least partly inside the viewport.
  function visible(element) {
    if (!element || element.closest('[hidden], .hidden, [inert]')) {
      return false;
    }
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0 || getComputedStyle(element).visibility === 'hidden') {
      return false;
    }
    return rect.right > 0 && rect.bottom > 0 && rect.left < innerWidth && rect.top < innerHeight;
  }
  // The alternatives in the order they're written, not the page's: "the Sync button, or the
  // tray's tab while it's collapsed" must not pick the tab, which comes first in the page.
  function target(step) {
    for (const selector of step.selector.split(',')) {
      const element = [...document.querySelectorAll(selector.trim())].find(visible);
      if (element) {
        return element;
      }
    }
    return null;
  }

  /* ---- drawing ---- */

  // Adds the tour's layer to the page: the lit hole, the chalk arrow, Skip, and the card with
  // its text, dots and Next button, and listens for the keys and for the page moving.
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
    root.addEventListener('keydown', (event) => {
      // Handled here, so the page's own Escape (which closes every window) leaves it be.
      if (event.key === 'Escape') { event.preventDefault(); end(); }
      if (event.key === 'ArrowRight') { event.preventDefault(); next(); }
    });
    addEventListener('resize', place);
    addEventListener('scroll', place, true);
  }

  // Shows step number `index`: scrolls its element into view, sets the text, the dots and the
  // button's label, then places everything once the page has settled.
  function show(index) {
    stepIndex = index;
    const element = steps[index].target;
    // A tall element from its top, so its top edge isn't lost.
    const tall = element.getBoundingClientRect().height > innerHeight * 0.6;
    let block;
    if (tall) {
      block = 'start';
    } else {
      block = 'center';
    }
    element.scrollIntoView({ block, inline: 'nearest', behavior: 'instant' });
    root.querySelector('.tourText').textContent = steps[index].text;
    root.querySelector('.tourDots').innerHTML = steps.map((step, dotIndex) => {
      let onClass;
      if (dotIndex === index) {
        onClass = ' class="on"';
      } else {
        onClass = '';
      }
      return `<span${onClass}></span>`;
    }).join('');
    if (index === steps.length - 1) {
      root.querySelector('.tourNext').textContent = 'Done';
    } else {
      root.querySelector('.tourNext').textContent = 'Next';
    }
    requestAnimationFrame(place);
    root.querySelector('.tourNext').focus({ preventScroll: true });
  }

  // The hole, the card on the side with room, lined up with the element, and the arrow
  // between them, all of it on screen (the spec's §3).
  const MARGIN = 12;
  const EDGE = 20;
  const GAP_MIN = 36;
  const GAP_MAX = 70;
  const CARD_MIN = 220;
  const clamp = (low, value, high) => {
    return Math.max(low, Math.min(value, Math.max(low, high)));
  };

  // Lays out the current step: the hole over its element, the card on whichever side has
  // room (shrinking it to fit beside the element if need be, or on a solid backing at the
  // top or bottom when there's no room anywhere), and the curved arrow from card to element.
  function place() {
    if (!root || root === true) {
      return;
    }
    const step = steps[stepIndex];
    let element;
    if (step !== null && step !== undefined) {
      element = step.target;
    }
    if (!element) {
      return;
    }
    const rect = element.getBoundingClientRect();
    const viewportWidth = innerWidth;
    const viewportHeight = innerHeight;
    const hole = root.querySelector('.tourHole');
    Object.assign(hole.style, {
      left: `${rect.left - PADDING}px`, top: `${rect.top - PADDING}px`,
      width: `${rect.width + PADDING * 2}px`, height: `${rect.height + PADDING * 2}px`,
    });

    // The part of the element inside the viewport.
    const visiblePart = {
      left: Math.max(rect.left, 0), right: Math.min(rect.right, viewportWidth),
      top: Math.max(rect.top, 0), bottom: Math.min(rect.bottom, viewportHeight),
    };
    const card = root.querySelector('.tourCard');
    card.classList.remove('solid');
    card.style.width = '';
    let cardWidth = card.offsetWidth;
    let cardHeight = card.offsetHeight;
    const room = {
      below: viewportHeight - visiblePart.bottom - PADDING - MARGIN, above: visiblePart.top - PADDING - MARGIN,
      right: viewportWidth - visiblePart.right - PADDING - MARGIN, left: visiblePart.left - PADDING - MARGIN,
    };
    // Which side of the element the card goes: above or below if it fits there, otherwise
    // the roomier of left and right, narrowed to fit.
    let side = null;
    if (Math.max(room.below, room.above) >= cardHeight + GAP_MIN) {
      if (room.below >= room.above) {
        side = 'below';
      } else {
        side = 'above';
      }
    } else {
      let widerSide;
      if (room.right >= room.left) {
        widerSide = 'right';
      } else {
        widerSide = 'left';
      }
      const fit = room[widerSide] - GAP_MIN;
      if (fit >= Math.min(cardWidth, CARD_MIN)) {
        if (fit < cardWidth) {
          card.style.width = `${fit}px`;
          cardWidth = card.offsetWidth;
          cardHeight = card.offsetHeight;
        }
        if (cardHeight <= viewportHeight - MARGIN * 2) {
          side = widerSide;
        } else {
          card.style.width = '';
        }
      }
    }

    const line = root.querySelector('.tourLine');
    const head = root.querySelector('.tourHead');
    let left;
    let top;
    if (!side) {
      // No room for an arrow: the card on a backing, at the end away from most of the element.
      card.classList.add('solid');
      cardWidth = card.offsetWidth;
      cardHeight = card.offsetHeight;
      left = (viewportWidth - cardWidth) / 2;
      if ((visiblePart.top + visiblePart.bottom) / 2 > viewportHeight / 2) {
        top = MARGIN;
      } else {
        top = viewportHeight - cardHeight - MARGIN;
      }
      Object.assign(card.style, { left: `${left}px`, top: `${top}px` });
      line.setAttribute('d', '');
      head.setAttribute('d', '');
      return;
    }

    // Where the card goes, and the arrow's two ends: its start by the card and its tip by the
    // element.
    const midX = (visiblePart.left + visiblePart.right) / 2;
    const midY = (visiblePart.top + visiblePart.bottom) / 2;
    let startX;
    let startY;
    let tipX;
    let tipY;
    if (side === 'below' || side === 'above') {
      const gap = clamp(GAP_MIN, room[side] - cardHeight, GAP_MAX);
      left = clamp(MARGIN, midX - cardWidth / 2, viewportWidth - cardWidth - MARGIN);
      if (side === 'below') {
        top = visiblePart.bottom + PADDING + gap;
      } else {
        top = visiblePart.top - PADDING - gap - cardHeight;
      }
      top = clamp(MARGIN, top, viewportHeight - cardHeight - MARGIN);
      tipX = clamp(visiblePart.left + 12, midX, visiblePart.right - 12);
      if (side === 'below') {
        tipY = visiblePart.bottom + PADDING + 4;
      } else {
        tipY = visiblePart.top - PADDING - 4;
      }
      startX = clamp(left + 24, tipX, left + cardWidth - 24);
      if (side === 'below') {
        startY = top - 6;
      } else {
        startY = top + cardHeight + 6;
      }
    } else {
      const gap = clamp(GAP_MIN, room[side] - cardWidth, GAP_MAX);
      if (side === 'right') {
        left = visiblePart.right + PADDING + gap;
      } else {
        left = visiblePart.left - PADDING - gap - cardWidth;
      }
      left = clamp(MARGIN, left, viewportWidth - cardWidth - MARGIN);
      top = clamp(MARGIN, midY - cardHeight / 2, viewportHeight - cardHeight - MARGIN);
      if (side === 'right') {
        tipX = visiblePart.right + PADDING + 4;
      } else {
        tipX = visiblePart.left - PADDING - 4;
      }
      tipY = clamp(visiblePart.top + 12, midY, visiblePart.bottom - 12);
      if (side === 'right') {
        startX = left - 6;
      } else {
        startX = left + cardWidth + 6;
      }
      startY = clamp(top + 16, tipY, top + cardHeight - 16);
    }
    Object.assign(card.style, { left: `${left}px`, top: `${top}px` });

    // Every point of the arrow EDGE in from the viewport, so none of it is cut off.
    const insideX = (x) => {
      return clamp(EDGE, x, viewportWidth - EDGE);
    };
    const insideY = (y) => {
      return clamp(EDGE, y, viewportHeight - EDGE);
    };
    tipX = insideX(tipX);
    tipY = insideY(tipY);
    startX = insideX(startX);
    startY = insideY(startY);
    const deltaX = tipX - startX;
    const deltaY = tipY - startY;
    // The curve's control point, pushed off to one side of the straight line so it bows.
    const controlX = insideX((startX + tipX) / 2 - deltaY * 0.2);
    const controlY = insideY((startY + tipY) / 2 + deltaX * 0.2);

    root.querySelector('.tourArrow').setAttribute('viewBox', `0 0 ${viewportWidth} ${viewportHeight}`);
    line.setAttribute('d', `M${startX},${startY} Q${controlX},${controlY} ${tipX},${tipY}`);
    line.style.setProperty('--len', Math.ceil(line.getTotalLength()) + 10);
    // The arrowhead: two short strokes back from the tip, either side of the curve's direction.
    const angle = Math.atan2(tipY - controlY, tipX - controlX);
    const firstWingAngle = angle + Math.PI * 0.8;
    const secondWingAngle = angle - Math.PI * 0.8;
    const headLength = 14;
    head.setAttribute('d',
      `M${tipX + Math.cos(firstWingAngle) * headLength},${tipY + Math.sin(firstWingAngle) * headLength} L${tipX},${tipY} L${tipX + Math.cos(secondWingAngle) * headLength},${tipY + Math.sin(secondWingAngle) * headLength}`);
  }

  /* ---- running ---- */

  function next() {
    if (stepIndex < steps.length - 1) {
      show(stepIndex + 1);
    } else {
      end();
    }
  }

  // Ends the tour: marks its tours as seen, removes the layer, and goes back to the page it
  // began on (or looks for the next page's first tour).
  function end() {
    for (const id of toursToMark) {
      markSeen(id);
    }
    toursToMark = [];
    removeEventListener('resize', place);
    removeEventListener('scroll', place, true);
    if (root && root !== true) {
      root.remove();
    }
    root = null;
    document.body.classList.remove('touring');
    const returnTo = startPage;
    startPage = null;
    // Back where it began (its own view again, if it was shown as the other), which may be a
    // page whose own tour is still to see.
    if (returnTo && pages.active() !== returnTo) {
      pages.open(returnTo);
    } else {
      setTimeout(forPage, 600);
    }
  }

  // `id`'s tour, on its page. With `withWelcome`, the welcome's steps follow its own, as the
  // first tour anyone sees; `id` may then be `empty`, which has no steps of its own.
  function start(id, { withWelcome = false } = {}) {
    const tour = TOURS[id];
    if (root || (!tour && !withWelcome)) {
      return;
    }
    const from = pages.active();
    if (!from) {
      return;
    }
    let goTo;
    if (tour !== null && tour !== undefined) {
      goTo = tour.page;
    }
    if (goTo && from !== goTo) {
      pages.open(goTo);
    }
    root = true; // taken, while the page draws
    // Straight away when already on the page, otherwise after a moment for it to draw.
    let delay;
    if (!goTo || from === goTo) {
      delay = 0;
    } else {
      delay = 400;
    }
    setTimeout(() => {
      root = null;
      let ownSteps = [];
      if (tour !== null && tour !== undefined && tour.steps) {
        ownSteps = tour.steps;
      }
      let welcomeSteps;
      if (withWelcome && id !== WELCOME) {
        welcomeSteps = TOURS.welcome.steps;
      } else {
        welcomeSteps = [];
      }
      const allSteps = [...ownSteps, ...welcomeSteps];
      steps = allSteps
        .filter((step) => {
          if (!step.when) {
            return true;
          }
          return step.when();
        })
        .map((step) => {
          return { ...step, target: target(step) };
        })
        .filter((step) => {
          return step.target;
        });
      // Two steps can land on the same thing, such as the collapsed tray's tab.
      steps = steps.filter((step, index) => {
        return index === 0 || step.target !== steps[index - 1].target;
      });
      const done = [];
      if (withWelcome) {
        done.push(WELCOME);
      }
      if (tour) {
        done.push(id);
      }
      if (!steps.length) {
        done.forEach(markSeen);
        if (pages.active() !== from) {
          pages.open(from);
        }
        return;
      }
      toursToMark = done;
      startPage = from;
      document.body.classList.add('touring');
      build();
      show(0);
    }, delay);
  }

  // The tour for what's on screen, the first time, once it's drawn: the welcome joined to the
  // view's own steps if the welcome's still to see, or that page's own tour.
  let waiting = null;
  function forPage() {
    if (root) {
      return;
    }
    const id = pages.active();
    if (!id) {
      return;
    }
    const welcome = !seen(WELCOME) && (VIEWS.includes(id) || id === 'empty');
    if (!welcome && (!TOURS[id] || seen(id))) {
      return;
    }
    clearInterval(waiting);
    let tries = 0;
    // Checked every half second: given up if the page changes, started once the page is
    // ready (or after eight seconds regardless), unless a window is open over it.
    waiting = setInterval(() => {
      tries = tries + 1;
      if (pages.active() !== id || root) {
        clearInterval(waiting);
        return;
      }
      let keepWaiting;
      if (ready(id)) {
        keepWaiting = tries < 2;
      } else {
        keepWaiting = tries <= 16;
      }
      if (keepWaiting) {
        return;
      }
      clearInterval(waiting);
      if (!windowOpen(id)) {
        start(id, { withWelcome: welcome });
      }
    }, 500);
  }

  // Once the app is on screen: the first tour, unless a link opened something.
  let started = false;
  function init() {
    if (started) {
      return;
    }
    started = true;
    addEventListener('pagechange', forPage);
    if (location.hash.length > 1 || location.search) {
      return;
    }
    forPage();
  }

  // "Show me around": a button per tour, each only while there's something for it to show.
  const ORDER = ['welcome', 'kanban', 'timeline', 'newboard', 'card'];
  function pickers() {
    return ORDER.map((id) => {
      const tour = TOURS[id];
      let disabledAttributes = '';
      if (tour.available && !tour.available()) {
        disabledAttributes = ` disabled title="${tour.why}"`;
      }
      return `<button class="btn-ghost" type="button" data-tour="${id}"${disabledAttributes}>${tour.label}</button>`;
    }).join('');
  }

  window.Tour = {
    init,
    start,
    end,
    pickers,
    active: () => {
      return Boolean(root);
    },
  };
})();
