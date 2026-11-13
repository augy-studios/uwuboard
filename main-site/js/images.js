'use strict';

/* Card images and the avatar, shown through blob: URLs so the page never holds where an image
   is stored (docs/hide-images-spec.md). A signed-in user's image is fetched by its name from
   /api/images/get with the session in a header; a guest's is the data URL kept in this
   browser; an old guest copy that still has a public `url` is read from it once. Whichever,
   only a blob: URL ever goes into the markup.

   Each image is fetched once per session and its URL kept, so redrawing the board reuses it
   rather than fetching again. They're all released on sign-out (clear()), when the account
   they belong to goes away. */
(function () {
  let token = null;
  const cache = new Map(); // key -> Promise<{ blob, url }>
  let avatarEntry = null;  // Promise<{ blob, url }> | null

  async function fetchBlob(url, options) {
    const r = await fetch(url, options);
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return r.blob();
  }

  const authHeaders = () => (token ? { Authorization: `Bearer ${token}` } : {});

  function keyOf(img) {
    if (!img) return null;
    if (img.file) return `file:${img.file}`;
    if (img.data) return `data:${img.id}`;
    if (img.url) return `url:${img.url}`;
    return null;
  }

  function load(img) {
    const key = keyOf(img);
    if (!key) return Promise.reject(new Error('No image'));
    if (!cache.has(key)) {
      const entry = (async () => {
        let blob;
        if (img.file) {
          blob = await fetchBlob(`/api/images/get?id=${encodeURIComponent(img.file)}`, { headers: authHeaders() });
        } else if (img.data) {
          blob = await fetchBlob(img.data);
        } else {
          blob = await fetchBlob(img.url);
        }
        return { blob, url: URL.createObjectURL(blob) };
      })();
      cache.set(key, entry);
      // A failure isn't kept, so the next draw tries again.
      entry.catch(() => { if (cache.get(key) === entry) cache.delete(key); });
    }
    return cache.get(key);
  }

  // Puts the image into an <img> once it has loaded.
  function show(el, img) {
    if (!el) return;
    load(img).then(
      ({ url }) => { el.src = url; },
      () => {
        el.alt = 'Image unavailable';
        el.classList.add('img-missing');
      }
    );
  }

  const blob = (img) => load(img).then((r) => r.blob);

  function blobToDataUrl(b) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(b);
    });
  }

  // As a data URL, for an export file or another device (js/sync.js).
  const dataUrl = (img) => (img?.data ? Promise.resolve(img.data) : blob(img).then(blobToDataUrl));

  // Saves bytes under a name of our choosing. The blob: URL is same-origin, so `download` is
  // honoured, and it's released a while after, since some browsers start after click() returns.
  function save(b, filename) {
    const url = URL.createObjectURL(b);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  }

  // The signed-in user's avatar. `fresh` after changing it, so the old one isn't reused.
  function avatar({ fresh = false } = {}) {
    if (fresh && avatarEntry) {
      avatarEntry.then((r) => URL.revokeObjectURL(r.url), () => {});
      avatarEntry = null;
    }
    if (!avatarEntry) {
      const entry = fetchBlob('/api/auth/avatar', { headers: authHeaders(), cache: 'no-cache' })
        .then((b) => ({ blob: b, url: URL.createObjectURL(b) }));
      avatarEntry = entry;
      entry.catch(() => { if (avatarEntry === entry) avatarEntry = null; });
    }
    return avatarEntry.then((r) => r.url);
  }

  function setToken(value) {
    token = value || null;
  }

  // Signing out: every URL this session made goes, so nothing of one account is left for the next.
  function clear() {
    for (const entry of cache.values()) entry.then((r) => URL.revokeObjectURL(r.url), () => {});
    cache.clear();
    avatarEntry?.then((r) => URL.revokeObjectURL(r.url), () => {});
    avatarEntry = null;
    token = null;
  }

  window.ImageStore = { show, blob, dataUrl, blobToDataUrl, save, avatar, setToken, clear, url: (img) => load(img).then((r) => r.url) };
})();
