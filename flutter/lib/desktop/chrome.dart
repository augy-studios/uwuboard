// The desktop's own title bar and command bar, round the shared app (docs/desktop-features-spec.md
// §5, docs/flutter-desktop-app-spec.md §2.3–2.5). 40 px tall, in the brand colour (writing light
// or dark by contrast; in native glass, clear, on the window's glass as the system's own title
// bars are), draggable where there's nothing to click, double-click to maximise:
//
//   (macOS traffic lights) Back Forward Reload  [ Command / Search bar ]  Copy link Screenshot
//   Long screenshot (Update) (Windows, Linux: minimise, maximise, close)
//
// The command bar shows the open board's name at rest; Ctrl+K, Ctrl+F, Ctrl+L or F6 (⌘K, ⌘F, ⌘L)
// opens a live search of boards, cards and the app's commands. A pasted uwu://board/ link, the
// site's address or a #sync/… path opens in the app; another site's address opens in the browser.
// Back and Forward step through the boards opened. The title bar hides in full screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app/env.dart';
import '../app/links.dart';
import '../app/nav.dart';
import '../app/state.dart';
import '../data/board.dart';
import '../features/board/column_sheets.dart';
import '../features/bug/bug_report.dart';
import '../features/card/card_sheet.dart';
import '../features/sync/sync_sheet.dart';
import '../features/theme/theme_sheet.dart';
import '../features/tour/tour.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/sheet.dart';
import 'desk.dart';
import 'screenshot.dart';
import 'updater.dart';

const titleBarHeight = 40.0;

/// Back and Forward through the boards opened.
class ViewHistory {
  ViewHistory._();

  /// The boards opened, oldest first, and where in that list the open board is.
  static final List<String> _stack = [];
  static int _position = -1;

  /// True while Back or Forward is opening a board (so that opening isn't added to the list).
  static bool _moving = false;
  static final ValueNotifier<int> changed = ValueNotifier(0);

  /// Starts noting each board opened. Opening a board after going back drops the boards that
  /// were ahead, as a browser does.
  static void start() {
    AppState.I.addListener(() {
      final id = AppState.I.activeBoardId;
      if (_moving || id == null) {
        return;
      }
      if (_position >= 0 && _stack[_position] == id) {
        return;
      }
      _stack.removeRange(_position + 1, _stack.length);
      _stack.add(id);
      _position = _stack.length - 1;
      changed.value = changed.value + 1;
    });
  }

  static bool get canBack {
    return _position > 0;
  }

  static bool get canForward {
    return _position < _stack.length - 1;
  }

  /// Opens the board `steps` places back (negative) or forward (positive), if there is one.
  static void _go(int steps) {
    final target = _position + steps;
    if (target < 0 || target >= _stack.length) {
      return;
    }
    _position = target;
    _moving = true;
    AppState.I.selectBoard(_stack[_position]);
    _moving = false;
    changed.value = changed.value + 1;
  }

  static void back() {
    _go(-1);
  }

  static void forward() {
    _go(1);
  }
}

/// One thing the command bar offers.
class _SearchHit {
  _SearchHit(this.icon, this.title, this.subtitle, this.run);
  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback run;
}

