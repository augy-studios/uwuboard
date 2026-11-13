# uwuBoard's apps

Android, Windows, macOS and Linux from one Flutter project, with the same features, words, stored
data and API as the website in `../main-site/`, which stays the specification
(`docs/flutter-android-app-spec.md`, `docs/flutter-desktop-app-spec.md`,
`docs/desktop-features-spec.md`). `PORTING.md` maps each part of the site to its Dart.

```text
lib/
  main.dart, run.dart     start-up: the store, the bridge (or the desktop's host), the theme,
                          the saved session, then the app
  app/                    the shell: the home screen, sidebar, edge tray, links, files, state
  api/                    the site's /api/*, and whether the network's there
  data/                   storage under the site's keys, boards, images, and the logic ported
                          from the site's JS (timeline_logic, sync_logic)
  features/               auth, board (Kanban), card, timeline, theme, sync, tour, profile, update
  native/bridge.dart      the one way to platform code: Native.call / has / on
  share/                  PeerJS over WebRTC, STUN only, for Sync (the site's js/p2p.js)
  theme/                  Material You and the UwU Apps look; the site's icons
  widgets/                shared widgets, and AppSheet (bottom sheet, dialog or side panel)
  desktop/                Windows, macOS and Linux only: the window, tray, title bar and
                          command bar, updater, welcome and update windows, widgets, glance
android/                  Gradle; the Java in app/src/main/java/org/uwuapps/board/
windows/ macos/ linux/    the desktop runners, each with its small native channel
installers/               NSIS, WiX, .deb/.rpm/AppImage and .dmg, and the update files
test/                     Dart tests, including the site-parity tests (tool/expected.mjs)
e2e/                      the app in a browser, driven by Playwright (its README)
build-apk.ps1             the signed, obfuscated APK and App Bundle, into ../release/<version>/
FIREBASE-SETUP.md         notifications of new versions
```

## The look

Android 12 and later open in **Material You**, the phone's own font and wallpaper colours; the
**UwU Apps** look (the site's brand colours, Jua font and glass panels) is a switch in **Theme**.
Phones without a palette, and the desktop apps, open in the UwU Apps look; on the desktop
**Use system accent colour** borrows the computer's accent instead of the brand colour. The
Updates page is always Material You.

## Build the APK and App Bundle

Needs Flutter (3.47), a JDK 17 or later and the Android SDK, and `android.keystore` with
`keystore.properties` in this folder. Both are kept out of git: **back them up**. An APK signed
with any other key can't update the app people already have, and Google Play needs the same key
for every upload.

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1          # uwuboard-<v>.apk, for GitHub
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab     # uwuboard-<v>.aab, for Play
```

Both are shrunk and obfuscated as Google Play asks: R8 shrinks and renames the Java and removes
unused resources (`android/app/build.gradle.kts`), the Dart is obfuscated with its symbols split
off, and emulator-only libraries are left out. What reads a crash report back stays beside them
in `release/<version>/` and is never shared: `-mapping.txt` (R8) and `-symbols.zip` (Dart, for
`flutter symbolize`). The App Bundle carries R8's mapping and the native symbol tables for Play
itself; the script checks they're there, and that the Play build has no updater.

For a new version, raise `version:` in `pubspec.yaml`, name and code (`1.0.1+2`): a phone only
takes a higher code as an update, and every platform shares the name.

## The desktop apps

Built on GitHub's machines (`.github/workflows/build-desktop.yml`), each on its own system and
processor, when a release is published. To try one here: `flutter run -d windows` (or `macos`,
`linux`). Run from source it skips updating, starting at sign-in and the link scheme; set
`UWUBOARD_SPLASH_DEMO=1` to see the update window's steps.

## Tests

```powershell
cd flutter
flutter analyze
flutter test                 # the Dart tests, with the site-parity ones
node tool/expected.mjs       # the site's answers again, after changing timeline.js or sync.js
cd e2e; npm install; npx playwright install chromium; npm run build; npm test
```
