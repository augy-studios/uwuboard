// Bump on every change to anything this worker serves. The browser only sees
// an update when this file changes byte for byte, so a deploy that leaves this
// alone never reaches anyone who already has the site cached.
const VERSION = "v7";
const CACHE = `uwuboard-${VERSION}`;
// The last answer from each API route, for opening the app offline. Versioned
// too, so copies from before a deploy (which may carry what it removed, such as
// image addresses) go with it.
const API_CACHE = `uwuboard-api-${VERSION}`;

const ASSETS = [
  "/",
  "/index.html",
  "/style.css",
  "/script.js",
  "/js/icons.js",
  "/js/ui.js",
  "/js/theme.js",
  "/js/images.js",
  "/js/tray.js",
  "/js/qr.js",
  "/js/p2p.js",
  "/js/sync.js",
  "/js/tour.js",
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
        keys.filter((key) => key !== CACHE && key !== API_CACHE).map((key) => caches.delete(key))
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

  // Signing out: the API copies are keyed by URL alone, so the next person to
  // sign in on this device must not be handed them.
  if (type === "clear-api-cache") {
    event.waitUntil(caches.delete(API_CACHE));
  }
});

// Image bytes are left to the browser's own cache, which honours their
// `Cache-Control: private` and keys nothing across accounts the way a URL-only
// cache here would (docs/hide-images-spec.md).
const UNCACHED_API = ["/api/images/get", "/api/auth/avatar"];

self.addEventListener("fetch", (event) => {
  // Only handle GET requests; skip POST and other methods
  if (event.request.method !== "GET") return;

  // Skip cross-origin requests (ads, analytics, PeerJS and its broker, etc.)
  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  if (url.pathname.startsWith("/api/")) {
    if (UNCACHED_API.includes(url.pathname)) return;
    // Network first: the boards as they are now, and the last copy only when
    // there's no network. Only an ok answer is kept, so a 401 never sticks.
    event.respondWith(
      fetch(event.request).then((response) => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(API_CACHE).then((cache) => cache.put(event.request, clone));
        }
        return response;
      }).catch(() => caches.open(API_CACHE).then((cache) => cache.match(event.request)).then((cached) => cached || Response.error()))
    );
    return;
  }

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