class DesktopChrome extends StatefulWidget {
  const DesktopChrome({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopChrome> createState() {
    return _DesktopChromeState();
  }
}

class _DesktopChromeState extends State<DesktopChrome> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  /// Ties the results list to the command bar, so it opens just under it.
  final _resultsLink = LayerLink();
  OverlayEntry? _resultsEntry;

  /// A short message shown in the command bar for a moment ('Link copied').
  String _message = '';
  Timer? _messageTimer;
  bool _reloading = false;

  /// Focusing the command bar selects what's in it and opens the results; leaving it closes
  /// them (a moment later, so a click on a result still lands).
  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus) {
        _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
        _showResults();
      } else {
        Timer(const Duration(milliseconds: 150), _hideResults);
      }
    });
    _searchController.addListener(() {
      final resultsEntry = _resultsEntry;
      if (resultsEntry != null) {
        resultsEntry.markNeedsBuild();
      }
    });
  }

  @override
  void dispose() {
    _hideResults();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Shows `text` in the command bar for a second and a half.
  void say(String text) {
    final oldTimer = _messageTimer;
    if (oldTimer != null) {
      oldTimer.cancel();
    }
    setState(() {
      _message = text;
    });
    _messageTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _message = '';
        });
      }
    });
  }

  /// The app's context under the navigator, for opening sheets.
  BuildContext? get _appContext {
    return AppNav.context;
  }

  void _focusSearch() {
    _searchController.text = '';
    _searchFocus.requestFocus();
  }

  /// Fetches the boards again (signed in) and redraws the page.
  Future<void> _reload() async {
    if (_reloading) {
      return;
    }
    setState(() {
      _reloading = true;
    });
    if (AppState.I.signedIn) {
      await AppState.I.loadUserBoards();
    }
    AppState.I.pageChanged();
    if (mounted) {
      setState(() {
        _reloading = false;
      });
    }
  }

  Future<void> _copyLink() async {
    final link = linkFor(boardId: AppState.I.activeBoardId);
    if (link == null) {
      return;
    }
    await copyText(link);
    say('Link copied');
  }

  /// Ctrl+W: closes the open sheet or page if there is one, or else hides the window.
  void _closeTop() {
    bool somethingToClose;
    if (AppSheet.anyOpen) {
      somethingToClose = true;
    } else {
      final navigator = AppNav.navigatorKey.currentState;
      if (navigator != null) {
        somethingToClose = navigator.canPop();
      } else {
        somethingToClose = false;
      }
    }
    if (somethingToClose) {
      final navigator = AppNav.navigatorKey.currentState;
      if (navigator != null) {
        navigator.maybePop();
      }
    } else {
      Desktop.hide();
    }
  }

  /// Escape: leaves the command bar, then full screen, then closes the open sheet or page.
  void _escape() {
    if (_searchFocus.hasFocus) {
      _searchFocus.unfocus();
      return;
    }
    if (Desktop.fullScreen.value) {
      Desktop.setFullScreen(false);
      return;
    }
    final navigator = AppNav.navigatorKey.currentState;
    if (navigator != null) {
      navigator.maybePop();
    }
  }

  /// The command that switches the open board between Kanban and Timeline.
  _SearchHit _viewToggleHit(AppState app) {
    String icon;
    String title;
    if (app.isTimeline(app.activeBoard)) {
      icon = 'kanban';
      title = 'Show as Kanban';
    } else {
      icon = 'timeline';
      title = 'Show as Timeline';
    }
    return _SearchHit(icon, title, 'Command', app.toggleView);
  }

  /// What the command bar finds for what's typed: a link to open, then the app's commands,
  /// boards and (when something's typed) cards whose words match. At most 12.
  List<_SearchHit> _hits(String typed) {
    final appContext = _appContext;
    final app = AppState.I;
    final query = typed.trim().toLowerCase();
    final hits = <_SearchHit>[];
    final text = typed.trim();
    if (text.isNotEmpty && parseLink(text) != null) {
      hits.add(
        _SearchHit('link', 'Open $text', 'Link', () {
          _openTyped(text);
        }),
      );
    }
    final commands = <_SearchHit>[
      _SearchHit('plus', 'New board', 'Command', () {
        if (appContext != null) {
          openNewBoard(appContext);
        }
      }),
      _SearchHit('sync', 'Sync with another device', 'Command', () {
        if (appContext != null) {
          openSync(appContext);
        }
      }),
      _SearchHit('sun', 'Theme', 'Command · Ctrl+,', () {
        if (appContext != null) {
          openThemeSheet(appContext);
        }
      }),
      _SearchHit('help', 'Show me around', 'Command', () {
        if (appContext != null) {
          openTourPicker(appContext);
        }
      }),
      _SearchHit('bug', 'Report a bug', 'Command', () {
        if (appContext != null) {
          openBugReport(appContext);
        }
      }),
      if (app.activeBoard != null) ...[
        _viewToggleHit(app),
        _SearchHit('file-export', 'Export this board to a file', 'Command', exportActiveBoard),
        _SearchHit('file-import', 'Import a board file over this board', 'Command', importOverActiveBoard),
      ],
      _SearchHit('screenshot', 'Screenshot', 'Command', () {
        if (appContext != null) {
          Screenshots.take(appContext);
        }
      }),
      _SearchHit('refresh', 'Reload', 'Command · F5', _reload),
    ];
    for (final command in commands) {
      if (query.isEmpty || command.title.toLowerCase().contains(query)) {
        hits.add(command);
      }
    }
    for (final board in app.boards) {
      if (query.isEmpty || '${board['name']}'.toLowerCase().contains(query)) {
        String boardIcon;
        if (board['view'] == 'timeline') {
          boardIcon = 'timeline';
        } else {
          boardIcon = 'kanban';
        }
        hits.add(
          _SearchHit(boardIcon, '${board['name']}', 'Board', () {
            app.selectBoard('${board['id']}');
          }),
        );
      }
    }
    // Cards, by title or description, only once something's typed.
    if (query.isNotEmpty) {
      for (final board in app.boards) {
        for (final column in columnsOf(board)) {
          for (final card in cardsOf(column)) {
            Object? description = card['description'];
            if (description == null) {
              description = '';
            }
            if ('${card['title']}'.toLowerCase().contains(query) || '$description'.toLowerCase().contains(query)) {
              hits.add(
                _SearchHit('pencil', '${card['title']}', 'Card in ${board['name']} · ${column['name']}', () {
                  app.selectBoard('${board['id']}');
                  final cardContext = _appContext;
                  if (cardContext != null) {
                    openCardSheet(cardContext, board, '${card['id']}');
                  }
                }),
              );
            }
          }
        }
      }
    }
    return hits.take(12).toList();
  }

  /// Opens a typed link: another site's in the browser, the app's own in the app.
  Future<void> _openTyped(String text) async {
    final target = parseLink(text);
    if (target is LinkOut) {
      await Desktop.openExternal(target.uri.toString());
      say('Opened in your browser');
      return;
    }
    if (!await Links.open(text)) {
      say('Not found');
    }
  }

  /// Enter in the command bar: opens a link or address, or else runs the first result.
  void _submit(String text) {
    _searchFocus.unfocus();
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    if (parseLink(trimmed) != null) {
      _openTyped(trimmed);
      return;
    }
    // A bare address: the site's own, or another's.
    if (RegExp(r'^[^\s/?#]+\.[^\s/?#]+').hasMatch(trimmed) && !trimmed.contains(' ')) {
      _openTyped('https://$trimmed');
      return;
    }
    final hits = _hits(trimmed);
    if (hits.isEmpty) {
      say('Not found');
    } else {
      hits.first.run();
    }
  }

  /// Opens the results list under the command bar, rebuilt as the typing changes.
  void _showResults() {
    if (_resultsEntry != null) {
      return;
    }
    // The chrome sits above the navigator, so its overlay is the navigator's.
    final navigator = AppNav.navigatorKey.currentState;
    OverlayState? overlay;
    if (navigator != null) {
      overlay = navigator.overlay;
    }
    if (overlay == null) {
      return;
    }
    final resultsEntry = OverlayEntry(
      builder: (context) {
        final colors = UwuColors.of(context);
        final hits = _hits(_searchController.text);
        Widget resultsList;
        if (hits.isEmpty) {
          resultsList = Padding(
            padding: const EdgeInsets.all(14),
            child: Text('Nothing found', style: TextStyle(color: colors.muted)),
          );
        } else {
          resultsList = ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final hit in hits)
                ListTile(
                  dense: true,
                  leading: AppIcon(hit.icon, size: 16, color: colors.muted),
                  title: Text(
                    hit.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.ink, fontSize: 13.5),
                  ),
                  subtitle: Text(
                    hit.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colors.muted, fontSize: 11.5),
                  ),
                  onTap: () {
                    _searchFocus.unfocus();
                    hit.run();
                  },
                ),
            ],
          );
        }
        return Positioned(
          width: 520,
          child: CompositedTransformFollower(
            link: _resultsLink,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 6),
            child: Material(
              elevation: 12,
              color: Color.alphaBlend(colors.surfaceStrong, colors.bg),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(colors.round(12)),
                side: BorderSide(color: colors.edge),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: resultsList,
              ),
            ),
          ),
        );
      },
    );
    _resultsEntry = resultsEntry;
    overlay.insert(resultsEntry);
  }

  void _hideResults() {
    final resultsEntry = _resultsEntry;
    if (resultsEntry != null) {
      resultsEntry.remove();
    }
    _resultsEntry = null;
  }

  /// The keyboard shortcuts: Ctrl on Windows and Linux, ⌘ on macOS, plus each system's own keys
  /// for Back, Forward and full screen.
  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final mac = Env.macOS;

    /// A key with the system's command modifier (Ctrl, or ⌘ on macOS).
    SingleActivator withModifier(LogicalKeyboardKey key, {bool shift = false}) {
      return SingleActivator(key, control: !mac, meta: mac, shift: shift);
    }

    final appContext = _appContext;
    return {
      withModifier(LogicalKeyboardKey.keyK): _focusSearch,
      withModifier(LogicalKeyboardKey.keyF): _focusSearch,
      withModifier(LogicalKeyboardKey.keyL): _focusSearch,
      const SingleActivator(LogicalKeyboardKey.f6): _focusSearch,
      withModifier(LogicalKeyboardKey.keyC, shift: true): _copyLink,
      const SingleActivator(LogicalKeyboardKey.f5): _reload,
      withModifier(LogicalKeyboardKey.keyR): _reload,
      withModifier(LogicalKeyboardKey.comma): () {
        if (appContext != null) {
          openThemeSheet(appContext);
        }
      },
      withModifier(LogicalKeyboardKey.keyW): _closeTop,
      const SingleActivator(LogicalKeyboardKey.escape): _escape,
      if (mac) ...{
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): ViewHistory.back,
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): ViewHistory.forward,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true, control: true): () {
          Desktop.setFullScreen(!Desktop.fullScreen.value);
        },
        const SingleActivator(LogicalKeyboardKey.keyQ, meta: true): Desktop.quit,
        const SingleActivator(LogicalKeyboardKey.keyM, meta: true): () {
          windowManager.minimize();
        },
      } else ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): ViewHistory.back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): ViewHistory.forward,
        const SingleActivator(LogicalKeyboardKey.f11): () {
          Desktop.setFullScreen(!Desktop.fullScreen.value);
        },
      },
      withModifier(LogicalKeyboardKey.keyN): () {
        if (appContext != null) {
          openNewBoard(appContext);
        }
      },
    };
  }

  /// The title bar (hidden in full screen) over the app, with the shortcuts, and on macOS the
  /// menu bar.
  @override
  Widget build(BuildContext context) {
    final body = ValueListenableBuilder<bool>(
      valueListenable: Desktop.fullScreen,
      builder: (context, fullScreen, child) {
        return Column(
          children: [
            if (!fullScreen) _bar(context),
            Expanded(child: widget.child),
          ],
        );
      },
    );
    Widget app = CallbackShortcuts(
      bindings: _shortcuts,
      // The title bar sits above the navigator, so its tooltips and the command bar's text menus
      // need an overlay of their own. Without one, showing a tooltip throws, and the error box
      // fills the title bar.
      child: Focus(autofocus: true, child: Overlay.wrap(child: body)),
    );
    if (Env.macOS) {
      app = _MacMenus(chrome: this, child: app);
    }
    return app;
  }

  /// The title bar itself: its colour and writing colour worked out from the theme, then Back,
  /// Forward, Reload, the command bar, Copy link, the screenshot buttons, Update (when one's
  /// ready) and the window buttons.
  Widget _bar(BuildContext context) {
    final colors = UwuColors.of(context);
    final native = colors.native != null;
    Color brand;
    if (colors.glass) {
      brand = ThemeController.I.colorTheme.color;
    } else {
      brand = colors.brandFill;
    }
    final dark = colors.glass && ThemeController.I.brightness == Brightness.dark;
    // The bar's colour: clear on native glass, a deep shade of the brand in dark glass, or else
    // the brand colour itself.
    Color background;
    if (native) {
      background = Colors.transparent;
    } else if (dark) {
      background = Color.lerp(brand, Colors.black, 0.72)!;
    } else {
      background = brand;
    }
    // The writing colour: light or dark, whichever stands out on the bar.
    Color ink;
    if (native) {
      ink = colors.ink;
    } else if (ThemeData.estimateBrightnessForColor(background) == Brightness.dark) {
      ink = Colors.white;
    } else {
      ink = const Color(0xFF121815);
    }
    final mac = Env.macOS;

    /// One of the bar's icon buttons; faded when `onTap` is null (not available now).
    Widget tool(String icon, String label, VoidCallback? onTap, {Color? colour}) {
      Color iconColor;
      if (onTap == null) {
        iconColor = ink.withValues(alpha: 0.35);
      } else if (colour != null) {
        iconColor = colour;
      } else {
        iconColor = ink;
      }
      return Tooltip(
        excludeFromSemantics: true,
        message: label,
        child: Semantics(
          button: true,
          label: label,
          excludeSemantics: true,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 32,
              height: 30,
              child: Center(child: AppIcon(icon, size: 16, color: iconColor)),
            ),
          ),
        ),
      );
    }

    // On macOS the traffic lights sit at the left.
    double leadingGap;
    if (mac) {
      leadingGap = 78;
    } else {
      leadingGap = 8;
    }
    return Material(
      color: background,
      child: SizedBox(
        height: titleBarHeight,
        child: Row(
          children: [
            SizedBox(width: leadingGap),
            ValueListenableBuilder<int>(
              valueListenable: ViewHistory.changed,
              builder: (context, changeCount, child) {
                VoidCallback? onBack;
                if (ViewHistory.canBack) {
                  onBack = ViewHistory.back;
                } else {
                  onBack = null;
                }
                VoidCallback? onForward;
                if (ViewHistory.canForward) {
                  onForward = ViewHistory.forward;
                } else {
                  onForward = null;
                }
                return Row(
                  children: [
                    tool('arrow-left', 'Back', onBack),
                    tool('arrow-right', 'Forward', onForward),
                  ],
                );
              },
            ),
            if (_reloading)
              SizedBox(
                width: 32,
                child: Center(
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: ink)),
                ),
              )
            else
              tool('refresh', 'Reload', _reload),
            Expanded(
              child: DragToMoveArea(
                child: SizedBox(
                  height: titleBarHeight,
                  child: Center(child: _commandBar(colors, ink, native)),
                ),
              ),
            ),
            tool('link', 'Copy link', _copyLink),
            ValueListenableBuilder<bool>(
              valueListenable: Screenshots.busy,
              builder: (context, busy, child) {
                VoidCallback? onScreenshot;
                VoidCallback? onLongScreenshot;
                if (busy) {
                  onScreenshot = null;
                  onLongScreenshot = null;
                } else {
                  onScreenshot = () {
                    Screenshots.take(context);
                  };
                  onLongScreenshot = () {
                    Screenshots.takeLong(context);
                  };
                }
                return Row(
                  children: [
                    tool('screenshot', 'Screenshot', onScreenshot),
                    tool('screenshot-long', 'Long screenshot', onLongScreenshot),
                  ],
                );
              },
            ),
            ValueListenableBuilder<String?>(
              valueListenable: Updater.ready,
              builder: (context, ready, child) {
                if (ready == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF16A34A),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 28),
                    ),
                    onPressed: Updater.restartToUpdate,
                    icon: const AppIcon('download', size: 14, color: Colors.white),
                    label: Text('Update to $ready', style: const TextStyle(fontSize: 12)),
                  ),
                );
              },
            ),
            if (!mac) _WindowButtons(ink: ink) else const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// The command bar: at rest it shows the open board's name (or a message), centred in the
  /// bar's writing colour; focused, it's a search field in the theme's own colours.
  Widget _commandBar(UwuColors colors, Color ink, bool native) {
    final board = AppState.I.activeBoard;
    String rest;
    if (_message.isNotEmpty) {
      rest = _message;
    } else if (board == null) {
      rest = 'uwuBoard';
    } else {
      rest = '${board['name']}';
    }
    return CompositedTransformTarget(
      link: _resultsLink,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 160),
        child: SizedBox(
          height: 28,
          child: ListenableBuilder(
            listenable: Listenable.merge([_searchFocus, AppState.I]),
            builder: (context, child) {
              final focused = _searchFocus.hasFocus;
              TextAlign textAlign;
              Color textColor;
              Color fillColor;
              String hintText;
              Color hintColor;
              Color iconColor;
              if (focused) {
                textAlign = TextAlign.start;
                textColor = colors.ink;
                if (native) {
                  fillColor = Color.alphaBlend(colors.surfaceStrong, colors.bg);
                } else {
                  fillColor = colors.surfaceStrong;
                }
                hintText = 'Search boards, cards and commands, or paste a link';
                hintColor = colors.muted;
                iconColor = colors.muted;
              } else {
                textAlign = TextAlign.center;
                textColor = ink;
                if (native) {
                  fillColor = colors.surfaceStrong;
                } else {
                  fillColor = Colors.black.withValues(alpha: 0.08);
                }
                hintText = rest;
                hintColor = ink.withValues(alpha: 0.85);
                iconColor = ink.withValues(alpha: 0.7);
              }
              BorderSide enabledBorderSide;
              if (native) {
                enabledBorderSide = BorderSide(color: colors.edge);
              } else {
                enabledBorderSide = BorderSide.none;
              }
              return TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onSubmitted: _submit,
                textAlign: textAlign,
                style: TextStyle(fontSize: 13, color: textColor),
                cursorColor: colors.brandInk,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: fillColor,
                  hintText: hintText,
                  hintStyle: TextStyle(fontSize: 13, color: hintColor),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 6),
                    child: AppIcon('search', size: 14, color: iconColor),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 0),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(_barRadius(colors)), borderSide: BorderSide.none),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_barRadius(colors)),
                    borderSide: enabledBorderSide,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(_barRadius(colors)),
                    borderSide: BorderSide(color: colors.brandInk, width: 1.5),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The command bar's corners: Fluent's search box is barely rounded, Tahoe's a capsule.
