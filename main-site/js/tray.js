'use strict';

/* The edge tray (docs/edge-tray-spec.md): the app's global actions and the open board's
   actions in a column at the top right, with a tab that slides it off the edge. Open unless
   this browser last left it collapsed. Shown only while the app is (script.js calls
   Tray.show), not over the sign-in screen. */
(function () {
  const TRAY_KEY = 'uwuboard.trayOpen';

  const headsUpDisplay = document.getElementById('hudRight');
  const tray = document.getElementById('tray');
  const tab = document.getElementById('trayTab');
  const buttons = document.getElementById('trayButtons');

  // Slides the tray open or shut, keeps the tab's label in step, and (unless told not to)
  // remembers the choice in this browser.
  function setTray(open, { save = true } = {}) {
    tray.classList.toggle('collapsed', !open);
    tab.setAttribute('aria-expanded', String(open));
    let tabLabel;
    if (open) {
      tabLabel = 'Hide menu';
    } else {
      tabLabel = 'Show menu';
    }
    tab.setAttribute('aria-label', tabLabel);
    if (open) {
      tab.title = 'Hide menu';
    } else {
      tab.title = 'Show menu';
    }
    // Off-screen buttons must not take focus or clicks.
    buttons.inert = !open;
    document.body.classList.toggle('tray-open', open && !headsUpDisplay.hidden);
    if (!save) {
      return;
    }
    try {
      let storedValue;
      if (open) {
        storedValue = '1';
      } else {
        storedValue = '0';
      }
      localStorage.setItem(TRAY_KEY, storedValue);
    } catch {
      // Remembered for this page view only.
    }
  }

  const isOpen = () => {
    return !tray.classList.contains('collapsed');
  };

  function show(visible) {
    headsUpDisplay.hidden = !visible;
    // The page keeps a strip clear for the tray only while there's a tray to clear.
    document.body.classList.toggle('tray-open', visible && isOpen());
  }

  function init() {
    let open = true;
    try {
      open = localStorage.getItem(TRAY_KEY) !== '0';
    } catch {
      // Open, the default.
    }
    setTray(open, { save: false });
    // The head script's first-paint state has done its job; from here on toggles animate.
    requestAnimationFrame(() => {
      return document.documentElement.classList.remove('tray-start-collapsed');
    });
    tab.addEventListener('click', () => {
      return setTray(!isOpen());
    });
  }

  init();

  /* ---- Press and hold: what a button does ----
     The buttons are icons only, and a touch screen has no hover to show their titles. Holding
     one for a moment shows its label beside it, and letting go then does nothing, so a hold
     is always safe. A quick tap works as ever. The label is the button's own aria-label, so a
     screen reader already hears the same words; the bubble is hidden from it. */
  const HOLD_MILLISECONDS = 450;
  const MOVE_PIXELS = 10;
  let tip = null;
  let holdTimer = null;
  let hideTimer = null;
  let held = false;
  let start = null;

  // Shows the button's label in a bubble beside it, creating the bubble the first time.
  function showTip(button) {
    if (!tip) {
      tip = document.createElement('div');
      tip.className = 'tray-tip';
      tip.setAttribute('aria-hidden', 'true');
      document.body.appendChild(tip);
    }
    clearTimeout(hideTimer);
    let label = button.getAttribute('aria-label');
    if (!label) {
      label = button.title;
    }
    tip.textContent = label;
    // Beside the button, on the side away from the screen's edge.
    const buttonBox = button.getBoundingClientRect();
    tip.style.top = `${buttonBox.top + buttonBox.height / 2}px`;
    tip.style.right = `${window.innerWidth - buttonBox.left + 10}px`;
    tip.classList.add('show');
  }

  function hideTip(delay = 0) {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      if (tip !== null && tip !== undefined) {
        tip.classList.remove('show');
      }
    }, delay);
  }

  tray.addEventListener('pointerdown', (event) => {
    const button = event.target.closest('button');
    if (!button || button.closest('[inert]') || event.button > 0) {
      return;
    }
    held = false;
    start = { x: event.clientX, y: event.clientY };
    clearTimeout(holdTimer);
    hideTip();
    holdTimer = setTimeout(() => {
      held = true;
      showTip(button);
      if (navigator.vibrate !== null && navigator.vibrate !== undefined) {
        navigator.vibrate(10);
      }
    }, HOLD_MILLISECONDS);
  });

  // A finger that slides off is scrolling or changing its mind, not holding.
  tray.addEventListener('pointermove', (event) => {
    if (!start || held) {
      return;
    }
    if (Math.hypot(event.clientX - start.x, event.clientY - start.y) > MOVE_PIXELS) {
      clearTimeout(holdTimer);
    }
  });

  const release = () => {
    clearTimeout(holdTimer);
    start = null;
    if (held) {
      hideTip(1500);
    }
  };
  tray.addEventListener('pointerup', release);
  tray.addEventListener('pointercancel', release);
  tray.addEventListener('pointerleave', release);

  // The click a hold ends with is swallowed before it reaches the button.
  tray.addEventListener('click', (event) => {
    if (!held) {
      return;
    }
    held = false;
    event.preventDefault();
    event.stopPropagation();
  }, true);

  // No long-press menu or text selection on the buttons.
  tray.addEventListener('contextmenu', (event) => {
    if (event.target.closest('button')) {
      event.preventDefault();
    }
  });

  window.Tray = {
    show,
    setOpen: (open) => {
      return setTray(open);
    },
    isOpen,
  };
})();
