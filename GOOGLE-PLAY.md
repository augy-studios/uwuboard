# Putting uwuBoard on Google Play

A step-by-step guide to publishing the Android app on Google Play, for the repo as it stands at
1.0.0 (14 November 2026). Google changes its Play rules often: each rule below says where it
comes from, so re-check that page if this date is far behind you.

**What's done in the repo already:** the Play build (`flutter\build-apk.ps1 -Aab`) makes a signed,
shrunk and obfuscated App Bundle with no updater of its own, and checks it; the release notes and
store graphics are written and drawn (`announcements/`, `docs/*-assets/`). **What's left is yours:**
the account, the decisions in section 3, and the clicks in Play Console.

## Contents

1. [The short version](#1-the-short-version)
2. [What the Play build is](#2-what-the-play-build-is)
3. [Decisions to make](#3-decisions-to-make)
4. [Step 1: Build the App Bundle](#4-step-1-build-the-app-bundle)
5. [Step 2: Developer account](#5-step-2-developer-account)
6. [Step 3: Create the app](#6-step-3-create-the-app)
7. [Step 4: Store listing](#7-step-4-store-listing)
8. [Step 5: App content (the Dashboard tasks)](#8-step-5-app-content-the-dashboard-tasks)
9. [Step 6: Data safety](#9-step-6-data-safety)
10. [Step 7: Testing tracks, then production](#10-step-7-testing-tracks-then-production)
11. [After launch](#11-after-launch)
12. [Checklist](#12-checklist)

---

## 1. The short version

- Google Play takes an **Android App Bundle** (`uwuboard-<version>.aab`), not the APK on GitHub.
  `release/1.0.0/uwuboard-1.0.0.aab` is ready.
- It's the same app as the GitHub APK, with the same package (`org.uwuapps.board`) and signing
  key, minus the self-updater, which Play forbids: Play updates it instead.
- The bundle is shrunk and obfuscated as Play recommends (R8 for the Java, Dart obfuscation,
  unused resources removed), and carries R8's mapping and the native symbol tables, so Play
  Console's crash reports and "deobfuscation" warnings are covered.
- Play App Signing is required. Give Play **your existing key** (section 3, D1) and installs from
  GitHub and from Play update each other.
- A new personal developer account must run a **closed test with 12 testers for 14 days** before
  it can publish to everyone. Plan on about three weeks.

## 2. What the Play build is

| | GitHub APK | Play App Bundle |
|---|---|---|
| Built with | `build-apk.ps1` | `build-apk.ps1 -Aab` |
| Updater | Updates page, update bar, downloads and installs the APK | None: Play updates it. The Updates page still lists every version, with **Update on Google Play** |
| `REQUEST_INSTALL_PACKAGES` | Yes | Removed (`android/app/src/play/AndroidManifest.xml`), and the script checks it's gone |
| "New versions of the app" notifications | Yes, with Firebase | Yes, with Firebase (optional on Play: Play notifies too) |
| Processors | ARM 32 and 64 bit in one APK | Play delivers each phone only what it needs |
| Signed with | `android.keystore` | The same, as the upload key; Play re-signs with the app signing key (D1) |

The app asks for only these permissions: **Internet**; **post notifications** (Android 13+, asked
only when "New versions of the app" is turned on); **write to storage** on Android 9 and older
only (saving a board export to Downloads). Nothing that needs a Play declaration form.

Target SDK: Flutter 3.47's default (36), which Play requires for new apps from 31 August 2026.

## 3. Decisions to make

| | Decision | Recommended |
|---|---|---|
| D1 | **Which key Play signs with.** Your existing key, uploaded once to Play App Signing, keeps the GitHub APK and the Play app able to update each other, and keeps `main-site/.well-known/assetlinks.json` as it is. A key Play makes means a Play install can't update a GitHub install (and the other way round): people would uninstall first, and lose guest boards they hadn't synced. | Your existing key |
| D2 | **Personal or organisation account.** Personal is quicker, but has the 12-tester rule. Organisation needs a registered business (a D-U-N-S number). | Personal |
| D3 | **Countries.** uwuBoard isn't tied to a place. | Every country |
| D4 | **Privacy policy URL.** Play requires one, and the site has none yet. A short page at `https://board.uwuapps.org/privacy` saying what section 9 says is enough. | Write one before step 5 |

## 4. Step 1: Build the App Bundle

In PowerShell, from the project root, with `android.keystore` and `keystore.properties` in
`flutter\` (they're not in git: restore them from your backup):

```powershell
powershell -ExecutionPolicy Bypass -File flutter\build-apk.ps1 -Aab
```

It writes `release\<version>\uwuboard-<version>.aab`, and refuses to finish unless the bundle:

- is signed with the app's key (SHA-256 `4C:C9:9A:E0:91:90:2F:AC:71:FE:E6:E7:3B:5C:75:2D:E6:F6:FE:C3:CB:51:C8:02:2E:D4:FA:01:76:97:A3:00`);
- has no `REQUEST_INSTALL_PACKAGES` in its manifest;
- carries `BUNDLE-METADATA/com.android.tools.build.obfuscation/proguard.map` (R8's mapping, which
  Play reads for crash reports) and the stripped symbol tables of `libflutter.so` and `libapp.so`.

Beside it, `uwuboard-<version>-play-mapping.txt` and `-play-symbols.zip` stay on your computer
(git-ignored): with them, `flutter symbolize` reads an obfuscated Dart stack trace from Play's
crash reports.

Every upload needs a higher `versionCode` than any before it. `build-apk.ps1` raises it by itself
on every run (the `+N` in `flutter\pubspec.yaml`), so a fresh build is always uploadable; commit
`pubspec.yaml` with it.

## 5. Step 2: Developer account

1. Sign in to the Google account that will own the app, with 2-Step Verification on.
2. Register at <https://play.google.com/console/signup>: **US$25, once**, by a card in the
   account holder's name. You must be 18 or older and accept the Developer Distribution
   Agreement; Google may ask for government ID ([registration](https://support.google.com/googleplay/android-developer/answer/6112435)).
3. Choose **personal** (D2), and complete **identity verification**. Allow a few days, and don't
   create the app until it's done. Personal accounts also confirm an Android device through the
   Play Console app.
4. **Developer verification**: creating the app in Play Console registers the package name
   `org.uwuapps.board` to your account ([developer verification](https://developer.android.com/developer-verification)).
   Check Play Console's Home page afterwards shows it registered: it covers the GitHub APK too,
   as both use the same package and key.

## 6. Step 3: Create the app

1. **Create app**: name `uwuBoard`, default language **English (United Kingdom)** (`en-GB`), as the app and its notes are written, **App**,
   **Free**, your contact email. Accept the declarations.
2. **Test and release** > **Setup** > **App signing** (or when you create the first release):
   choose **Use a different key** > **Export and upload a key from Java keystore**, and follow
   Play's steps with its PEPK tool and `flutter\android.keystore` (D1). Use the same key as the
   **upload key** too. Afterwards, the page shows the **app signing key certificate**: its SHA-256
   should be the one in section 4. If it differs (you let Play make a key), add Play's SHA-256 to
   `main-site/.well-known/assetlinks.json` beside the existing one, so board links still open the
   app ([Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756)).
3. The package name comes from the first bundle you upload. **It's permanent.**

## 7. Step 4: Store listing

**Grow users** > **Store presence** > **Main store listing**
([asset specs](https://support.google.com/googleplay/android-developer/answer/9866151)):

| Field | Limit | uwuBoard |
|---|---|---|
| App name | 30 | `uwuBoard` |
| Short description | 80 | `The Kanban way: drag your tasks from To Do to Done, or lay them out on a Timeline` (79) |
| Full description | 4,000 | Below |
| App icon | 512 × 512 PNG | `main-site/uwuboard-512.png` |
| Feature graphic | 1024 × 500, no alpha | `docs/feature-graphic.png` |
| Phone screenshots | 2 to 8 | `docs/phone-assets/01…08` (1620 × 2880) |
| 7-inch tablet screenshots | up to 8 | `docs/tablet-assets/7-inch/01…08` (1620 × 2880) |
| 10-inch tablet screenshots | up to 8 | `docs/tablet-assets/10-inch/01…08` (2880 × 1620) |
| Chromebook screenshots | up to 8 | `docs/desktop-assets/01…08` (2880 × 1620) |
| Category | one | **Productivity** |
| Tags | up to 5 | Task management, To-do list, Project management, Productivity, Planner (whichever of these Play offers) |
| Contact | email, website | Your email; `https://board.uwuapps.org` |

Upload the screenshots in their numbered order: the first three show in search results.

Full description:

```text
uwuBoard turns your to-do list into a clear board where you drag tasks from To Do to Done.

KANBAN BOARDS
Make as many boards as you like. Add columns, rename and reorder them, and drag cards from one to the next as the work moves along.

TIMELINES
Any board can be a Timeline, a Gantt chart of the same cards: columns become phases and cards become bars from their start to their due date. Drag a bar to move it or an end to change how long it takes, mark milestones, and see what waits for what, with the arrow turning red when the dates clash. Zoom by weeks, months or quarters.

CARDS WITH EVERYTHING
Each card has a description, a due date, a priority, colour labels, a checklist and images. The card shows how far its checklist is done, and turns red when it's overdue.

YOUR LOOK
Material You by default: your phone's font and, on Android 12 and later, your wallpaper's colours. Prefer uwuBoard's own look? Switch to the UwU Apps theme for its brand colours. Light, dark, or time-based.

GUEST OR ACCOUNT
Use it as a guest, with everything kept on your phone, or sign up and your boards follow you to the website and any device.

SYNC WITHOUT AN ACCOUNT
Copy boards straight to another phone or computer on the same wifi with a code or QR code. Copying adds and updates, and never deletes.

ALSO
Export a board to a file and import it anywhere, step-by-step tours the first time you open each part, and the edge tray for every action in reach.

uwuBoard is also on the web at board.uwuapps.org, and for Windows, macOS and Linux.
```

## 8. Step 5: App content (the Dashboard tasks)

**Policy and programmes** > **App content**
([prepare your app for review](https://support.google.com/googleplay/android-developer/answer/9859455)):

| Task | Answer |
|---|---|
| Privacy policy | Your URL (D4) |
| Ads | **No ads** |
| App access | **All functionality is available without special access**: guest mode needs no account. (If reviewers ask for an account, give them a test username and password in the instructions.) |
| Content rating | Fill the questionnaire: a productivity tool, no violence, no gambling, no shared public content. Users can't talk to each other in the app; Sync copies one's own boards between one's own devices |
| Target audience | 13 and over; not designed for children |
| News app | No |
| Government app | No |
| Financial features | None |
| Health | No |
| Advertising ID | **No**: the app has no ads or analytics SDK and doesn't use it |
| Account deletion | Required because the app lets people sign up. In the app: sidebar > the avatar > **Profile** > **Delete Account**. On the web: `https://board.uwuapps.org`, sign in, the avatar > **Delete Account** |

## 9. Step 6: Data safety

**App content** > **Data safety**
([form help](https://support.google.com/googleplay/android-developer/answer/10787469)). Data is
"collected" when it leaves the phone; data used only on the phone isn't. As a guest, nothing
leaves the phone except what Sync sends to your own other device.

| Data type | What happens | Declare |
|---|---|---|
| Name (username, display name) | Sent to uwuBoard's server when you register or sign in | Collected, **optional** (guest mode needs none), App functionality, Account management |
| Email address | Sent when you register | Collected, optional, Account management |
| Photos | Card images and the avatar, uploaded to your account's private storage when signed in | Collected, optional, App functionality |
| Other user-generated content | Your boards, columns and cards, stored on the server when signed in | Collected, optional, App functionality |
| Device or other IDs | Only with "New versions of the app" on: Firebase subscribes the phone to a topic, through Google's servers; uwuBoard's server keeps no ID | Collected, optional, App functionality (Firebase Cloud Messaging) |
| IP address | Sync's free introduction service (PeerJS) sees both devices' IP addresses while it connects them | Disclose under the privacy policy; the boards themselves go straight from device to device |
| Location, contacts, calendar, messages, health, financial info, web history | Not used | Not collected |

Other answers:

- **Encrypted in transit**: **Yes** (HTTPS for the API, DTLS for Sync's WebRTC channel).
- **Can people ask for data to be deleted?** **Yes**: Delete Account removes the account, its
  boards and images (section 8).
- **Shared with third parties?** No: Supabase (the database), Vercel (the server) and Firebase are
  service providers working for uwuBoard, which Play doesn't count as sharing.
- Check the SDKs' own notes in the [Play SDK Index](https://play.google.com/sdks): Firebase
  Messaging, flutter_webrtc.

## 10. Step 7: Testing tracks, then production

1. **Internal testing**: **Test and release** > **Testing** > **Internal testing** > **Create new
   release**, upload `uwuboard-1.0.0.aab`, paste the release notes from
   `announcements/play-release-notes-1.0.0.md`, and add yourself and a few testers by email. No
   review in the usual case. Use it to check:
   - a phone with the **GitHub APK 1.0.0** installed takes the Play version as an update, boards
     kept (only with D1's existing key; Play needs a higher `versionCode`, so test with 1.0.1);
   - the Updates page shows **Update on Google Play**, and there's no update bar.
2. **Closed testing**, for a new personal account
   ([testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)):
   a closed track with **at least 12 testers opted in for 14 days in a row**. Invite 15 or so (the
   UwU Apps Telegram channel is a good place), so a few dropping out doesn't restart the clock.
3. **Apply for production** from the Dashboard once that's met, and answer its three sections.
   Google usually replies within seven days.
4. **Production**: create the release (the same bundle, or a newer one), the release notes, the
   countries (D3), and **Start rollout**. The first review can take a few days.

## 11. After launch

- **Every update**: raise the version name, `build-apk.ps1 -Aab` (the code goes up by itself), upload to a track,
  paste `announcements/play-release-notes-<version>.md`, roll out. The GitHub release goes on as
  before with the APK (`release/README.md`).
- **Point people to Play**: add the Play link to the site and the GitHub release notes once it's
  live.
- **Target API each year**: Play raises the required target SDK every August. Upgrading Flutter
  raises it; check `targetSdk` in the built bundle's manifest
  ([target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)).
- **Crashes**: Play Console > **Quality** > **Android vitals**. Java stack traces are readable
  thanks to the mapping in the bundle; for Dart ones, `flutter symbolize -i <trace> -d
  <unzipped -play-symbols.zip>`.

## 12. Checklist

- [ ] D1–D4 decided; privacy policy page live
- [ ] `android.keystore` and `keystore.properties` backed up somewhere safe
- [ ] `uwuboard-<version>.aab` built with `-Aab`, its checks passed
- [ ] Developer account registered and verified
- [ ] App created; App Signing set up with the existing key; its SHA-256 matches section 4
- [ ] Store listing: text, icon, feature graphic, phone, tablet and Chromebook screenshots
- [ ] App content tasks answered; Data safety filled
- [ ] Internal test installed and checked
- [ ] Closed test: 12+ testers, 14 days; production applied for and approved
- [ ] Production rolled out; the site links to Play
