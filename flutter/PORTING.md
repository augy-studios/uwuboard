# Porting table

Each part of the site (`main-site/`), where it lives in the app, and how it stands. Storage keys,
board JSON and API calls are the site's own throughout; `test/parity_test.dart` checks the keys
and the ported logic against the site's JavaScript.

| Site | App | Status |
|---|---|---|
| `script.js` state, sessions, sign-in, register, guest, sign out | `lib/app/state.dart`, `lib/features/auth/auth_screen.dart` | Done |
| `script.js` boards: create, rename, delete, select, persist | `lib/app/state.dart`, `lib/app/sidebar.dart`, `lib/features/board/column_sheets.dart` | Done |
| `script.js` columns: add, rename, delete, reorder | `lib/features/board/column_sheets.dart`, `kanban_view.dart` | Done |
| `script.js` cards: add inline, drag between columns, details, labels, checklist, images, due, priority | `lib/features/board/kanban_view.dart`, `lib/features/card/card_sheet.dart` | Done. Long press to drag on a phone, as a swipe scrolls |
| `script.js` export and import (board files with images inside) | `lib/app/state.dart`, `lib/features/card/card_sheet.dart`, `lib/app/files.dart` | Done. Android saves into Downloads |
| `script.js` profile, avatar, delete account in three steps | `lib/features/profile/profile_sheet.dart` | Done |
| `js/timeline.js` the Gantt view, drag and resize, keyboard, zoom, dependencies, today | `lib/data/timeline_logic.dart`, `lib/features/timeline/timeline_view.dart` | Done; logic checked against the site |
| `js/theme.js` brand colours, light, dark, time-based | `lib/theme/theme.dart`, `lib/features/theme/theme_sheet.dart` | Done, plus Material You |
| `js/sync.js`, `js/p2p.js`, `js/qr.js` device sync over PeerJS | `lib/data/sync_logic.dart`, `lib/features/sync/`, `lib/share/` | Done; merging checked against the site. Talks to the site in a browser and back |
| `js/images.js` images by bytes, never addresses | `lib/data/images.dart` | Done. New pictures are JPEG or PNG (Dart has no WebP writer); the site and server take both |
| `js/tour.js` first-visit tours, Show me around | `lib/features/tour/tour.dart` | Done |
| `js/tray.js` edge tray, press and hold for a label | `lib/app/edge_tray.dart` | Done |
| `js/bug-report.js` Report a bug, Screenshot a page, sent to Telegram by `api/bug-report.js` | `lib/features/bug/bug_report.dart`, `lib/features/board/whole_board.dart` | Done. Screenshot a page takes the open board whole, or the screen with a window open |
| `js/sw-update.js` update bar | `lib/features/update/update_bar.dart` | Done, as the app's own updater and Updates page (Android), and `lib/desktop/updater.dart` |
| `sw.js` offline | `lib/api/api.dart`, `lib/app/state.dart` (`app.boardsCache`) | Done: the boards as last fetched, and an offline bar |
| `index.html` `#sync/CODE` links | `lib/app/links.dart`, `AndroidManifest.xml` (verified links) | Done |
| `api/app-release.js`, `api/push/release.js` | site additions for the apps | New with 1.0.0 |
