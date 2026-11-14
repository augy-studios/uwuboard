// Report a bug, from the edge tray: a small form for what went wrong, and a way to be reached if
// they'd like an answer, sent to Augy on Telegram by api/bug-report.js. The same form as SG Bus
// Timings', and the apps' (flutter/lib/features/bug/bug_report.dart).
//
// The form adds what helps find the bug, and says so under the box before it's sent: which app
// and its version (the site's, from sw.js), the device as the browser describes it, and the page
// on show (the kind of page, and which window is open: never a board's or a card's name). Nothing
// else goes.
//
// What's typed stays while the page is open, closed or not, until it's sent. Offline it waits for
// the connection. If the site can't send it (not set up, or Telegram's down), it offers email
// instead, with the same words filled in.
//
// Pictures, up to MAX_SHOTS: picked from the device (any image), or Screenshot a page. That puts
// the form away and leaves you on the page, to go where the bug is (open a card, switch to the
// Timeline), with a bar floating at the bottom: its Screenshot this page draws the page as it is
// (vendor/html-to-image, loaded the first time it's used), the whole page top to bottom, not only
// the part on the screen, and brings you back to the form. The bar is left out of the picture.
// Each picture is made a JPEG of at most SHOT_SIDE pixels a side and about SHOT_BYTES before it's
// sent, and kept with what's typed until it's sent. A screenshot of a page taller (or wider) than
// the screen is kept as big as it is instead (shrinkPage), within what Telegram takes as a photo,
// and sent marked `full`, so it also reaches Augy as a file at its full size (api/bug-report.js).
//
// Once it's sent, the form says the report's ID (api/bug-report.js, reportId), to quote.
//
// window.BugReport = { open() }. Plain script: exports go on window.
(function () {
  const $ = (sel) => document.querySelector(sel);
  const ID = 'bugModal';
  const EMAIL = 'augy@augystudios.com';
  const MIN_TEXT = 5;
  const VERSION_MS = 1500;

  let siteVersion = null;
  let details = null;
  let sending = false;
  // The pictures to send, as JPEG data URLs, and which of them are whole-page screenshots.
  let shots = [];
  let fullShots = new Set();
  const MAX_SHOTS = 3;
  const SHOT_SIDE = 1600;
  const SHOT_BYTES = 900 * 1024;
  // A whole-page screenshot: at most PAGE_SIDE across its shorter side, and within Telegram's
  // limits for a photo, width and height PAGE_SUM at most together and the longer side PAGE_RATIO
  // times the shorter at most (any more is cut off at the bottom or the right). Drawn at most
  // PAGE_DRAW pixels along its longer side, as a browser won't make a canvas much bigger.
  const PAGE_SIDE = 1080;
  const PAGE_SUM = 10000;
  const PAGE_RATIO = 20;
  const PAGE_DRAW = 16000;
  const CAPTURE_LIB = '/vendor/html-to-image-1.11.13/html-to-image.js';

  // The site's version, from the service worker serving it ("v15"), or null without one.
  function askVersion() {
    const sw = navigator.serviceWorker?.controller;
    if (!sw) return Promise.resolve(null);
    return new Promise((resolve) => {
      const channel = new MessageChannel();
      const timer = setTimeout(() => resolve(null), VERSION_MS);
      channel.port1.onmessage = ({ data }) => { clearTimeout(timer); resolve(typeof data === 'string' ? data : null); };
      sw.postMessage({ type: 'version' }, [channel.port2]);
    });
  }

  // Which app this is: the site installed, or the site in a browser. (The Android and desktop
  // apps send their own reports.)
  function platform() {
    if (window.matchMedia?.('(display-mode: standalone)').matches || navigator.standalone) return 'pwa';
    return 'web';
  }
  const PLATFORM_NAMES = { web: 'Web', pwa: 'Web, installed' };

  const version = () => (siteVersion ? `site ${siteVersion}` : '');

  // The system and browser, and the window's size: "Android 14 · Chrome 130 · 412×915".
  // Each [pattern, name], the first that matches; a number caught is the version.
  const SYSTEMS = [[/Android ([\d.]+)/, 'Android'], [/(?:iPhone|iPad|iPod).*? OS (\d+)/, 'iOS'], [/Windows NT/, 'Windows'],
    [/CrOS/, 'ChromeOS'], [/Mac OS X/, 'macOS'], [/Linux/, 'Linux']];
  const BROWSERS = [[/SamsungBrowser\/(\d+)/, 'Samsung Internet'], [/Edg\/(\d+)/, 'Edge'], [/Firefox\/(\d+)/, 'Firefox'],
    [/(?:Chrome|CriOS)\/(\d+)/, 'Chrome'], [/Version\/(\d+).*Safari/, 'Safari']];
  function first(list, ua, none) {
    for (const [re, name] of list) {
      const m = re.exec(ua);
      if (m) return m[1] ? `${name} ${m[1]}` : name;
    }
    return none;
  }
  function device() {
    const ua = navigator.userAgent || '';
    return `${first(SYSTEMS, ua, 'Unknown system')} · ${first(BROWSERS, ua, 'Unknown browser')} · ${window.innerWidth}×${window.innerHeight}`;
  }

  // The windows that can be open over the page, by what they're called.
  const WINDOWS = {
    'card-modal': 'card window',
    'new-board-modal': 'New board',
    'rename-col-modal': 'Rename column',
    'col-picker-sheet': 'Move to column',
    'reorder-cols-modal': 'Reorder columns',
    'profile-modal': 'Profile',
    'delete-account-modal': 'Delete account',
    themeModal: 'Theme',
    syncModal: 'Sync',
    tourModal: 'Show me around',
  };
  const shown = (el) => el && !el.classList.contains('hidden') && !el.hidden;

  // The page on show, and the window open over it: never a board's or a card's name.
  function page() {
    if (shown(document.getElementById('auth-overlay'))) return 'Sign in';
    const parts = [];
    if (shown(document.getElementById('timeline-container'))) parts.push('Timeline');
    else if (shown(document.getElementById('columns-container'))) parts.push('Kanban board');
    else parts.push('No board open');
    if (document.getElementById('sidebar')?.classList.contains('open')) parts.push('boards list');
    for (const [id, name] of Object.entries(WINDOWS)) if (shown(document.getElementById(id))) parts.push(name);
    return parts.join(', ');
  }

  function collect() {
    const p = platform();
    return { version: version(), platform: p, device: device(), page: page(), platformName: PLATFORM_NAMES[p] };
  }

  function say(text, { email = false } = {}) {
    const el = $('#bugStatus');
    el.hidden = !text;
    el.textContent = text || '';
    if (email) {
      const body = `${$('#bugText').value.trim()}\n\n${detailsText()}`;
      const a = document.createElement('a');
      a.href = `mailto:${EMAIL}?subject=${encodeURIComponent('uwuBoard bug report')}&body=${encodeURIComponent(body)}`;
      a.target = '_blank';
      a.rel = 'noopener noreferrer';
      a.textContent = 'Email it instead.';
      el.append(' ', a);
    }
  }

  const detailsText = () => [details.platformName, details.version, details.device, details.page].filter(Boolean).join(' · ');

  function renderDetails() {
    $('#bugDetails').textContent = `${detailsText()}.`;
  }

  // `keepStatus`: back from a screenshot, whose outcome is on show.
  async function open({ keepStatus = false } = {}) {
    details = collect();
    renderDetails();
    if (!keepStatus) say('');
    window.openModal(ID);
    setTimeout(() => $('#bugText').focus(), 50);
    // The site's version arrives a moment later, the first time.
    if (!siteVersion) {
      siteVersion = await askVersion();
      if (siteVersion && details) { details.version = version(); renderDetails(); }
    }
  }

  // ---------- pictures ----------

  function loadImage(url) {
    return new Promise((resolve, reject) => {
      const i = new Image();
      i.onload = () => resolve(i);
      i.onerror = () => reject(new Error('not an image'));
      i.src = url;
    });
  }

  // An image (a File, or a data URL) as a JPEG data URL, at most SHOT_SIDE a side and about
  // SHOT_BYTES, smaller and rougher till it is.
  async function shrink(src) {
    const url = typeof src === 'string' ? src : URL.createObjectURL(src);
    try {
      const img = await loadImage(url);
      let side = SHOT_SIDE;
      for (let tries = 0; tries < 6; tries++) {
        const k = Math.min(1, side / Math.max(img.naturalWidth, img.naturalHeight));
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(img.naturalWidth * k));
        canvas.height = Math.max(1, Math.round(img.naturalHeight * k));
        const ctx = canvas.getContext('2d');
        ctx.fillStyle = '#fff';
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        const out = canvas.toDataURL('image/jpeg', tries < 2 ? 0.82 : 0.7);
        if (out.length * 0.75 <= SHOT_BYTES || tries === 5) return out;
        side = Math.round(side * 0.8);
      }
    } finally {
      if (typeof src !== 'string') URL.revokeObjectURL(url);
    }
    return null;
  }

  // A whole-page screenshot (a data URL) as a JPEG data URL, as big as the page, within
  // PAGE_SIDE, PAGE_SUM and PAGE_RATIO and about SHOT_BYTES, smaller and rougher till it is.
  async function shrinkPage(src) {
    const img = await loadImage(src);
    const short = Math.min(img.naturalWidth, img.naturalHeight);
    const w = Math.min(img.naturalWidth, short * PAGE_RATIO);
    const h = Math.min(img.naturalHeight, short * PAGE_RATIO);
    let k = Math.min(1, PAGE_SIDE / short, (PAGE_SUM - 2) / (w + h));
    for (let tries = 0; tries < 8; tries++) {
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.floor(w * k));
      canvas.height = Math.max(1, Math.floor(h * k));
      const ctx = canvas.getContext('2d');
      ctx.fillStyle = '#fff';
      ctx.fillRect(0, 0, canvas.width, canvas.height);
      ctx.drawImage(img, 0, 0, w, h, 0, 0, canvas.width, canvas.height);
      const out = canvas.toDataURL('image/jpeg', tries < 2 ? 0.8 : 0.68);
      if (out.length * 0.75 <= SHOT_BYTES || tries === 7) return out;
      if (tries >= 1) k *= 0.82;
    }
    return null;
  }

  function renderShots() {
    const box = $('#bugShots');
    box.innerHTML = shots.map((s, i) => `<span class="bugShot"><img src="${s}" alt="Picture ${i + 1}"><button type="button" class="bugShotX" data-bug-shot="${i}" aria-label="Remove picture ${i + 1}">×</button></span>`).join('');
    box.hidden = !shots.length;
    const full = shots.length >= MAX_SHOTS;
    $('#bugAddPic').disabled = full;
    $('#bugScreenshot').disabled = full;
  }

  async function addShot(src) {
    if (shots.length >= MAX_SHOTS) return;
    try {
      const jpeg = await shrink(src);
      if (jpeg) shots.push(jpeg);
    } catch {
      say("Couldn't add that picture.");
    }
    renderShots();
  }

  // The script that draws the page, the first time it's wanted.
  let lib = null;
  function captureLib() {
    if (window.htmlToImage) return Promise.resolve(window.htmlToImage);
    lib ??= new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = CAPTURE_LIB;
      s.onload = () => (window.htmlToImage ? resolve(window.htmlToImage) : reject(new Error('no htmlToImage')));
      s.onerror = () => { lib = null; reject(new Error('could not load')); };
      document.head.appendChild(s);
    });
    return lib;
  }

  // ---------- Screenshot a page ----------

  // Off to the page to find what to take: the form put away (what's typed stays in it), and the
  // bar floating over the page.
  function screenshotAPage() {
    if (shots.length >= MAX_SHOTS) return;
    captureLib().catch(() => {}); // fetched while they find the page
    window.closeModal(ID);
    const bar = $('#bugShotBar');
    bar.hidden = false;
    $('#bugShotTake').disabled = false;
    $('#bugShotTakeLabel').textContent = 'Screenshot this page';
    setTimeout(() => $('#bugShotTake').focus(), 50);
  }

  function backToForm(status) {
    $('#bugShotBar').hidden = true;
    say(status || '');
    open({ keepStatus: true });
  }

  // Once nothing on the page is moving (a window fading in or out), or after a second at most.
  async function settled() {
    const moving = () => document.getAnimations?.().filter((x) => x.playState === 'running' && x.effect?.getComputedTiming().iterations !== Infinity) || [];
    const until = Date.now() + 1000;
    while (moving().length && Date.now() < until) await new Promise((r) => setTimeout(r, 50));
  }

  // The page as it is now, drawn: the whole of it, from the top, however far down (or across) it
  // goes. The bar, the form and toasts are left out.
  async function takeScreenshot() {
    if (shots.length >= MAX_SHOTS) return backToForm();
    const btn = $('#bugShotTake');
    btn.disabled = true;
    $('#bugShotTakeLabel').textContent = 'Taking a screenshot…';
    let status = '';
    try {
      const h2i = await captureLib();
      // A window that has only just opened is still fading in: drawn now, it'd be see-through.
      await settled();
      const bg = getComputedStyle(document.body).backgroundColor;
      const root = document.scrollingElement || document.documentElement;
      const width = Math.max(window.innerWidth, root.scrollWidth || 0, document.body.scrollWidth || 0);
      const height = Math.max(window.innerHeight, root.scrollHeight || 0, document.body.scrollHeight || 0);
      const big = height > window.innerHeight + 4 || width > window.innerWidth + 4;
      const url = await h2i.toJpeg(document.body, {
        quality: 0.85,
        pixelRatio: Math.min(2, window.devicePixelRatio || 1, PAGE_DRAW / Math.max(width, height)),
        width,
        height,
        backgroundColor: bg && bg !== 'rgba(0, 0, 0, 0)' ? bg : '#ffffff',
        cacheBust: false,
        imagePlaceholder: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=',
        // What isn't the page: this bar, the form and toasts. And what can't be drawn, which
        // would spoil the whole picture: video, and an image with nothing in it yet.
        filter: (node) => !(node.id === 'bugShotBar' || node.id === ID || node.id === 'toast-container')
          && node.tagName !== 'VIDEO'
          && !(node.tagName === 'IMG' && (!node.currentSrc || !node.complete || !node.naturalWidth)),
      });
      if (big) {
        const pic = await shrinkPage(url);
        if (pic && shots.length < MAX_SHOTS) {
          shots.push(pic);
          fullShots.add(shots.length - 1);
        }
      } else {
        await addShot(url);
      }
    } catch (err) {
      console.warn("couldn't take the screenshot:", err);
      status = "Couldn't take a screenshot here. Take one with your device and add it instead.";
    } finally {
      renderShots();
      backToForm(status);
    }
  }

  // ---------- sending ----------

  async function send(e) {
    e.preventDefault();
    if (sending) return;
    const text = $('#bugText').value.trim();
    if (text.length < MIN_TEXT) {
      say('Please say what went wrong first.');
      $('#bugText').focus();
      return;
    }
    if (navigator.onLine === false) {
      say("You're offline. It's kept here: send it once you're back online.");
      return;
    }
    sending = true;
    $('#bugSend').disabled = true;
    say('Sending…');
    try {
      const { platformName, ...sent } = details;
      const r = await fetch('/api/bug-report', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...sent, text, contact: $('#bugContact').value.trim(), website: $('#bugWebsite').value, images: shots, full: [...fullShots] }),
      });
      if (r.ok) {
        $('#bugText').value = '';
        $('#bugContact').value = '';
        shots = [];
        fullShots = new Set();
        renderShots();
        // Its ID, to quote.
        const id = await r.json().then((d) => (typeof d?.id === 'string' ? d.id : null)).catch(() => null);
        say(id ? `Sent as report ${id}. Thank you! Augy will look into it.` : 'Sent. Thank you! Augy will look into it.');
        return;
      }
      const err = await r.json().then((d) => d?.error).catch(() => null);
      // Something about what was typed, or too many at once: said as it is. Otherwise, email.
      if (r.status === 400 || r.status === 413 || r.status === 429) say(err || "Couldn't send it right now.");
      else say(r.status === 503 ? "Bug reports can't be sent from the app yet." : "Couldn't send it right now.", { email: true });
    } catch {
      say("Couldn't send it right now.", { email: true });
    } finally {
      sending = false;
      $('#bugSend').disabled = false;
    }
  }

  function init() {
    if (!document.getElementById(ID)) return;
    $('#bugForm').addEventListener('submit', send);
    $('#bugAddPic').addEventListener('click', () => $('#bugPicFile').click());
    $('#bugPicFile').addEventListener('change', async (e) => {
      const files = [...(e.target.files || [])].slice(0, MAX_SHOTS - shots.length);
      e.target.value = '';
      for (const f of files) await addShot(f);
    });
    $('#bugScreenshot').addEventListener('click', screenshotAPage);
    $('#bugShotTake').addEventListener('click', takeScreenshot);
    $('#bugShotCancel').addEventListener('click', () => backToForm());
    $('#bugShots').addEventListener('click', (e) => {
      const x = e.target.closest('[data-bug-shot]');
      if (!x) return;
      const n = Number(x.dataset.bugShot);
      shots.splice(n, 1);
      fullShots = new Set([...fullShots].filter((i) => i !== n).map((i) => (i > n ? i - 1 : i)));
      renderShots();
    });
    $('#bugBtn')?.addEventListener('click', () => open());
    const backdrop = document.getElementById(ID);
    backdrop.addEventListener('click', (e) => { if (e.target === backdrop) window.closeModal(ID); });
    document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && !e.defaultPrevented) window.closeModal(ID); });
    renderShots();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, { once: true });
  else init();

  window.BugReport = { open };
})();
