'use strict';

/* The edge tray (docs/edge-tray-spec.md): the app's global actions and the open board's
   actions in a column at the top right, with a tab that slides it off the edge. Open unless
   this browser last left it collapsed. Shown only while the app is (script.js calls
   Tray.show), not over the sign-in screen. */
(function () {
  const TRAY_KEY = 'uwuboard.trayOpen';

  const hud = document.getElementById('hudRight');
  const tray = document.getElementById('tray');
  const tab = document.getElementById('trayTab');
  const buttons = document.getElementById('trayButtons');

  function setTray(open, { save = true } = {}) {
    tray.classList.toggle('collapsed', !open);
    tab.setAttribute('aria-expanded', String(open));
    tab.setAttribute('aria-label', open ? 'Hide menu' : 'Show menu');
    tab.title = open ? 'Hide menu' : 'Show menu';
    // Off-screen buttons must not take focus or clicks.
    buttons.inert = !open;
    document.body.classList.toggle('tray-open', open && !hud.hidden);
    if (!save) return;
    try {
      localStorage.setItem(TRAY_KEY, open ? '1' : '0');
    } catch {
      // Remembered for this page view only.
    }
  }

  const isOpen = () => !tray.classList.contains('collapsed');

  function show(on) {
    hud.hidden = !on;
    // The page keeps a strip clear for the tray only while there's a tray to clear.
    document.body.classList.toggle('tray-open', on && isOpen());
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
    requestAnimationFrame(() => document.documentElement.classList.remove('tray-start-collapsed'));
    tab.addEventListener('click', () => setTray(!isOpen()));
  }

  init();

  /* ---- Press and hold: what a button does ----
     The buttons are icons only, and a touch screen has no hover to show their titles. Holding
     one for a moment shows its label beside it, and letting go then does nothing, so a hold
     is always safe. A quick tap works as ever. The label is the button's own aria-label, so a
     screen reader already hears the same words; the bubble is hidden from it. */
  const HOLD_MS = 450;
  const MOVE_PX = 10;
  let tip = null;
  let holdTimer = null;
  let hideTimer = null;
  let held = false;
  let start = null;

  function showTip(btn) {
    if (!tip) {
      tip = document.createElement('div');
      tip.className = 'tray-tip';
      tip.setAttribute('aria-hidden', 'true');
      document.body.appendChild(tip);
    }
    clearTimeout(hideTimer);
    tip.textContent = btn.getAttribute('aria-label') || btn.title;
    // Beside the button, on the side away from the screen's edge.
    const r = btn.getBoundingClientRect();
    tip.style.top = `${r.top + r.height / 2}px`;
    tip.style.right = `${window.innerWidth - r.left + 10}px`;
    tip.classList.add('show');
  }

  function hideTip(delay = 0) {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => tip?.classList.remove('show'), delay);
  }

  tray.addEventListener('pointerdown', (e) => {
    const btn = e.target.closest('button');
    if (!btn || btn.closest('[inert]') || e.button > 0) return;
    held = false;
    start = { x: e.clientX, y: e.clientY };
    clearTimeout(holdTimer);
    hideTip();
    holdTimer = setTimeout(() => {
      held = true;
      showTip(btn);
      navigator.vibrate?.(10);
    }, HOLD_MS);
  });

  // A finger that slides off is scrolling or changing its mind, not holding.
  tray.addEventListener('pointermove', (e) => {
    if (!start || held) return;
    if (Math.hypot(e.clientX - start.x, e.clientY - start.y) > MOVE_PX) clearTimeout(holdTimer);
  });

  const release = () => {
    clearTimeout(holdTimer);
    start = null;
    if (held) hideTip(1500);
  };
  tray.addEventListener('pointerup', release);
  tray.addEventListener('pointercancel', release);
  tray.addEventListener('pointerleave', release);

  // The click a hold ends with is swallowed before it reaches the button.
  tray.addEventListener('click', (e) => {
    if (!held) return;
    held = false;
    e.preventDefault();
    e.stopPropagation();
  }, true);

  // No long-press menu or text selection on the buttons.
  tray.addEventListener('contextmenu', (e) => {
    if (e.target.closest('button')) e.preventDefault();
  });

  window.Tray = { show, setOpen: (open) => setTray(open), isOpen };
})();
