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
    const response = await fetch(url, options);
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }
    return response.blob();
  }

  const authHeaders = () => {
    if (token) {
      return { Authorization: `Bearer ${token}` };
    }
    return {};
  };

  // The key an image is cached under: its storage name, its id (guest data URL) or its old URL.
  function keyOf(image) {
    if (!image) {
      return null;
    }
    if (image.file) {
      return `file:${image.file}`;
    }
    if (image.data) {
      return `data:${image.id}`;
    }
    if (image.url) {
      return `url:${image.url}`;
    }
    return null;
  }

  // Fetches an image's bytes once and keeps the promise of { blob, url } for next time.
  function load(image) {
    const key = keyOf(image);
    if (!key) {
      return Promise.reject(new Error('No image'));
    }
    if (!cache.has(key)) {
      const entry = (async () => {
        let blob;
        if (image.file) {
          blob = await fetchBlob(`/api/images/get?id=${encodeURIComponent(image.file)}`, { headers: authHeaders() });
        } else if (image.data) {
          blob = await fetchBlob(image.data);
        } else {
          blob = await fetchBlob(image.url);
        }
        return { blob, url: URL.createObjectURL(blob) };
      })();
      cache.set(key, entry);
      // A failure isn't kept, so the next draw tries again.
      entry.catch(() => {
        if (cache.get(key) === entry) {
          cache.delete(key);
        }
      });
    }
    return cache.get(key);
  }

  // Puts the image into an <img> once it has loaded.
  function show(element, image) {
    if (!element) {
      return;
    }
    load(image).then(
      ({ url }) => { element.src = url; },
      () => {
        element.alt = 'Image unavailable';
        element.classList.add('img-missing');
      }
    );
  }

  const blob = (image) => {
    return load(image).then((loaded) => {
      return loaded.blob;
    });
  };

  function blobToDataUrl(imageBlob) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => {
        return resolve(reader.result);
      };
      reader.onerror = () => {
        return reject(reader.error);
      };
      reader.readAsDataURL(imageBlob);
    });
  }

  // As a data URL, for an export file or another device (js/sync.js).
  const dataUrl = (image) => {
    let hasData = false;
    if (image !== null && image !== undefined && image.data) {
      hasData = true;
    }
    if (hasData) {
      return Promise.resolve(image.data);
    }
    return blob(image).then(blobToDataUrl);
  };

  // Saves bytes under a name of our choosing. The blob: URL is same-origin, so `download` is
  // honoured, and it's released a while after, since some browsers start after click() returns.
  function save(fileBlob, filename) {
    const url = URL.createObjectURL(fileBlob);
    const link = document.createElement('a');
    link.href = url;
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => {
      return URL.revokeObjectURL(url);
    }, 10000);
  }

  // The signed-in user's avatar. `fresh` after changing it, so the old one isn't reused.
  function avatar({ fresh = false } = {}) {
    if (fresh && avatarEntry) {
      avatarEntry.then((loaded) => {
        return URL.revokeObjectURL(loaded.url);
      }, () => {});
      avatarEntry = null;
    }
    if (!avatarEntry) {
      const entry = fetchBlob('/api/auth/avatar', { headers: authHeaders(), cache: 'no-cache' })
        .then((avatarBlob) => {
          return { blob: avatarBlob, url: URL.createObjectURL(avatarBlob) };
        });
      avatarEntry = entry;
      entry.catch(() => {
        if (avatarEntry === entry) {
          avatarEntry = null;
        }
      });
    }
    return avatarEntry.then((loaded) => {
      return loaded.url;
    });
  }

  function setToken(value) {
    if (!value) {
      token = null;
    } else {
      token = value;
    }
  }

  // Signing out: every URL this session made goes, so nothing of one account is left for the next.
  function clear() {
    for (const entry of cache.values()) {
      entry.then((loaded) => {
        return URL.revokeObjectURL(loaded.url);
      }, () => {});
    }
    cache.clear();
    if (avatarEntry !== null && avatarEntry !== undefined) {
      avatarEntry.then((loaded) => {
        return URL.revokeObjectURL(loaded.url);
      }, () => {});
    }
    avatarEntry = null;
    token = null;
  }

  window.ImageStore = {
    show,
    blob,
    dataUrl,
    blobToDataUrl,
    save,
    avatar,
    setToken,
    clear,
    url: (image) => {
      return load(image).then((loaded) => {
        return loaded.url;
      });
    },
  };
})();
