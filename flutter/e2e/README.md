# The app in a browser, driven by Playwright

The real Flutter screens, built for the web from `main_e2e.dart`, with a stand-in for the Android
side and the site's API answered by the tests (`tests/helpers.js`), so they run offline and the
same every time. It's for testing only: the website is still the HTML site in `main-site/`, and
this build never ships.

```powershell
cd flutter\e2e
npm install
npx playwright install chromium
npm run build      # flutter build web, into flutter/build/web
npm test
```

`?android=1` draws as the Android app does (its Updates entry, Material You by default),
`?wallpaper=1` pretends the phone has wallpaper colours, and `?play=1` acts as the Google Play
build. What the app asked of its Android side is in `window.e2eCalls`.

The tests find things as a screen reader would (`getByRole`, by name), so a change that makes a
button nameless, or names it twice, fails here.
