// GET /api/app-release: the newest release of the Android app (flutter/), for its update bar and
// its Updates page (docs/flutter-android-app-spec.md §8), read from GitHub Releases
// (api/lib/releases.js) and cached at Vercel's edge, so GitHub sees a request every few minutes
// however many phones ask.
//
//   { version: "1.0.0", apk: "https://github.com/.../uwuboard-1.0.0.apk", size: 12345678,
//     sha256: "ab12…" (GitHub's checksum of the file, or null), page: the release's page,
//     date, notes: the release's notes, history: every release, this one first, each
//     { version, date, notes, page }, for the Updates page }
//   or { version: null, history: [] } while there's no release with an APK.
//
// ?v=<anything> is ignored, but makes a URL the cache hasn't seen: the Updates page asks with it,
// for a release published a moment ago.

const { allReleases } = require('./lib/releases');

module.exports = async (request, response) => {
  if (request.method !== 'GET') {
    return response.status(405).json({ error: 'Method not allowed' });
  }
  let releases;
  try {
    releases = await allReleases();
  } catch (error) {
    console.error('app-release:', error.message);
    return response.status(502).json({ error: "Couldn't reach GitHub" });
  }
  const history = releases.map(({ version, date, notes, page }) => {
    return { version, date, notes, page };
  });
  response.setHeader('Cache-Control', 'public, s-maxage=600, stale-while-revalidate=3600');
  // The app's browser build (its Playwright suite) asks from another origin.
  response.setHeader('Access-Control-Allow-Origin', '*');
  let answer;
  if (releases[0]) {
    answer = { ...releases[0], history };
  } else {
    answer = { version: null, history };
  }
  return response.status(200).json(answer);
};
