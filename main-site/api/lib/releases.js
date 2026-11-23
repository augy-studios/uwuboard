// The Android app's releases (flutter/) on GitHub, tagged android-v<version> with the APK
// attached (release/README.md). Shared by api/app-release.js, which the app's updater and its
// Updates page read, and api/push/release.js, which tells phones a new one is out.
//
// GITHUB_TOKEN, if set, raises GitHub's limit from 60 lookups an hour; app-release's answer is
// cached at Vercel's edge for ten minutes, so it's rarely needed.

const RELEASES = 'https://api.github.com/repos/augy-studios/uwuboard/releases?per_page=100';
const TAG = /^android-v(\d+(?:\.\d+)*)$/;

// Whether version `version` comes after version `otherVersion`, number by number: 1.10.0 after
// 1.9.0. The same as newerVersion() in flutter/lib/features/update/update_bar.dart.
function newer(version, otherVersion) {
  const versionNumbers = String(version).split('.').map(Number);
  const otherNumbers = String(otherVersion).split('.').map(Number);
  for (let index = 0; index < Math.max(versionNumbers.length, otherNumbers.length); index = index + 1) {
    // A missing (or unreadable) number counts as 0, so 1.2 is the same as 1.2.0.
    let versionNumber = versionNumbers[index];
    if (!versionNumber) {
      versionNumber = 0;
    }
    let otherNumber = otherNumbers[index];
    if (!otherNumber) {
      otherNumber = 0;
    }
    const difference = versionNumber - otherNumber;
    if (difference) {
      return difference > 0;
    }
  }
  return false;
}

// Markdown as plain lines: no bold, code or link markup; headings and bullets kept, which the
// Updates page draws as such.
function plain(body) {
  let text = body;
  if (!text) {
    text = '';
  }
  return String(text)
    .replace(/\r\n/g, '\n')
    .replace(/\*\*(.+?)\*\*/g, '$1')
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .trim();
}

// A release as the app wants it, or null if it isn't one to offer: a draft, a pre-release, a tag
// that isn't android-v*, or one published before its APK finished uploading.
function asRelease(release) {
  let tagName;
  if (release !== null && release !== undefined) {
    tagName = release.tag_name;
  }
  if (!tagName) {
    tagName = '';
  }
  const tagMatch = TAG.exec(tagName);
  let version;
  if (tagMatch !== null && tagMatch !== undefined) {
    version = tagMatch[1];
  }
  if (!version || release.draft || release.prerelease) {
    return null;
  }
  let assets = release.assets;
  if (!assets) {
    assets = [];
  }
  // The APK named for this version, else any APK attached.
  let apk = assets.find((asset) => {
    return asset.name === `uwuboard-${version}.apk`;
  });
  if (!apk) {
    apk = assets.find((asset) => {
      return /\.apk$/i.test(asset.name);
    });
  }
  if (!apk || apk.state !== 'uploaded') {
    return null;
  }
  // GitHub gives the file's checksum as "sha256:<hex>"; only the hex part is passed on.
  let digest = apk.digest;
  if (!digest) {
    digest = '';
  }
  let sha256;
  if (/^sha256:[0-9a-f]{64}$/i.test(digest)) {
    sha256 = apk.digest.slice(7).toLowerCase();
  } else {
    sha256 = null;
  }
  let date = release.published_at;
  if (!date) {
    date = null;
  }
  return {
    version,
    apk: apk.browser_download_url,
    size: apk.size,
    sha256: sha256,
    page: release.html_url,
    date: date,
    notes: plain(release.body),
  };
}

// Every release worth offering, newest first.
async function allReleases() {
  const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'uwuboard-releases' };
  if (process.env.GITHUB_TOKEN) {
    headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
  }
  const response = await fetch(RELEASES, { headers });
  if (!response.ok) {
    throw new Error(`GitHub said ${response.status}`);
  }
  const list = await response.json();
  let releases;
  if (Array.isArray(list)) {
    releases = list;
  } else {
    releases = [];
  }
  return releases
    .map(asRelease)
    .filter(Boolean)
    .sort((first, second) => {
      if (newer(first.version, second.version)) {
        return -1;
      } else if (newer(second.version, first.version)) {
        return 1;
      } else {
        return 0;
      }
    });
}

// The newest release worth offering, or null when there is none.
async function latestRelease() {
  const newest = (await allReleases())[0];
  if (!newest) {
    return null;
  }
  return newest;
}

module.exports = { TAG, newer, asRelease, allReleases, latestRelease };
