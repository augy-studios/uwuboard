// The Android app's releases (flutter/) on GitHub, tagged android-v<version> with the APK
// attached (release/README.md). Shared by api/app-release.js, which the app's updater and its
// Updates page read, and api/push/release.js, which tells phones a new one is out.
//
// GITHUB_TOKEN, if set, raises GitHub's limit from 60 lookups an hour; app-release's answer is
// cached at Vercel's edge for ten minutes, so it's rarely needed.

const RELEASES = 'https://api.github.com/repos/augy-studios/uwuboard/releases?per_page=100';
const TAG = /^android-v(\d+(?:\.\d+)*)$/;

// Whether version a comes after version b, number by number: 1.10.0 after 1.9.0. The same as
// newerVersion() in flutter/lib/features/update/update_bar.dart.
function newer(a, b) {
  const x = String(a).split('.').map(Number);
  const y = String(b).split('.').map(Number);
  for (let i = 0; i < Math.max(x.length, y.length); i++) {
    const d = (x[i] || 0) - (y[i] || 0);
    if (d) return d > 0;
  }
  return false;
}

// Markdown as plain lines: no bold, code or link markup; headings and bullets kept, which the
// Updates page draws as such.
function plain(body) {
  return String(body || '')
    .replace(/\r\n/g, '\n')
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .trim();
}

// A release as the app wants it, or null if it isn't one to offer: a draft, a pre-release, a tag
// that isn't android-v*, or one published before its APK finished uploading.
function asRelease(rel) {
  const version = TAG.exec(rel?.tag_name || '')?.[1];
  if (!version || rel.draft || rel.prerelease) return null;
  const assets = rel.assets || [];
  const apk = assets.find((a) => a.name === `uwuboard-${version}.apk`) || assets.find((a) => /\.apk$/i.test(a.name));
  if (!apk || apk.state !== 'uploaded') return null;
  return {
    version,
    apk: apk.browser_download_url,
    size: apk.size,
    sha256: /^sha256:[0-9a-f]{64}$/i.test(apk.digest || '') ? apk.digest.slice(7).toLowerCase() : null,
    page: rel.html_url,
    date: rel.published_at || null,
    notes: plain(rel.body),
  };
}

// Every release worth offering, newest first.
async function allReleases() {
  const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'uwuboard-releases' };
  if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  const r = await fetch(RELEASES, { headers });
  if (!r.ok) throw new Error(`GitHub said ${r.status}`);
  const list = await r.json();
  return (Array.isArray(list) ? list : [])
    .map(asRelease)
    .filter(Boolean)
    .sort((a, b) => (newer(a.version, b.version) ? -1 : newer(b.version, a.version) ? 1 : 0));
}

async function latestRelease() {
  return (await allReleases())[0] || null;
}

module.exports = { TAG, newer, asRelease, allReleases, latestRelease };