double _barRadius(UwuColors colors) {
  switch (colors.native) {
    case GlassStyle.fluent:
      return 4;
    case GlassStyle.tahoe:
      return 14;
    default:
      return 8;
  }
}

/// Minimise, maximise or restore, and close (which keeps the app in the tray): full bar height,
/// 46 px wide each, close turning red on hover.
class _WindowButtons extends StatelessWidget {
  const _WindowButtons({required this.ink});
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Desktop.maximized,
      builder: (context, maximized, child) {
        String middleIcon;
        String middleLabel;
        if (maximized) {
          middleIcon = 'restore';
          middleLabel = 'Restore';
        } else {
          middleIcon = 'maximise';
          middleLabel = 'Maximise';
        }
        return Row(
          children: [
            _WindowButton(icon: 'minimise', label: 'Minimise', ink: ink, onTap: windowManager.minimize),
            _WindowButton(
              icon: middleIcon,
              label: middleLabel,
              ink: ink,
              onTap: () async {
                if (maximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowButton(icon: 'close', label: 'Close', ink: ink, close: true, onTap: Desktop.hide),
          ],
        );
      },
    );
  }
}

/// One of the window buttons, highlighted under the mouse (close in red).
class _WindowButton extends StatefulWidget {
  const _WindowButton({required this.icon, required this.label, required this.ink, required this.onTap, this.close = false});
  final String icon;
  final String label;
  final Color ink;
  final Future<void> Function() onTap;
  final bool close;

