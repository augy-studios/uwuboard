// Host and guest pairing (main-site/js/p2p.js, docs/STUN-p2p-spec.md). One device shows a code,
// the other enters it; PeerJS's public broker introduces the two (peer.dart), and after that
// nothing passes through a server. The same codes, peer ids and messages as the site's, so the
// app syncs with the site in a browser on another device and the other way round.
import 'dart:async';
import 'dart:math' as math;

import 'peer.dart';

const codeAlphabet = 'BCDFGHJKLMNPQRSTVWXYZ23456789';
const codeLength = 6;
const protocolVersion = 1;
const _connectTimeout = Duration(seconds: 15);

String generateCode() {
  final r = math.Random.secure();
  return [for (var i = 0; i < codeLength; i++) codeAlphabet[r.nextInt(codeAlphabet.length)]].join();
}

String normaliseCode(String input) {
  final s = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  return s.length > codeLength ? s.substring(0, codeLength) : s;
}

bool isValidCode(String? input) {
  if (input == null) return false;
  final c = normaliseCode(input);
  return c.length == codeLength && c.split('').every(codeAlphabet.contains);
}

typedef StatusFn = void Function(String status, {String? message, bool taken});

/// The site's Connection: the status, and one link's open and close said once each.
abstract class _Connection {
  String status = 'idle';
  StatusFn? onStatus;
  void Function(Map<String, dynamic> message)? onMessage;

  void setStatus(String s, {String? message, bool taken = false}) {
    status = s;
    onStatus?.call(s, message: message, taken: taken);
  }

  void linkOpened(ShareLink link);
  void linkClosed(ShareLink link, bool everOpened);

  void bindLink(ShareLink link) {
    // A link that closes without ever opening never reached the other device.
    var everOpened = false;
    var finished = false;
    link.onOpen = () {
      everOpened = true;
      linkOpened(link);
    };
    link.onData = (message) {
      if (message['type'] is String) onMessage?.call(message);
    };
    link.onClose = () {
      if (finished) return;
      finished = true;
      linkClosed(link, everOpened);
    };
  }

  void send(Map<String, Object?> message);
  void close();
}

class Host extends _Connection {
  ShareLink? link;
  void Function()? onJoin;
  bool _closed = false;
  PeerListener? _listener;

  Future<void> start(String code) async {
    setStatus('connecting');
    _listener = PeerListener(
      code,
      onLink: (l) {
        if (_closed) {
          l.close();
          return;
        }
        bindLink(l);
      },
      onOpen: () => _refresh(),
      onError: (type) {
        if (_closed) return;
        if (type == 'unavailable-id') {
          setStatus('error', message: describePeerError(type), taken: true);
          return;
        }
        // A guest already attached doesn't need the broker.
        if (link != null && brokerErrors.contains(type)) return;
        setStatus('error', message: describePeerError(type));
      },
    );
    await _listener!.start();
  }

  @override
  void linkOpened(ShareLink l) {
    // The newcomer replaces the incumbent.
    final old = link;
    link = l;
    if (old != null && old != l) old.close();
    onJoin?.call();
    _refresh();
  }

  @override
  void linkClosed(ShareLink l, bool everOpened) {
    if (link != l) return;
    link = null;
    _refresh();
  }

  void _refresh() {
    if (_closed) return;
    setStatus(link != null ? 'connected' : 'waiting');
  }

  @override
  void send(Map<String, Object?> message) {
    try {
      link?.send(message);
    } catch (_) {
      // Closed between the check and the send; its close handler reports it.
    }
  }

  @override
  void close() {
    _closed = true;
    final l = link;
    link = null;
    l?.close();
    _listener?.close();
    _listener = null;
    status = 'idle';
  }
}

class Guest extends _Connection {
  ShareLink? link;
  ShareLink? _candidate;
  Timer? _timer;
  PeerDialer? _dialer;

  Future<void> connect(String code) async {
    setStatus('connecting');
    // Nothing errors when ICE can't find a path; it just keeps trying.
    _timer = Timer(_connectTimeout, () {
      if (status != 'connecting') return;
      hangUp();
      setStatus('unreachable');
    });
    final dialer = PeerDialer(
      onLink: (l) {
        _candidate = l;
        bindLink(l);
      },
      onError: (type) {
        if (status == 'connected' && brokerErrors.contains(type)) return;
        if (status != 'connecting') return;
        hangUp();
        setStatus('error', message: describePeerError(type));
      },
    );
    _dialer = dialer;
    await dialer.connect(code);
  }

  @override
  void linkOpened(ShareLink l) {
    if (l != _candidate) {
      l.close();
      return;
    }
    link = l;
    _timer?.cancel();
    setStatus('connected');
    send({'type': 'hello', 'v': protocolVersion});
  }

  @override
  void linkClosed(ShareLink l, bool everOpened) {
    if (l != link && l != _candidate) return;
    link = null;
    _candidate = null;
    setStatus(everOpened ? 'dropped' : 'unreachable');
  }

  @override
  void send(Map<String, Object?> message) {
    final l = link;
    if (l == null || !l.isOpen) return;
    try {
      l.send(message);
    } catch (_) {
      // As on the host.
    }
  }

  /// Leaving on purpose: `bye` first, and a flushed close so it arrives.
  void leave() {
    send({'type': 'bye'});
    _timer?.cancel();
    final l = link;
    final dialer = _dialer;
    link = null;
    _candidate = null;
    _dialer = null;
    onStatus = null;
    l?.close(flush: true);
    Timer(const Duration(seconds: 1), () => dialer?.close());
    status = 'idle';
  }

  void hangUp() {
    _timer?.cancel();
    final l = link ?? _candidate;
    link = null;
    _candidate = null;
    l?.close();
    _dialer?.close();
    _dialer = null;
  }

  @override
  void close() {
    hangUp();
    status = 'idle';
  }
}
