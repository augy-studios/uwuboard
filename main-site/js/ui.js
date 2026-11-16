'use strict';

/* Safe to call repeatedly; re-renders when data-icon changes. */
function hydrateIcons(root = document) {
  root.querySelectorAll('[data-icon]').forEach((element) => {
    const name = element.dataset.icon;
    if (element.dataset.iconRendered === name) {
      return;
    }
    element.innerHTML = icon(name);
    element.dataset.iconRendered = name;
  });
}

function openModal(id) {
  document.getElementById(id).classList.remove('hidden');
  document.body.classList.add('modal-open');
}

function closeModal(id) {
  document.getElementById(id).classList.add('hidden');
  if (!document.querySelector('.modal-backdrop:not(.hidden)')) {
    document.body.classList.remove('modal-open');
  }
}

window.hydrateIcons = hydrateIcons;
window.openModal = openModal;
window.closeModal = closeModal;
