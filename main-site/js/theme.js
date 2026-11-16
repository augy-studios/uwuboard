'use strict';

// Theme system: 7 brand colour swatches + light/dark/time-based mode.
// Default is always light + classic (#ccffcc), regardless of OS preference.
// Once the user picks something, it is persisted.

const APP_KEY = 'uwuboard';

const COLOR_THEMES = [
  { id: 'classic', label: 'Classic', hex: '#ccffcc' },
  { id: 'not-green-1', label: 'Not green 1', hex: '#ffcccc' },
  { id: 'not-green-2', label: 'Not green 2', hex: '#ccccff' },
  { id: 'not-green-3', label: 'Not green 3', hex: '#ffffcc' },
  { id: 'not-green-4', label: 'Not green 4', hex: '#ffccff' },
  { id: 'not-green-5', label: 'Not green 5', hex: '#ccffff' },
  { id: 'really-light-green', label: 'Really really light green', hex: '#ffffff' },
];

const STORAGE_KEY_COLOR = `${APP_KEY}.colorTheme`;
const STORAGE_KEY_MODE = `${APP_KEY}.mode`;

// Pre-mode-axis key. Maps 1:1 onto the new swatch ids.
const LEGACY_KEY = 'uwuboard_theme';
const LEGACY_COLORS = {
  classic: 'classic',
  pink: 'not-green-1',
  blue: 'not-green-2',
  yellow: 'not-green-3',
  magenta: 'not-green-4',
  cyan: 'not-green-5',
  white: 'really-light-green',
};

// Moves a colour saved under the old single theme key onto the new swatch key, once.
function migrateLegacyTheme() {
  const legacyTheme = localStorage.getItem(LEGACY_KEY);
  if (!legacyTheme) {
    return;
  }
  if (!localStorage.getItem(STORAGE_KEY_COLOR) && LEGACY_COLORS[legacyTheme]) {
    localStorage.setItem(STORAGE_KEY_COLOR, LEGACY_COLORS[legacyTheme]);
  }
  localStorage.removeItem(LEGACY_KEY);
}

// "#rrggbb" to "red, green, blue" as three numbers from 0 to 255.
function hexToRgb(hex) {
  const colorNumber = parseInt(hex.replace('#', ''), 16);
  return `${(colorNumber >> 16) & 255}, ${(colorNumber >> 8) & 255}, ${colorNumber & 255}`;
}

function getStoredColorTheme() {
  const storedTheme = localStorage.getItem(STORAGE_KEY_COLOR);
  if (!storedTheme) {
    return 'classic';
  }
  return storedTheme;
}

/* Mode preference and mode are different things. The preference is what the
   person chose and can be "time"; the mode is what the document is in and
   is only ever light or dark. */

const MODE_PREFERENCES = ['light', 'dark', 'time'];

/* The daylight window. Duplicated in the pre-paint script in index.html's
   head, which has to resolve this before first paint and cannot import
   anything. Change both together. */
const LIGHT_FROM_HOUR = 9;
const LIGHT_UNTIL_HOUR = 18;

function getModePreference() {
  const storedPreference = localStorage.getItem(STORAGE_KEY_MODE);
  if (MODE_PREFERENCES.includes(storedPreference)) {
    return storedPreference;
  }
  return 'light';
}

function isDaylightHours(now = new Date()) {
  const hour = now.getHours();
  return hour >= LIGHT_FROM_HOUR && hour < LIGHT_UNTIL_HOUR;
}

function resolveMode(preference) {
  if (preference === 'time') {
    if (isDaylightHours()) {
      return 'light';
    }
    return 'dark';
  }
  if (preference === 'dark') {
    return 'dark';
  }
  return 'light';
}

// The mode the document is in right now, resolved. What the theme button
// icon and anything else reading the active mode wants.
function getStoredMode() {
  return resolveMode(getModePreference());
}

// Paints the page in the swatch with this id (or Classic if it's unknown) and remembers it.
function applyColorTheme(id) {
  let theme = COLOR_THEMES.find((candidate) => {
    return candidate.id === id;
  });
  if (!theme) {
    theme = COLOR_THEMES[0];
  }
  document.documentElement.setAttribute('data-color-theme', theme.id);
  document.documentElement.style.setProperty('--brand', theme.hex);
  document.documentElement.style.setProperty('--brand-rgb', hexToRgb(theme.hex));
  localStorage.setItem(STORAGE_KEY_COLOR, theme.id);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) {
    meta.setAttribute('content', theme.hex);
  }
  return theme;
}

// Puts the page in light or dark for this preference ('light', 'dark' or 'time'),
// remembers the preference, and returns the mode it resolved to.
function applyMode(preference) {
  let chosen;
  if (MODE_PREFERENCES.includes(preference)) {
    chosen = preference;
  } else {
    chosen = 'light';
  }
  const resolved = resolveMode(chosen);

  document.documentElement.setAttribute('data-mode', resolved);
  document.documentElement.setAttribute('data-mode-preference', chosen);
  localStorage.setItem(STORAGE_KEY_MODE, chosen);

  scheduleModeCheck();

  return resolved;
}

/* Keeping the time based mode honest while the page stays open. */

let modeTimer = null;
let watchingVisibility = false;

// Milliseconds until the next 09:00 or 18:00, whichever comes first.
function millisecondsUntilNextBoundary(now = new Date()) {
  const next = new Date(now);
  next.setMinutes(0, 0, 0);

  const hour = now.getHours();
  if (hour < LIGHT_FROM_HOUR) {
    next.setHours(LIGHT_FROM_HOUR);
  } else if (hour < LIGHT_UNTIL_HOUR) {
    next.setHours(LIGHT_UNTIL_HOUR);
  } else {
    next.setDate(next.getDate() + 1);
    next.setHours(LIGHT_FROM_HOUR);
  }

  // A second of slack, so a timer that fires a fraction early does not land
  // back in the hour it just left and reschedule itself in a tight loop.
  return Math.max(1000, next.getTime() - now.getTime() + 1000);
}

