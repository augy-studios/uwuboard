// Bump on every change to anything this worker serves. The browser only sees
// an update when this file changes byte for byte, so a deploy that leaves this
// alone never reaches anyone who already has the site cached.
const VERSION = "v4";
const CACHE = `uwuboard-${VERSION}`;

const ASSETS = [
  "/",
  "/index.html",
  "/style.css",
  "/script.js",
  "/js/icons.js",
  "/js/ui.js",
  "/js/theme.js",
  "/js/sw-update.js",
  "/uwuboard-main.png",
  "/favicon.ico",
  "/manifest.json"
];

// No skipWaiting() here: a new version installs and then waits until somebody
// presses Reload in the update bar (js/sw-update.js).
self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(ASSETS))
  );
});

// No clients.claim() here either, for the same reason.
self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))
      )
    )
  );
});

self.addEventListener("message", (event) => {
  const type = typeof event.data === "string" ? event.data : event.data?.type;

  // The only place either of these is ever called.
  if (type === "skip-waiting") {
    event.waitUntil(self.skipWaiting().then(() => self.clients.claim()));
  }
});

self.addEventListener("fetch", (event) => {
  // Only handle GET requests; skip POST and other methods
  if (event.request.method !== "GET") return;

  // Skip cross-origin requests (ads, analytics, etc.)
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  event.respondWith(
    caches.match(event.request).then((cached) => {
      const fetched = fetch(event.request).then((response) => {
        // Only cache valid same-origin responses
        if (response && response.status === 200 && response.type === "basic") {
          const clone = response.clone();
          caches.open(CACHE).then((cache) => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => cached);
      return cached || fetched;
    })
  );
});