  @override
  State<_WindowButton> createState() {
    return _WindowButtonState();
  }
}

class _WindowButtonState extends State<_WindowButton> {
  /// True while the mouse is over it.
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    Color hoverColor;
    if (widget.close) {
      hoverColor = const Color(0xFFE81123);
    } else {
      hoverColor = widget.ink.withValues(alpha: 0.12);
    }
    Color background;
    if (_hovered) {
      background = hoverColor;
    } else {
      background = Colors.transparent;
    }
    Color iconColor;
    if (_hovered && widget.close) {
      iconColor = Colors.white;
    } else {
      iconColor = widget.ink;
    }
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (event) {
          setState(() {
            _hovered = true;
          });
        },
        onExit: (event) {
          setState(() {
            _hovered = false;
          });
        },
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: titleBarHeight,
            color: background,
            child: Center(child: AppIcon(widget.icon, size: 14, stroke: 1.4, color: iconColor)),
          ),
        ),
      ),
    );
  }
}

/// The macOS menu bar: App, File, Edit, View, Window and Help, wired to the app's actions.
class _MacMenus extends StatelessWidget {
  const _MacMenus({required this.chrome, required this.child});
  final _DesktopChromeState chrome;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final appContext = AppNav.context;

    /// One menu item, with its keyboard shortcut if it has one.
    PlatformMenuItem item(String label, VoidCallback onTap, [MenuSerializableShortcut? shortcut]) {
      return PlatformMenuItem(label: label, onSelected: onTap, shortcut: shortcut);
    }

    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'uwuBoard',
          menus: [
            PlatformMenuItemGroup(
              members: [
                item('Settings…', () {
                  if (appContext != null) {
                    openThemeSheet(appContext);
                  }
                }, const SingleActivator(LogicalKeyboardKey.comma, meta: true)),
                item('Check for Updates…', Updater.checkNow),
              ],
            ),
            if (PlatformProvidedMenuItem.hasMenu(PlatformProvidedMenuItemType.hide)) const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            item('Quit uwuBoard', Desktop.quit, const SingleActivator(LogicalKeyboardKey.keyQ, meta: true)),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            item('New Board', () {
              if (appContext != null) {
                openNewBoard(appContext);
              }
            }, const SingleActivator(LogicalKeyboardKey.keyN, meta: true)),
            item('Export Board…', exportActiveBoard),
            item('Import Board…', importOverActiveBoard),
            item('Close', chrome._closeTop, const SingleActivator(LogicalKeyboardKey.keyW, meta: true)),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            item('Find…', chrome._focusSearch, const SingleActivator(LogicalKeyboardKey.keyF, meta: true)),
            item('Copy Link', chrome._copyLink, const SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true)),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            item('Reload', chrome._reload, const SingleActivator(LogicalKeyboardKey.keyR, meta: true)),
            item('Back', ViewHistory.back, const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true)),
            item('Forward', ViewHistory.forward, const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true)),
            item(
              'Toggle Full Screen',
              () {
                Desktop.setFullScreen(!Desktop.fullScreen.value);
              },
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true, control: true),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Window',
          menus: [
            item('Minimise', () {
              windowManager.minimize();
            }, const SingleActivator(LogicalKeyboardKey.keyM, meta: true)),
            item('Sync with Another Device…', () {
              if (appContext != null) {
                openSync(appContext);
              }
            }),
          ],
        ),
        PlatformMenu(
          label: 'Help',
          menus: [
            item('Show Me Around', () {
              if (appContext != null) {
                openTourPicker(appContext);
              }
            }),
            item('Report a Bug…', () {
              if (appContext != null) {
                openBugReport(appContext);
              }
            }),
            item('uwuBoard on the Web', () {
              Desktop.openExternal(Desktop.site);
            }),
          ],
        ),
      ],
      child: child,
    );
  }
}
