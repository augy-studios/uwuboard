'use strict';

/* Service worker registration and the update bar. The one place the site
   registers its worker. A new worker installs and waits; it only takes over
   when somebody presses Reload here. See update-bar-spec.md. */
(function () {
  const SW_URL = '/sw.js';

  // One language, so the copy lives here rather than in a dictionary.
  const COPY = {
    label: 'Update',
    ready: 'A new version of uwuBoard is ready.',
    reload: 'Reload',
    later: 'Not now',
  };

  let registration = null;
  let waitingWorker = null;
  let reloading = false;
  // This page view only. Never stored: "Not now" means not now.
  let dismissed = false;

  function render() {
    const existing = document.querySelector('.update-notice');

    if (!waitingWorker || dismissed) {
      existing?.remove();
      return;
    }

    const bar = existing ?? document.createElement('div');
    bar.className = 'update-notice';
    bar.setAttribute('role', 'status');
    bar.setAttribute('aria-label', COPY.label);
    bar.innerHTML = `
      <div class="update-notice-inner">
        <p>${COPY.ready}</p>
        <button type="button" class="btn-primary" data-sw-update>${COPY.reload}</button>
        <button type="button" class="btn-ghost small" data-sw-later>${COPY.later}</button>
      </div>
    `;

    bar.querySelector('[data-sw-update]').addEventListener('click', () => {
      // The only place anything asks for skipWaiting. The reload happens on
      // controllerchange, not here.
      waitingWorker?.postMessage('skip-waiting');
    });

    bar.querySelector('[data-sw-later]').addEventListener('click', () => {
      dismissed = true;
      render();
    });

    if (!existing) document.body.prepend(bar);
  }

  function watchForUpdate() {
    if (!registration) return;

    // A worker already waiting when the page opened: the ordinary case on the
    // first visit after a deploy.
    if (registration.waiting && navigator.serviceWorker.controller) {
      waitingWorker = registration.waiting;
      render();
    }

    registration.addEventListener('updatefound', () => {
      const installing = registration.installing;
      if (!installing) return;

      installing.addEventListener('statechange', () => {
        // `installed` with no controller is a first install, which has no
        // previous version on screen to prompt about.
        if (installing.state === 'installed' && navigator.serviceWorker.controller) {
          waitingWorker = registration.waiting ?? installing;
          render();
        }
      });
    });
  }

  function registerWorker() {
    navigator.serviceWorker
      .register(SW_URL)
      .then((reg) => {
        registration = reg;
        watchForUpdate();
      })
      .catch((cause) => {
        // Private browsing in some browsers, and any non-localhost http
        // origin, land here. Not a reason to break the page.
        console.warn('service worker registration failed:', cause);
      });

    // Reload once the new worker controls the page, so the reload is served
    // by it and not by the one being replaced. The flag stops a second
    // controllerchange from starting a reload loop.
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (reloading) return;
      reloading = true;
      window.location.reload();
    });
  }

  if (!('serviceWorker' in navigator)) return;

  // On load, so precaching does not compete with the page's own first fetches.
  if (document.readyState === 'complete') registerWorker();
  else window.addEventListener('load', registerWorker, { once: true });
})();
