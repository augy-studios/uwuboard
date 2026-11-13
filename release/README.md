# Releases

The apps built here, each version in a folder of its own, all with the same version number:

```text
release/1.0.0/
  uwuboard-1.0.0.apk                  Android      flutter\build-apk.ps1
  uwuboard-1.0.0.aab                  Google Play  flutter\build-apk.ps1 -Aab (never on a GitHub release)
  uwuboard-1.0.0-mapping.txt          Android      the same, for reading crashes; never shared (git-ignored)
  uwuboard-1.0.0-symbols.zip          Android      the Dart side's symbols, the same; never shared (git-ignored)
  uwuboard-1.0.0-setup.exe            Windows      GitHub Actions: Build desktop apps (x64 and Arm in one)
  uwuboard-1.0.0.msi                  Windows      the same, x64, for installing on many computers
  uwuboard-1.0.0-mac-arm64.dmg/.zip   macOS        the same; the .zip is what the Mac app updates from
  uwuboard-1.0.0-mac-x64.dmg/.zip     macOS        the same, for Intel Macs
  uwuboard-1.0.0-amd64.deb, -arm64.deb, -x86_64.rpm, -aarch64.rpm, -x86_64.AppImage, -aarch64.AppImage
                                      Linux        the same
  latest.yml, latest-mac.yml, latest-linux.yml, latest-linux-arm64.yml
                                      desktop      what the desktop apps read to update themselves
```

The APK and App Bundle are committed with the code they were built from. Any file over GitHub's
100 MB limit is listed by name in `.gitignore` and goes only on the GitHub release, as the
desktop installers do (they're built on GitHub and never kept here).

## Build them

The APK, in PowerShell from the project root (`flutter/README.md` has what it needs):

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab
```

For a new version, raise the version name in `flutter/pubspec.yaml` first (`1.0.0` → `1.0.1`). The version
code after the `+` goes up by itself on every build (`flutter/README.md`): commit `pubspec.yaml` with it.

The desktop ones build on GitHub: publishing the release starts **Build desktop apps**, and a few
minutes later its installers and update files are on the release. To build them before
publishing, run it by hand (**Actions** > **Build desktop apps** > **Run workflow**) with the new
tag, such as `android-v1.0.1`: they land on a draft release of that tag, ready for the APK.

## Put it on GitHub

1. Commit and push, so the release points at the code it was built from.
2. Open <https://github.com/augy-studios/uwuboard/releases/new>.
3. **Choose a tag**: type a new one, `android-v<version>`, and pick **Create new tag on publish**.
   Leave the target as `main`. Keep to `android-v<version>`, even with the desktop installers on
   it: it's how the Android app's updater finds its releases (`main-site/api/lib/releases.js`).
4. **Release title**: `uwuBoard 1.0.0`.
5. **Describe this release**: paste `announcements/release-notes-<version>.md`. The Android app's
   Updates page reads it: the first paragraph as the summary, and under `## What's new` (or
   `What's fixed`) a card for each `###` heading, each `- **Title**: text` line as one change.
   The download table and install steps stay on GitHub.
6. Drag in the APK from `release\<version>\`. Wait for it to finish uploading. (Not the `.aab`,
   the mapping or the symbols.)
7. Tick **Set as the latest release**, then **Publish release**.

`https://github.com/augy-studios/uwuboard/releases/latest` always points at the newest one.

## How phones and computers hear about it

- **Android**: within about 10 minutes of publishing, the app offers the new version in a bar at
  the top and on its Updates page, read from `https://board.uwuapps.org/api/app-release` (cached
  for 10 minutes). It skips drafts, pre-releases, tags that don't start `android-v`, and releases
  whose APK hasn't finished uploading. **Update** downloads the APK, checks GitHub's SHA-256 and
  hands it to Android's installer.
- **Android, at once**: phones with **New versions of the app** on get a notification the moment
  it's published, once Firebase is set up (`flutter/FIREBASE-SETUP.md`). That's why the APK is
  attached **before** **Publish release**: a release without its APK is skipped.
- **Desktop**: the apps read the `latest*.yml` files on the newest release as they open, every
  hour and after the computer wakes, so they hear once GitHub Actions has added the installers.
- **Telegram**: post `announcements/announcement-<version>.md` in the UwU Apps channel.

## Before you share it

- **Deploy the site first**: the updater and the notifications go through its `/api/app-release`
  and `/api/push/release`.
- **The repository has to be public** for others to download from it.
- **Never upload `android.keystore`, `keystore.properties`, the mapping, the symbols or a
  Firebase key.** Only the installers.

## If something goes wrong

| What happens | What to do |
|---|---|
| "App not installed" on the phone | An older copy signed with a different key is installed, such as one from PWABuilder. Uninstall uwuBoard, then install again. |
| "App not installed as package appears to be invalid" | The download didn't finish. Download it again. |
| Windows says "Windows protected your PC" | The installer isn't code-signed. **More info** > **Run anyway**. |
| macOS says the app is damaged | `xattr -cr /Applications/uwuBoard.app` in Terminal, then open it again. |
| You uploaded the wrong file | On the release, **Edit**, delete the file, attach the right one, **Update release**. The app checks GitHub's checksum, so phones won't install a mismatch. |
| No update bar in the Android app | The tag doesn't start `android-v`, the release is a draft or pre-release, or it's been under 10 minutes. `https://board.uwuapps.org/api/app-release` shows what phones see. |
| The desktop installers didn't appear | **Actions** > **Build desktop apps**: open the run for the release and read the failed job. Run it again by hand with the tag. |
