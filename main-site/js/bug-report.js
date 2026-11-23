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
  const findElement = (selector) => {
    return document.querySelector(selector);
  };
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
  const CAPTURE_LIBRARY_URL = '/vendor/html-to-image-1.11.13/html-to-image.js';

  // The site's version, from the service worker serving it ("v15"), or null without one.
  function askVersion() {
    let controller;
    if (navigator.serviceWorker !== null && navigator.serviceWorker !== undefined) {
      controller = navigator.serviceWorker.controller;
    }
    if (!controller) {
      return Promise.resolve(null);
    }
    return new Promise((resolve) => {
      const channel = new MessageChannel();
      const timer = setTimeout(() => {
        resolve(null);
      }, VERSION_MS);
      channel.port1.onmessage = ({ data }) => {
        clearTimeout(timer);
        if (typeof data === 'string') {
          resolve(data);
        } else {
          resolve(null);
        }
      };
      controller.postMessage({ type: 'version' }, [channel.port2]);
    });
  }

  // Which app this is: the site installed, or the site in a browser. (The Android and desktop
  // apps send their own reports.)
  function platform() {
    if (window.matchMedia !== null && window.matchMedia !== undefined && window.matchMedia('(display-mode: standalone)').matches) {
      return 'pwa';
    }
    if (navigator.standalone) {
      return 'pwa';
    }
    return 'web';
  }
  const PLATFORM_NAMES = { web: 'Web', pwa: 'Web, installed' };

  const version = () => {
    if (siteVersion) {
      return `site ${siteVersion}`;
    } else {
      return '';
    }
  };

  // The system and browser, and the window's size: "Android 14 · Chrome 130 · 412×915".
  // Each [pattern, name], the first that matches; a number caught is the version.
  const SYSTEMS = [[/Android ([\d.]+)/, 'Android'], [/(?:iPhone|iPad|iPod).*? OS (\d+)/, 'iOS'], [/Windows NT/, 'Windows'],
    [/CrOS/, 'ChromeOS'], [/Mac OS X/, 'macOS'], [/Linux/, 'Linux']];
  const BROWSERS = [[/SamsungBrowser\/(\d+)/, 'Samsung Internet'], [/Edg\/(\d+)/, 'Edge'], [/Firefox\/(\d+)/, 'Firefox'],
    [/(?:Chrome|CriOS)\/(\d+)/, 'Chrome'], [/Version\/(\d+).*Safari/, 'Safari']];
  // The name (and version, when the pattern catches one) of the first pattern in `patterns`
  // that matches the user agent, or `fallback` when none does.
  function firstMatch(patterns, userAgent, fallback) {
    for (const [pattern, name] of patterns) {
      const match = pattern.exec(userAgent);
      if (match) {
        if (match[1]) {
          return `${name} ${match[1]}`;
        } else {
          return name;
        }
      }
    }
    return fallback;
  }
  function device() {
    let userAgent = navigator.userAgent;
    if (!userAgent) {
      userAgent = '';
    }
    return `${firstMatch(SYSTEMS, userAgent, 'Unknown system')} · ${firstMatch(BROWSERS, userAgent, 'Unknown browser')} · ${window.innerWidth}×${window.innerHeight}`;
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
  // Whether an element is on show; a missing element (null) is passed straight back, which
  // counts as not shown.
  const shown = (element) => {
    if (!element) {
      return element;
    }
    return !element.classList.contains('hidden') && !element.hidden;
  };

  // The page on show, and the window open over it: never a board's or a card's name.
  function page() {
    if (shown(document.getElementById('auth-overlay'))) {
      return 'Sign in';
    }
    const parts = [];
    if (shown(document.getElementById('timeline-container'))) {
      parts.push('Timeline');
    } else if (shown(document.getElementById('columns-container'))) {
      parts.push('Kanban board');
    } else {
      parts.push('No board open');
    }
    const sidebar = document.getElementById('sidebar');
    if (sidebar !== null && sidebar !== undefined && sidebar.classList.contains('open')) {
      parts.push('boards list');
    }
    for (const [id, name] of Object.entries(WINDOWS)) {
      if (shown(document.getElementById(id))) {
        parts.push(name);
      }
    }
    return parts.join(', ');
  }

  function collect() {
    const platformId = platform();
    return { version: version(), platform: platformId, device: device(), page: page(), platformName: PLATFORM_NAMES[platformId] };
  }

  // Shows `text` under the form (or hides the line when it's empty). With `email`, adds a link
  // that opens an email to Augy with the report filled in, for when the site can't send it.
  function say(text, { email = false } = {}) {
    const statusElement = findElement('#bugStatus');
    statusElement.hidden = !text;
    if (text) {
      statusElement.textContent = text;
    } else {
      statusElement.textContent = '';
    }
    if (email) {
      const body = `${findElement('#bugText').value.trim()}\n\n${detailsText()}`;
      const link = document.createElement('a');
      link.href = `mailto:${EMAIL}?subject=${encodeURIComponent('uwuBoard bug report')}&body=${encodeURIComponent(body)}`;
      link.target = '_blank';
      link.rel = 'noopener noreferrer';
      link.textContent = 'Email it instead.';
      statusElement.append(' ', link);
    }
  }

  const detailsText = () => {
    return [details.platformName, details.version, details.device, details.page].filter(Boolean).join(' · ');
  };

  function renderDetails() {
    findElement('#bugDetails').textContent = `${detailsText()}.`;
  }

  // `keepStatus`: back from a screenshot, whose outcome is on show.
  async function open({ keepStatus = false } = {}) {
    details = collect();
    renderDetails();
    if (!keepStatus) {
      say('');
    }
    window.openModal(ID);
    setTimeout(() => {
      return findElement('#bugText').focus();
    }, 50);
    // The site's version arrives a moment later, the first time.
    if (!siteVersion) {
      siteVersion = await askVersion();
      if (siteVersion && details) {
        details.version = version();
        renderDetails();
      }
    }
  }

  // ---------- pictures ----------

  function loadImage(url) {
    return new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => {
        resolve(image);
      };
      image.onerror = () => {
        reject(new Error('not an image'));
      };
      image.src = url;
    });
  }

  // An image (a File, or a data URL) as a JPEG data URL, at most SHOT_SIDE a side and about
  // SHOT_BYTES, smaller and rougher till it is.
  async function shrink(source) {
    let url;
    if (typeof source === 'string') {
      url = source;
    } else {
      url = URL.createObjectURL(source);
    }
    try {
      const image = await loadImage(url);
      let side = SHOT_SIDE;
      for (let tries = 0; tries < 6; tries = tries + 1) {
        const scaleFactor = Math.min(1, side / Math.max(image.naturalWidth, image.naturalHeight));
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(image.naturalWidth * scaleFactor));
        canvas.height = Math.max(1, Math.round(image.naturalHeight * scaleFactor));
        const context = canvas.getContext('2d');
        context.fillStyle = '#fff';
        context.fillRect(0, 0, canvas.width, canvas.height);
        context.drawImage(image, 0, 0, canvas.width, canvas.height);
        let quality;
        if (tries < 2) {
          quality = 0.82;
        } else {
          quality = 0.7;
        }
        const jpeg = canvas.toDataURL('image/jpeg', quality);
        if (jpeg.length * 0.75 <= SHOT_BYTES || tries === 5) {
          return jpeg;
        }
        side = Math.round(side * 0.8);
      }
    } finally {
      if (typeof source !== 'string') {
        URL.revokeObjectURL(url);
      }
    }
    return null;
  }

  // A whole-page screenshot (a data URL) as a JPEG data URL, as big as the page, within
  // PAGE_SIDE, PAGE_SUM and PAGE_RATIO and about SHOT_BYTES, smaller and rougher till it is.
  async function shrinkPage(source) {
    const image = await loadImage(source);
    const shortSide = Math.min(image.naturalWidth, image.naturalHeight);
    const width = Math.min(image.naturalWidth, shortSide * PAGE_RATIO);
    const height = Math.min(image.naturalHeight, shortSide * PAGE_RATIO);
    let scaleFactor = Math.min(1, PAGE_SIDE / shortSide, (PAGE_SUM - 2) / (width + height));
    for (let tries = 0; tries < 8; tries = tries + 1) {
      const canvas = document.createElement('canvas');
      canvas.width = Math.max(1, Math.floor(width * scaleFactor));
      canvas.height = Math.max(1, Math.floor(height * scaleFactor));
      const context = canvas.getContext('2d');
      context.fillStyle = '#fff';
      context.fillRect(0, 0, canvas.width, canvas.height);
      context.drawImage(image, 0, 0, width, height, 0, 0, canvas.width, canvas.height);
      let quality;
      if (tries < 2) {
        quality = 0.8;
      } else {
        quality = 0.68;
      }
      const jpeg = canvas.toDataURL('image/jpeg', quality);
      if (jpeg.length * 0.75 <= SHOT_BYTES || tries === 7) {
        return jpeg;
      }
      if (tries >= 1) {
        scaleFactor = scaleFactor * 0.82;
      }
    }
    return null;
  }

  function renderShots() {
    const box = findElement('#bugShots');
    box.innerHTML = shots.map((shot, index) => {
      return `<span class="bugShot"><img src="${shot}" alt="Picture ${index + 1}"><button type="button" class="bugShotX" data-bug-shot="${index}" aria-label="Remove picture ${index + 1}">×</button></span>`;
    }).join('');
    box.hidden = !shots.length;
    const full = shots.length >= MAX_SHOTS;
    findElement('#bugAddPic').disabled = full;
    findElement('#bugScreenshot').disabled = full;
  }

  async function addShot(source) {
    if (shots.length >= MAX_SHOTS) {
      return;
    }
    try {
      const jpeg = await shrink(source);
      if (jpeg) {
        shots.push(jpeg);
      }
    } catch {
      say("Couldn't add that picture.");
    }
    renderShots();
  }

  // The script that draws the page, the first time it's wanted.
  let captureLibraryPromise = null;
  function loadCaptureLibrary() {
    if (window.htmlToImage) {
      return Promise.resolve(window.htmlToImage);
    }
    if (captureLibraryPromise === null || captureLibraryPromise === undefined) {
      captureLibraryPromise = new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = CAPTURE_LIBRARY_URL;
        script.onload = () => {
          if (window.htmlToImage) {
            resolve(window.htmlToImage);
          } else {
            reject(new Error('no htmlToImage'));
          }
        };
        script.onerror = () => {
          captureLibraryPromise = null;
          reject(new Error('could not load'));
        };
        document.head.appendChild(script);
      });
    }
    return captureLibraryPromise;
  }

  // ---------- Screenshot a page ----------

  // Off to the page to find what to take: the form put away (what's typed stays in it), and the
  // bar floating over the page.
  function screenshotAPage() {
    if (shots.length >= MAX_SHOTS) {
      return;
    }
    loadCaptureLibrary().catch(() => {}); // fetched while they find the page
    window.closeModal(ID);
    const bar = findElement('#bugShotBar');
    bar.hidden = false;
    findElement('#bugShotTake').disabled = false;
    findElement('#bugShotTakeLabel').textContent = 'Screenshot this page';
    setTimeout(() => {
      return findElement('#bugShotTake').focus();
    }, 50);
  }

  function backToForm(status) {
    findElement('#bugShotBar').hidden = true;
    if (status) {
      say(status);
    } else {
      say('');
    }
    open({ keepStatus: true });
  }

  // Once nothing on the page is moving (a window fading in or out), or after a second at most.
  async function settled() {
    // The animations running now, leaving out ones that repeat forever (they never stop).
    const moving = () => {
      let running;
      if (document.getAnimations !== null && document.getAnimations !== undefined) {
        running = document.getAnimations().filter((animation) => {
          if (animation.playState !== 'running') {
            return false;
          }
          let iterations;
          if (animation.effect !== null && animation.effect !== undefined) {
            iterations = animation.effect.getComputedTiming().iterations;
          }
          return iterations !== Infinity;
        });
      }
      if (!running) {
        running = [];
      }
      return running;
    };
    const until = Date.now() + 1000;
    while (moving().length && Date.now() < until) {
      await new Promise((resolve) => {
        setTimeout(resolve, 50);
      });
    }
  }

  // A number from the page that may be missing (or 0): 0 in that case.
  function numberOrZero(value) {
    if (!value) {
      return 0;
    }
    return value;
  }

  // The page as it is now, drawn: the whole of it, from the top, however far down (or across) it
  // goes. The bar, the form and toasts are left out.
  async function takeScreenshot() {
    if (shots.length >= MAX_SHOTS) {
      backToForm();
      return;
    }
    const button = findElement('#bugShotTake');
    button.disabled = true;
    findElement('#bugShotTakeLabel').textContent = 'Taking a screenshot…';
    let status = '';
    try {
      const captureLibrary = await loadCaptureLibrary();
      // A window that has only just opened is still fading in: drawn now, it'd be see-through.
      await settled();
      const pageBackground = getComputedStyle(document.body).backgroundColor;
      let scrollRoot = document.scrollingElement;
      if (!scrollRoot) {
        scrollRoot = document.documentElement;
      }
      const width = Math.max(window.innerWidth, numberOrZero(scrollRoot.scrollWidth), numberOrZero(document.body.scrollWidth));
      const height = Math.max(window.innerHeight, numberOrZero(scrollRoot.scrollHeight), numberOrZero(document.body.scrollHeight));
      const big = height > window.innerHeight + 4 || width > window.innerWidth + 4;
      let devicePixelRatio = window.devicePixelRatio;
      if (!devicePixelRatio) {
        devicePixelRatio = 1;
      }
      let backgroundColor;
      if (pageBackground && pageBackground !== 'rgba(0, 0, 0, 0)') {
        backgroundColor = pageBackground;
      } else {
        backgroundColor = '#ffffff';
      }
      const url = await captureLibrary.toJpeg(document.body, {
        quality: 0.85,
        pixelRatio: Math.min(2, devicePixelRatio, PAGE_DRAW / Math.max(width, height)),
        width,
        height,
        backgroundColor,
        cacheBust: false,
        imagePlaceholder: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=',
        // What isn't the page: this bar, the form and toasts. And what can't be drawn, which
        // would spoil the whole picture: video, and an image with nothing in it yet.
        filter: (node) => {
          if (node.id === 'bugShotBar' || node.id === ID || node.id === 'toast-container') {
            return false;
          }
          if (node.tagName === 'VIDEO') {
            return false;
          }
          if (node.tagName === 'IMG' && (!node.currentSrc || !node.complete || !node.naturalWidth)) {
            return false;
          }
          return true;
        },
      });
      if (big) {
        const picture = await shrinkPage(url);
        if (picture && shots.length < MAX_SHOTS) {
          shots.push(picture);
          fullShots.add(shots.length - 1);
        }
      } else {
        await addShot(url);
      }
    } catch (error) {
      console.warn("couldn't take the screenshot:", error);
      status = "Couldn't take a screenshot here. Take one with your device and add it instead.";
    } finally {
      renderShots();
      backToForm(status);
    }
  }

  // ---------- sending ----------

  // Sends the report to api/bug-report.js: what's typed, the details, the contact and the
  // pictures. On success the form is cleared and the report's ID shown; on failure it says why,
  // offering email when the site itself can't send it.
  async function send(event) {
    event.preventDefault();
    if (sending) {
      return;
    }
    const text = findElement('#bugText').value.trim();
    if (text.length < MIN_TEXT) {
      say('Please say what went wrong first.');
      findElement('#bugText').focus();
      return;
    }
    if (navigator.onLine === false) {
      say("You're offline. It's kept here: send it once you're back online.");
      return;
    }
    sending = true;
    findElement('#bugSend').disabled = true;
    say('Sending…');
    try {
      const { platformName, ...sent } = details;
      const response = await fetch('/api/bug-report', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ ...sent, text, contact: findElement('#bugContact').value.trim(), website: findElement('#bugWebsite').value, images: shots, full: [...fullShots] }),
      });
      if (response.ok) {
        findElement('#bugText').value = '';
        findElement('#bugContact').value = '';
        shots = [];
        fullShots = new Set();
        renderShots();
        // Its ID, to quote.
        const id = await response.json().then((data) => {
          if (data !== null && data !== undefined && typeof data.id === 'string') {
            return data.id;
          }
          return null;
        }).catch(() => {
          return null;
        });
        if (id) {
          say(`Sent as report ${id}. Thank you! Augy will look into it.`);
        } else {
          say('Sent. Thank you! Augy will look into it.');
        }
        return;
      }
      const errorMessage = await response.json().then((data) => {
        if (data === null || data === undefined) {
          return undefined;
        }
        return data.error;
      }).catch(() => {
        return null;
      });
      // Something about what was typed, or too many at once: said as it is. Otherwise, email.
      if (response.status === 400 || response.status === 413 || response.status === 429) {
        if (errorMessage) {
          say(errorMessage);
        } else {
          say("Couldn't send it right now.");
        }
      } else {
        if (response.status === 503) {
          say("Bug reports can't be sent from the app yet.", { email: true });
        } else {
          say("Couldn't send it right now.", { email: true });
        }
      }
    } catch {
      say("Couldn't send it right now.", { email: true });
    } finally {
      sending = false;
      findElement('#bugSend').disabled = false;
    }
  }

  // Hooks up the form's buttons, the picture picker, removing a picture, the tray's button,
  // and closing the window from its backdrop or with Escape.
  function init() {
    if (!document.getElementById(ID)) {
      return;
    }
    findElement('#bugForm').addEventListener('submit', send);
    findElement('#bugAddPic').addEventListener('click', () => {
      return findElement('#bugPicFile').click();
    });
    findElement('#bugPicFile').addEventListener('change', async (event) => {
      let pickedFiles = event.target.files;
      if (!pickedFiles) {
        pickedFiles = [];
      }
      const files = [...pickedFiles].slice(0, MAX_SHOTS - shots.length);
      event.target.value = '';
      for (const file of files) {
        await addShot(file);
      }
    });
    findElement('#bugScreenshot').addEventListener('click', screenshotAPage);
    findElement('#bugShotTake').addEventListener('click', takeScreenshot);
    findElement('#bugShotCancel').addEventListener('click', () => {
      return backToForm();
    });
    findElement('#bugShots').addEventListener('click', (event) => {
      const removeButton = event.target.closest('[data-bug-shot]');
      if (!removeButton) {
        return;
      }
      const removedIndex = Number(removeButton.dataset.bugShot);
      shots.splice(removedIndex, 1);
      // The whole-page marks follow their pictures: the ones after the removed one move up.
      fullShots = new Set([...fullShots].filter((shotIndex) => {
        return shotIndex !== removedIndex;
      }).map((shotIndex) => {
        if (shotIndex > removedIndex) {
          return shotIndex - 1;
        } else {
          return shotIndex;
        }
      }));
      renderShots();
    });
    const trayButton = findElement('#bugBtn');
    if (trayButton !== null && trayButton !== undefined) {
      trayButton.addEventListener('click', () => {
        return open();
      });
    }
    const backdrop = document.getElementById(ID);
    backdrop.addEventListener('click', (event) => {
      if (event.target === backdrop) {
        window.closeModal(ID);
      }
    });
    document.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && !event.defaultPrevented) {
        window.closeModal(ID);
      }
    });
    renderShots();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init, { once: true });
  } else {
    init();
  }

  window.BugReport = { open };
})();