// With the "time" preference, sets a timer for the next 09:00 or 18:00 so the mode
// flips on time, and re-checks whenever the tab becomes visible again.
function scheduleModeCheck() {
  if (modeTimer !== null) {
    clearTimeout(modeTimer);
    modeTimer = null;
  }

  if (getModePreference() !== 'time') {
    return;
  }

  modeTimer = setTimeout(() => {
    modeTimer = null;
    refreshTimeMode();
  }, millisecondsUntilNextBoundary());

  if (!watchingVisibility && typeof document !== 'undefined') {
    watchingVisibility = true;
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') {
        refreshTimeMode();
      }
    });
  }
}

// Re-resolves the "time" preference and, if the mode changed, tells the page.
function refreshTimeMode() {
  if (getModePreference() !== 'time') {
    return;
  }

  const resolved = resolveMode('time');
  const current = document.documentElement.getAttribute('data-mode');

  if (resolved !== current) {
    document.documentElement.setAttribute('data-mode', resolved);
    document.dispatchEvent(
      new CustomEvent('uwu:modechange', {
        detail: { mode: resolved, preference: 'time' },
      })
    );
  }

  scheduleModeCheck();
}

function initTheme() {
  migrateLegacyTheme();
  applyColorTheme(getStoredColorTheme());
  // The preference, not the resolved mode. Passing the resolved one would
  // quietly rewrite a stored "time" into "dark" the first evening.
  applyMode(getModePreference());
}

/* ── Theme modal wiring ── */

// Fills the theme window with a button per colour swatch and wires up the swatch and
// light/dark/time buttons.
function buildThemeModal() {
  const grid = document.getElementById('swatchGrid');
  grid.innerHTML = COLOR_THEMES.map(
    (theme) => {
      return `
      <button class="swatch" data-theme-id="${theme.id}" style="--swatch-color:${theme.hex}" type="button" aria-label="${theme.label}">
        <span class="swatch-dot"></span>
        <span class="swatch-label">${theme.label}</span>
      </button>`;
    }
  ).join('');

  syncThemeModalState();

  grid.addEventListener('click', (event) => {
    const button = event.target.closest('[data-theme-id]');
    if (!button) {
      return;
    }
    applyColorTheme(button.dataset.themeId);
    syncThemeModalState();
  });

  document.getElementById('modeToggle').addEventListener('click', (event) => {
    const button = event.target.closest('[data-mode]');
    if (!button) {
      return;
    }
    applyMode(button.dataset.mode);
    syncThemeModalState();
  });

  // A tab left open across 09:00 or 18:00 re-resolves itself; redraw the
  // modal so the note and pressed state stay in step with the change.
  document.addEventListener('uwu:modechange', syncThemeModalState);
}

// Marks the chosen swatch and mode button as pressed, and shows the "following the clock"
// note when the time preference is on.
function syncThemeModalState() {
  const activeTheme = getStoredColorTheme();
  const activePreference = getModePreference();
  const resolvedMode = getStoredMode();

  document.querySelectorAll('#swatchGrid .swatch').forEach((swatch) => {
    swatch.classList.toggle('active', swatch.dataset.themeId === activeTheme);
  });
  document.querySelectorAll('#modeToggle .mode-btn').forEach((modeButton) => {
    const isActive = modeButton.dataset.mode === activePreference;
    modeButton.classList.toggle('active', isActive);
    modeButton.setAttribute('aria-pressed', String(isActive));
  });

  const note = document.getElementById('modeNote');
  if (note) {
    note.hidden = activePreference !== 'time';
    if (activePreference === 'time') {
      note.textContent = `Following the clock. Currently ${resolvedMode}.`;
    }
  }

  updateThemeButtonIcon();
}

function updateThemeButtonIcon() {
  const iconHolder = document.querySelector('#themeBtn [data-icon]');
  let iconName;
  if (getStoredMode() === 'dark') {
    iconName = 'moon';
  } else {
    iconName = 'sun';
  }
  iconHolder.setAttribute('data-icon', iconName);
  hydrateIcons(document.getElementById('themeBtn'));
}

// Scoped to the theme modal: the app modals already wire their own close
// and backdrop handlers in script.js.
function wireModals() {
  document.querySelectorAll('[data-close-modal]').forEach((button) => {
    button.addEventListener('click', () => {
      closeModal(button.dataset.closeModal);
    });
  });
  const backdrop = document.getElementById('themeModal');
  backdrop.addEventListener('click', (event) => {
    if (event.target === backdrop) {
      closeModal(backdrop.id);
    }
  });
  document.getElementById('themeBtn').addEventListener('click', () => {
    openModal('themeModal');
  });
}

initTheme();
hydrateIcons();
updateThemeButtonIcon();
buildThemeModal();
wireModals();

window.COLOR_THEMES = COLOR_THEMES;
window.applyColorTheme = applyColorTheme;
window.applyMode = applyMode;
window.getStoredColorTheme = getStoredColorTheme;
window.getStoredMode = getStoredMode;
window.initTheme = initTheme;
window.MODE_PREFERENCES = MODE_PREFERENCES;
window.LIGHT_FROM_HOUR = LIGHT_FROM_HOUR;
window.LIGHT_UNTIL_HOUR = LIGHT_UNTIL_HOUR;
window.getModePreference = getModePreference;
window.isDaylightHours = isDaylightHours;
window.resolveMode = resolveMode;
window.refreshTimeMode = refreshTimeMode;
