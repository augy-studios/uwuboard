// The Sync window (the site's #syncModal): show a code (with its link and a QR code) or enter
// the other device's; once connected, Import and Send tabs with the boards and theme to tick.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/sheet.dart';
import 'sync_controller.dart';

/// Opens the Sync window. With a [code] (from a sync link), it starts joining that device
/// straight away. Tells the controller when the window opens and closes.
Future<void> openSync(BuildContext context, {String? code}) async {
  final syncController = SyncController.I;
  syncController.opened();
  if (code != null) {
    syncController.fromLink(code);
  }
  await AppSheet.show(
    context,
    id: 'sync',
    width: 520,
    builder: (context) {
      return const SyncSheet();
    },
  );
  syncController.closed();
}

class SyncSheet extends StatefulWidget {
  const SyncSheet({super.key});

  @override
  State<SyncSheet> createState() {
    return _SyncSheetState();
  }
}

class _SyncSheetState extends State<SyncSheet> with WidgetsBindingObserver {
  late final _code = TextEditingController(text: SyncController.I.codeInput);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SyncController.I.addListener(_follow);
  }

  /// Keeps the code box in step with the controller's code: always while connecting, and
  /// whenever the box is empty.
  void _follow() {
    final codeInput = SyncController.I.codeInput;
    if (codeInput != _code.text && SyncController.I.role != null) {
      _code.text = codeInput;
    }
    if (codeInput.isNotEmpty && _code.text.isEmpty) {
      _code.text = codeInput;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SyncController.I.resumed(true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncController.I.removeListener(_follow);
    super.dispose();
  }

  /// The window: an explanation, the status line, then either the start (show or enter a
  /// code), the code being shown, or the Import and Send tabs once connected, and the buttons
  /// to stop.
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncController.I,
      builder: (context, child) {
        final syncController = SyncController.I;
        final colors = UwuColors.of(context);
        final muted = TextStyle(color: colors.muted, fontSize: 12.5, height: 1.4);
        Color noteColor;
        if (syncController.noteError) {
          noteColor = colors.error;
        } else {
          noteColor = colors.muted;
        }
        String stopLabel;
        if (syncController.connected) {
          stopLabel = 'Disconnect';
        } else if (syncController.role == 'host') {
          stopLabel = 'Stop';
        } else {
          stopLabel = 'Cancel';
        }
        return SheetFrame(
          title: 'Sync with another device',
          children: [
            Text(
              'Copy boards and your theme straight between this device and another. Both have to be on the same wifi, or one on the other’s hotspot. Copying adds and updates, and never deletes anything.',
              style: muted,
            ),
            if (syncController.statusText.isNotEmpty) _status(colors, syncController),
            if (syncController.role == null) ..._start(colors, syncController),
            if (syncController.role == 'host' && !syncController.connected) _host(colors, syncController),
            if (syncController.connected) ..._live(colors, syncController),
            if (syncController.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Text(syncController.note, style: TextStyle(color: noteColor, fontSize: 13)),
                ),
              ),
            if (syncController.role != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (syncController.role == 'host')
                      OutlinedButton(
                        onPressed: () {
                          syncController.newHostCode();
                        },
                        child: const Text('New code'),
                      ),
                    OutlinedButton(onPressed: syncController.stop, child: Text(stopLabel)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            Text(
              'A free public service (PeerJS) introduces the two devices and sees their IP addresses. Your boards go straight from one device to the other.',
              style: muted,
            ),
          ],
        );
      },
    );
  }

  /// The status line: a coloured dot (green, amber, red, or busy) and the status text.
  Widget _status(UwuColors colors, SyncController syncController) {
    Color dotColor;
    switch (syncController.statusTone) {
      case 'ok':
        dotColor = colors.ok;
      case 'warn':
        dotColor = colors.warn;
      case 'error':
        dotColor = colors.error;
      default:
        dotColor = colors.busy;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(syncController.statusText, style: TextStyle(color: colors.ink, fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  /// Before connecting: a button to show a code on this device, or a box to type the other
  /// device's code and connect.
  List<Widget> _start(UwuColors colors, SyncController syncController) {
    return [
      const SizedBox(height: 14),
      FilledButton.icon(
        key: const ValueKey('sync-host'),
        onPressed: () {
          syncController.retryTaken();
          syncController.startHosting();
        },
        icon: AppIcon('sync', size: 16, color: colors.onBrand),
        label: const Text('Show a code on this device'),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('sync-code'),
              controller: _code,
              maxLength: 12,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              decoration: const InputDecoration(hintText: 'Or enter the other device’s code', counterText: ''),
              onSubmitted: syncController.join,
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () {
              syncController.join(_code.text);
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    ];
  }

  /// While this device waits as the host: its code in big letters (press to copy the link),
  /// a QR code of the link, and the link itself.
  Widget _host(UwuColors colors, SyncController syncController) {
    final link = syncLink(syncController.hostCode);
    String shownCode;
    if (syncController.hostCode.isEmpty) {
      shownCode = '------';
    } else {
      shownCode = syncController.hostCode;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          Tooltip(
            excludeFromSemantics: true,
            message: 'Press to copy the link',
            child: InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: link));
                  syncController.showNote('Link copied.');
                } catch (error) {
                  syncController.showNote('Couldn’t copy the link. Type the code on the other device instead.', error: true);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  shownCode,
                  semanticsLabel: 'Sync code ${syncController.hostCode.split('').join(' ')}. Press to copy the link',
                  style: TextStyle(fontSize: 34, letterSpacing: 6, color: colors.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (syncController.hostCode.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: link, size: 180, padding: EdgeInsets.zero, semanticsLabel: 'QR code of the sync link'),
            ),
          const SizedBox(height: 8),
          SelectableText(link, style: TextStyle(color: colors.muted, fontSize: 12)),
        ],
      ),
    );
  }

  /// Once connected: the Import and Send tabs, each a list of boards and theme settings to
  /// tick (with Select all), and the button that copies what's ticked.
  List<Widget> _live(UwuColors colors, SyncController syncController) {
    final importing = syncController.tab == 'import';
    final allItems = syncController.offered();
    final picked = syncController.picked[syncController.tab]!;
    // A pick the other end has since got some other way isn't on offer any more.
    picked.removeWhere((pickedKey) {
      return !allItems.any((item) {
        return item.key == pickedKey && !item.done;
      });
    });
    final openItems = allItems.where((item) {
      return !item.done;
    }).toList();
    final tickedCount = openItems.where((item) {
      return picked.contains(item.key);
    }).length;
    final pickedCount = picked.length;

    /// One of the Import / Send tab buttons.
    Widget tabButton(String id, String label) {
      final isSelected = syncController.tab == id;
      Color? fillColor;
      Color textColor;
      if (isSelected) {
        fillColor = colors.brandFill;
        textColor = colors.onBrand;
      } else {
        fillColor = null;
        textColor = colors.ink;
      }
      return Expanded(
        child: Semantics(
          selected: isSelected,
          button: true,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              syncController.setTab(id);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: fillColor, borderRadius: BorderRadius.circular(9)),
              child: Text(label, style: TextStyle(color: textColor)),
            ),
          ),
        ),
      );
    }

    /// One row to tick. A row the other end already has can't be ticked; it and a row with
    /// changes get a small label saying so.
    Widget itemRow(SyncItem item) {
      bool checkboxValue;
      ValueChanged<bool?>? onChanged;
      Color titleColor;
      if (item.done) {
        checkboxValue = false;
        onChanged = null;
        titleColor = colors.muted;
      } else {
        checkboxValue = picked.contains(item.key);
        onChanged = (value) {
          syncController.toggle(item.key, value == true);
        };
        titleColor = colors.ink;
      }
      Widget? badge;
      if (item.done || item.update) {
        String badgeText;
        if (item.done) {
          if (importing) {
            badgeText = 'Already here';
          } else {
            badgeText = 'Already there';
          }
        } else {
          badgeText = 'Has changes';
        }
        badge = Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: colors.surfaceStrong,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Text(badgeText, style: TextStyle(fontSize: 11, color: colors.muted)),
        );
      } else {
        badge = null;
      }
      return CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: checkboxValue,
        onChanged: onChanged,
        title: Text(item.title, style: TextStyle(color: titleColor, fontSize: 14)),
        subtitle: Text(item.sub, style: TextStyle(color: colors.muted, fontSize: 12)),
        secondary: badge,
      );
    }

    /// The rows of one kind (boards or theme settings) under a small heading; nothing if
    /// there are none.
    Widget group(String kind, String label) {
      final rows = allItems.where((item) {
        return item.kind == kind;
      }).toList();
      if (rows.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              label,
              style: TextStyle(color: colors.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          for (final item in rows) itemRow(item),
        ],
      );
    }

    String tabExplanation;
    String nothingToShare;
    if (importing) {
      tabExplanation = 'The other device’s boards and theme. Tick the ones to copy to this device.';
      nothingToShare = 'The other device has nothing to share yet.';
    } else {
      tabExplanation = 'This device’s boards and theme. Tick the ones to copy to the other device.';
      nothingToShare = 'This device has nothing to share yet.';
    }

    // Select all: off with nothing open, on when everything open is ticked, part-way (null)
    // when some are.
    bool? selectAllValue;
    ValueChanged<bool?>? onSelectAll;
    if (openItems.isEmpty) {
      selectAllValue = false;
      onSelectAll = null;
    } else {
      if (tickedCount == openItems.length) {
        selectAllValue = true;
      } else if (tickedCount == 0) {
        selectAllValue = false;
      } else {
        selectAllValue = null;
      }
      onSelectAll = (value) {
        syncController.toggleAll(tickedCount != openItems.length);
      };
    }

    // The copy button: off with nothing ticked, otherwise saying how many things it copies.
    VoidCallback? onCopy;
    String copyLabel;
    if (pickedCount == 0) {
      onCopy = null;
      if (importing) {
        copyLabel = 'Tick what to import';
      } else {
        copyLabel = 'Tick what to send';
      }
    } else {
      onCopy = syncController.copyPicked;
      if (importing) {
        if (pickedCount == 1) {
          copyLabel = 'Import 1 thing to this device';
        } else {
          copyLabel = 'Import $pickedCount things to this device';
        }
      } else {
        if (pickedCount == 1) {
          copyLabel = 'Send 1 thing to the other device';
        } else {
          copyLabel = 'Send $pickedCount things to the other device';
        }
      }
    }

    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.border),
        ),
        child: Row(children: [tabButton('import', 'Import'), tabButton('export', 'Send')]),
      ),
      const SizedBox(height: 8),
      Text(
        tabExplanation,
        style: TextStyle(color: colors.muted, fontSize: 12.5),
      ),
      if (syncController.theirs == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text('Waiting for the other device…', style: TextStyle(color: colors.muted)),
          ),
        )
      else ...[
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          tristate: true,
          value: selectAllValue,
          onChanged: onSelectAll,
          title: Text('Select all', style: TextStyle(color: colors.ink)),
        ),
        if (allItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(nothingToShare, style: TextStyle(color: colors.muted)),
          ),
        group('board', 'Boards'),
        group('setting', 'Theme'),
      ],
      const SizedBox(height: 10),
      FilledButton(
        onPressed: onCopy,
        child: Text(copyLabel),
      ),
    ];
  }
}
