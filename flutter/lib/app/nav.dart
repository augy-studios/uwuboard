// Getting about from anywhere: one navigator key and one messenger key, the toast every
// feature uses (the site's toast()), and the two small windows the site left to the browser
// (confirm() and prompt()).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/theme.dart';
import '../widgets/sheet.dart';

class AppNav {
  AppNav._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Round the whole app, for a picture of it (bug reports, the desktop's screenshot button).
  static final repaintKey = GlobalKey();

  static BuildContext? get context {
    return navigatorKey.currentContext;
  }

  /// The last few toasts, newest last: tests and the desktop's title bar read them.
  static final ValueNotifier<String> lastToast = ValueNotifier('');

  /// Shows a short message at the bottom of the app, replacing any that is showing.
  /// Errors are drawn in the theme's error colour.
  static void toast(String message, {bool error = false}) {
    lastToast.value = message;
    final messenger = messengerKey.currentState;
    final currentContext = context;
    if (messenger == null || currentContext == null) {
      return;
    }
    final colors = UwuColors.of(currentContext);
    messenger.hideCurrentSnackBar();
    Color? textColor;
    Color? backgroundColor;
    if (error) {
      textColor = colors.bg;
      backgroundColor = colors.error;
    } else {
      textColor = null;
      backgroundColor = null;
    }
    double? snackBarWidth;
    if (MediaQuery.sizeOf(currentContext).width > 560) {
      snackBarWidth = 420;
    } else {
      snackBarWidth = null;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: textColor)),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        width: snackBarWidth,
      ),
    );
  }

  /// The site's confirm(): true when agreed to.
  static Future<bool> confirm(String message, {String yes = 'Delete', bool danger = true}) async {
    final currentContext = context;
    if (currentContext == null) {
      return false;
    }
    final agreed = await showDialog<bool>(
      context: currentContext,
      builder: (context) {
        final colors = UwuColors.of(context);
        ButtonStyle? confirmStyle;
        if (danger) {
          confirmStyle = FilledButton.styleFrom(backgroundColor: colors.errorFill, foregroundColor: colors.error);
        } else {
          confirmStyle = null;
        }
        return AlertDialog(
          content: Text(message, style: TextStyle(color: colors.ink, fontSize: 15)),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: confirmStyle,
              onPressed: () {
                Navigator.pop(context, true);
              },
              child: Text(yes),
            ),
          ],
        );
      },
    );
    return agreed == true;
  }

  /// The site's prompt(): the words typed, or null when cancelled or left empty.
  static Future<String?> prompt(String label, {String initial = '', String ok = 'OK'}) async {
    final currentContext = context;
    if (currentContext == null) {
      return null;
    }
    final controller = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: currentContext,
      builder: (context) {
        return AlertDialog(
          title: Text(label, style: const TextStyle(fontSize: 16)),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (typedText) {
              Navigator.pop(context, typedText);
            },
          ),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, controller.text);
              },
              child: Text(ok),
            ),
          ],
        );
      },
    );
    String? trimmed;
    if (value != null) {
      trimmed = value.trim();
    }
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    } else {
      return trimmed;
    }
  }

  /// Closes whatever windows are open over the app (signing out, a link arriving).
  static void closeSheets() {
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.popUntil((route) {
        return route.isFirst;
      });
    }
    AppSheet.closeAll();
  }
}

/// Puts words on the clipboard.
Future<void> copyText(String text) {
  return Clipboard.setData(ClipboardData(text: text));
}
