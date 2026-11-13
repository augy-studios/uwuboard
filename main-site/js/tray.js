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

  window.Tray = { show, setOpen: (open) => setTray(open), isOpen };
})();
