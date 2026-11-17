// Every link that opens the app goes through Links.open() (docs/flutter-android-app-spec.md §5):
// the site's own https links (verified with assetlinks.json), the uwu://board/ scheme shared
// with the sibling apps, launcher shortcuts, the desktop's command bar and Jump List.
//
//   https://board.uwuapps.org/#sync/CODE   the Sync window with the code filled in
//   uwu://board/sync/CODE                  the same
//   uwu://board/b/<boardId>                that board
//   uwu://board/new                        the New Board window
//   uwu://board/updates                    the Updates page (Android)
//   uwu://board/  or the site's home        the app as it is
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../features/board/column_sheets.dart';
import '../features/sync/sync_sheet.dart';
import '../features/update/update_bar.dart';
import 'nav.dart';
import 'state.dart';

const appScheme = 'uwu';
const appHost = 'board';

/// What a link asks for.
sealed class LinkTarget {
  const LinkTarget();
}

class LinkHome extends LinkTarget {
  const LinkHome();
}

class LinkSync extends LinkTarget {
  const LinkSync(this.code);
  final String code;
}

class LinkBoard extends LinkTarget {
  const LinkBoard(this.id);
  final String id;
}

class LinkNewBoard extends LinkTarget {
  const LinkNewBoard();
}

/// The Updates page (a "new version is out" notification, tapped).
class LinkUpdates extends LinkTarget {
  const LinkUpdates();
}

/// Somewhere else: opened in the browser.
class LinkOut extends LinkTarget {
  const LinkOut(this.uri);
  final Uri uri;
}

final _plainPath = RegExp(r'^[A-Za-z0-9/_\-.]*$');
final _syncHash = RegExp(r'^sync/([A-Za-z0-9-]{1,20})$');

/// Reads a link, or null if it's nothing the app can open. Only plain path characters are
/// taken from the app's own scheme.
LinkTarget? parseLink(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  // A path or hash typed into the desktop's command bar.
  if (text.startsWith('#') || text.startsWith('/#')) {
    return parseLink('$siteOrigin/${text.replaceFirst(RegExp(r'^/'), '')}');
  }
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme) {
    return null;
  }
  // The app's own scheme: uwu://board/...
  if (uri.scheme == appScheme) {
    if (uri.host != appHost) {
      return null;
    }
    final path = uri.path.replaceAll(RegExp(r'^/+|/+$'), '');
    if (!_plainPath.hasMatch(path)) {
      return null;
    }
    final List<String> parts;
    if (path.isEmpty) {
      parts = <String>[];
    } else {
      parts = path.split('/');
    }
    if (parts.isEmpty) {
      return const LinkHome();
    }
    if (parts[0] == 'sync' && parts.length == 2) {
      return LinkSync(parts[1]);
    }
    if (parts[0] == 'b' && parts.length == 2) {
      return LinkBoard(parts[1]);
    }
    if (parts[0] == 'new') {
      return const LinkNewBoard();
    }
    if (parts[0] == 'updates') {
      return const LinkUpdates();
    }
    return const LinkHome();
  }
  // The site's own address: only a sync code in the hash means anything more.
  if ((uri.scheme == 'https' || uri.scheme == 'http') && uri.host == siteHost) {
    final syncMatch = _syncHash.firstMatch(uri.fragment);
    if (syncMatch != null) {
      return LinkSync(syncMatch.group(1)!);
    }
    return const LinkHome();
  }
  if (uri.scheme == 'https' || uri.scheme == 'http' || uri.scheme == 'mailto') {
    return LinkOut(uri);
  }
  return null;
}

/// The app's own link for the board on show, as the desktop's Copy link gives it.
String? linkFor({String? boardId}) {
  if (boardId == null) {
    return 'uwu://board/';
  } else {
    return 'uwu://board/b/$boardId';
  }
}

class Links {
  Links._();

  /// Opens a link. Returns false when it was nothing the app knows.
  static Future<bool> open(String raw) async {
    final target = parseLink(raw);
    if (target == null) {
      return false;
    }
    final currentContext = AppNavigation.context;
    final app = AppState.instance;
    switch (target) {
      case LinkHome():
        return true;
      case LinkOut(:final uri):
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      case LinkSync(:final code):
        if (!app.shown || currentContext == null) {
          // Kept until the app is on screen.
          app.pendingSyncCode = code;
          return true;
        }
        AppNavigation.closeSheets();
        await openSync(currentContext, code: code);
        return true;
      case LinkBoard(:final id):
        if (!app.shown) {
          return false;
        }
        AppNavigation.closeSheets();
        final boardExists = app.boards.any((board) {
          return board['id'] == id;
        });
        if (boardExists) {
          app.selectBoard(id);
        } else {
          AppNavigation.toast('Not found', error: true);
        }
        return true;
      case LinkUpdates():
        await openUpdates();
        return true;
      case LinkNewBoard():
        if (!app.shown || currentContext == null) {
          return false;
        }
        AppNavigation.closeSheets();
        await openNewBoard(currentContext);
        return true;
    }
  }

  /// Once the app is on screen: a sync link that opened it, now usable.
  static void appShown() {
    final code = AppState.instance.pendingSyncCode;
    final currentContext = AppNavigation.context;
    if (code == null || currentContext == null) {
      return;
    }
    AppState.instance.pendingSyncCode = null;
    openSync(currentContext, code: code);
  }
}
