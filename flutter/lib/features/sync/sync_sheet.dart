// The Sync window (the site's #syncModal): show a code (with its link and a QR code) or enter
// the other device's; once connected, Import and Send tabs with the boards and theme to tick.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/sheet.dart';
import 'sync_controller.dart';

Future<void> openSync(BuildContext context, {String? code}) async {
  final s = SyncController.I;
  s.opened();
  if (code != null) s.fromLink(code);
  await AppSheet.show(context, id: 'sync', width: 520, builder: (context) => const SyncSheet());
  s.closed();
}

class SyncSheet extends StatefulWidget {
  const SyncSheet({super.key});

  @override
  State<SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<SyncSheet> with WidgetsBindingObserver {
  late final _code = TextEditingController(text: SyncController.I.codeInput);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SyncController.I.addListener(_follow);
  }

  void _follow() {
    final v = SyncController.I.codeInput;
    if (v != _code.text && SyncController.I.role != null) _code.text = v;
    if (v.isNotEmpty && _code.text.isEmpty) _code.text = v;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) SyncController.I.resumed(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SyncController.I.removeListener(_follow);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SyncController.I,
      builder: (context, _) {
        final s = SyncController.I;
        final c = UwuColors.of(context);
        final muted = TextStyle(color: c.muted, fontSize: 12.5, height: 1.4);
        return SheetFrame(
          title: 'Sync with another device',
          children: [
            Text(
              'Copy boards and your theme straight between this device and another. Both have to be on the same wifi, or one on the other’s hotspot. Copying adds and updates, and never deletes anything.',
              style: muted,
            ),
            if (s.statusText.isNotEmpty) _status(c, s),
            if (s.role == null) ..._start(c, s),
            if (s.role == 'host' && !s.connected) _host(c, s),
            if (s.connected) ..._live(c, s),
            if (s.note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Semantics(
                  liveRegion: true,
                  child: Text(s.note, style: TextStyle(color: s.noteError ? c.error : c.muted, fontSize: 13)),
                ),
              ),
            if (s.role != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (s.role == 'host') OutlinedButton(onPressed: () => s.newHostCode(), child: const Text('New code')),
                    OutlinedButton(onPressed: s.stop, child: Text(s.connected ? 'Disconnect' : (s.role == 'host' ? 'Stop' : 'Cancel'))),
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

  Widget _status(UwuColors c, SyncController s) {
    final dot = switch (s.statusTone) {
      'ok' => c.ok,
      'warn' => c.warn,
      'error' => c.error,
      _ => c.busy,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5, right: 8),
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(s.statusText, style: TextStyle(color: c.ink, fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _start(UwuColors c, SyncController s) => [
    const SizedBox(height: 14),
    FilledButton.icon(
      key: const ValueKey('sync-host'),
      onPressed: () {
        s.retryTaken();
        s.startHosting();
      },
      icon: AppIcon('sync', size: 16, color: c.onBrand),
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
            onSubmitted: s.join,
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(onPressed: () => s.join(_code.text), child: const Text('Connect')),
      ],
    ),
  ];

  Widget _host(UwuColors c, SyncController s) {
    final link = syncLink(s.hostCode);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        children: [
          Tooltip(
            excludeFromSemantics: true,
            message: 'Press to copy the link',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                try {
                  await Clipboard.setData(ClipboardData(text: link));
                  s.showNote('Link copied.');
                } catch (_) {
                  s.showNote('Couldn’t copy the link. Type the code on the other device instead.', error: true);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Text(
                  s.hostCode.isEmpty ? '------' : s.hostCode,
                  semanticsLabel: 'Sync code ${s.hostCode.split('').join(' ')}. Press to copy the link',
                  style: TextStyle(fontSize: 34, letterSpacing: 6, color: c.ink, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (s.hostCode.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: link, size: 180, padding: EdgeInsets.zero, semanticsLabel: 'QR code of the sync link'),
            ),
          const SizedBox(height: 8),
          SelectableText(link, style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }

  List<Widget> _live(UwuColors c, SyncController s) {
    final importing = s.tab == 'import';
    final all = s.offered();
    final picked = s.picked[s.tab]!;
    // A pick the other end has since got some other way isn't on offer any more.
    picked.removeWhere((k) => !all.any((f) => f.key == k && !f.done));
    final open = all.where((f) => !f.done).toList();
    final ticked = open.where((f) => picked.contains(f.key)).length;
    final n = picked.length;

    Widget tabButton(String id, String label) => Expanded(
      child: Semantics(
        selected: s.tab == id,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: () => s.setTab(id),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: s.tab == id ? c.brandFill : null, borderRadius: BorderRadius.circular(9)),
            child: Text(label, style: TextStyle(color: s.tab == id ? c.onBrand : c.ink)),
          ),
        ),
      ),
    );

    Widget group(String kind, String label) {
      final rows = all.where((f) => f.kind == kind).toList();
      if (rows.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              label,
              style: TextStyle(color: c.muted, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          for (final f in rows)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: f.done ? false : picked.contains(f.key),
              onChanged: f.done ? null : (v) => s.toggle(f.key, v == true),
              title: Text(f.title, style: TextStyle(color: f.done ? c.muted : c.ink, fontSize: 14)),
              subtitle: Text(f.sub, style: TextStyle(color: c.muted, fontSize: 12)),
              secondary: f.done || f.update
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.surfaceStrong,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Text(f.done ? (importing ? 'Already here' : 'Already there') : 'Has changes', style: TextStyle(fontSize: 11, color: c.muted)),
                    )
                  : null,
            ),
        ],
      );
    }

    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Row(children: [tabButton('import', 'Import'), tabButton('export', 'Send')]),
      ),
      const SizedBox(height: 8),
      Text(
        importing
            ? 'The other device’s boards and theme. Tick the ones to copy to this device.'
            : 'This device’s boards and theme. Tick the ones to copy to the other device.',
        style: TextStyle(color: c.muted, fontSize: 12.5),
      ),
      if (s.theirs == null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Text('Waiting for the other device…', style: TextStyle(color: c.muted)),
          ),
        )
      else ...[
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          tristate: true,
          value: open.isEmpty ? false : (ticked == open.length ? true : (ticked == 0 ? false : null)),
          onChanged: open.isEmpty ? null : (v) => s.toggleAll(ticked != open.length),
          title: Text('Select all', style: TextStyle(color: c.ink)),
        ),
        if (all.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(importing ? 'The other device has nothing to share yet.' : 'This device has nothing to share yet.', style: TextStyle(color: c.muted)),
          ),
        group('board', 'Boards'),
        group('setting', 'Theme'),
      ],
      const SizedBox(height: 10),
      FilledButton(
        onPressed: n == 0 ? null : s.copyPicked,
        child: Text(
          n == 0
              ? (importing ? 'Tick what to import' : 'Tick what to send')
              : importing
              ? (n == 1 ? 'Import 1 thing to this device' : 'Import $n things to this device')
              : (n == 1 ? 'Send 1 thing to the other device' : 'Send $n things to the other device'),
        ),
      ),
    ];
  }
}
