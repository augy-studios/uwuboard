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

/// A new random pairing code.
String generateCode() {
  final random = math.Random.secure();
  return [for (var index = 0; index < codeLength; index = index + 1) codeAlphabet[random.nextInt(codeAlphabet.length)]].join();
}

/// A typed code as the pairing uses it: capitals and digits only, at most `codeLength` long.
String normaliseCode(String input) {
  final cleaned = input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (cleaned.length > codeLength) {
    return cleaned.substring(0, codeLength);
  } else {
    return cleaned;
  }
}

bool isValidCode(String? input) {
  if (input == null) {
    return false;
  }
  final code = normaliseCode(input);
  return code.length == codeLength && code.split('').every(codeAlphabet.contains);
}

typedef StatusCallback = void Function(String status, {String? message, bool taken});

/// The site's Connection: the status, and one link's open and close said once each.
abstract class _Connection {
  String status = 'idle';
  StatusCallback? onStatus;
  void Function(Map<String, dynamic> message)? onMessage;

  void setStatus(String newStatus, {String? message, bool taken = false}) {
    status = newStatus;
    final statusCallback = onStatus;
    if (statusCallback != null) {
      statusCallback(newStatus, message: message, taken: taken);
    }
  }

  void linkOpened(ShareLink openedLink);
  void linkClosed(ShareLink closedLink, bool everOpened);

  /// Listens to a link: its opening, its messages (those with a type) and its closing, which
  /// is said only once.
  void bindLink(ShareLink link) {
    // A link that closes without ever opening never reached the other device.
    var everOpened = false;
    var finished = false;
    link.onOpen = () {
      everOpened = true;
      linkOpened(link);
    };
    link.onData = (message) {
      if (message['type'] is String) {
        final messageCallback = onMessage;
        if (messageCallback != null) {
          messageCallback(message);
        }
      }
    };
    link.onClose = () {
      if (finished) {
        return;
      }
      finished = true;
      linkClosed(link, everOpened);
    };
  }

  void send(Map<String, Object?> message);
  void close();
}

/// The device showing the code: it waits on the broker for guests, one at a time.
class Host extends _Connection {
  ShareLink? link;
  void Function()? onJoin;
  bool _closed = false;
  PeerListener? _listener;

  /// Takes the code's id on the broker and waits there for a guest.
  Future<void> start(String code) async {
    setStatus('connecting');
    _listener = PeerListener(
      code,
      onLink: (newLink) {
        if (_closed) {
          newLink.close();
          return;
        }
        bindLink(newLink);
      },
      onOpen: () {
        _refresh();
      },
      onError: (type) {
        if (_closed) {
          return;
        }
        if (type == 'unavailable-id') {
          setStatus('error', message: describePeerError(type), taken: true);
          return;
        }
        // A guest already attached doesn't need the broker.
        if (link != null && brokerErrors.contains(type)) {
          return;
        }
        setStatus('error', message: describePeerError(type));
      },
    );
    await _listener!.start();
  }

  @override
  void linkOpened(ShareLink openedLink) {
    // The newcomer replaces the incumbent.
    final old = link;
    link = openedLink;
    if (old != null && old != openedLink) {
      old.close();
    }
    final joinCallback = onJoin;
    if (joinCallback != null) {
      joinCallback();
    }
    _refresh();
  }

  @override
  void linkClosed(ShareLink closedLink, bool everOpened) {
    if (link != closedLink) {
      return;
    }
    link = null;
    _refresh();
  }

  void _refresh() {
    if (_closed) {
      return;
    }
    if (link != null) {
      setStatus('connected');
    } else {
      setStatus('waiting');
    }
  }

  @override
  void send(Map<String, Object?> message) {
    try {
      final currentLink = link;
      if (currentLink != null) {
        currentLink.send(message);
      }
    } catch (error) {
      // Closed between the check and the send; its close handler reports it.
    }
  }

  @override
  void close() {
    _closed = true;
    final linkToClose = link;
    link = null;
    if (linkToClose != null) {
      linkToClose.close();
    }
    final listener = _listener;
    if (listener != null) {
      listener.close();
    }
    _listener = null;
    status = 'idle';
  }
}

/// The device entering the code: it dials the host and gives up if nothing answers in time.
class Guest extends _Connection {
  ShareLink? link;
  ShareLink? _candidate;
  Timer? _timer;
  PeerDialer? _dialer;

  /// Dials the device sharing this code.
  Future<void> connect(String code) async {
    setStatus('connecting');
    // Nothing errors when ICE can't find a path; it just keeps trying.
    _timer = Timer(_connectTimeout, () {
      if (status != 'connecting') {
        return;
      }
      hangUp();
      setStatus('unreachable');
    });
    final dialer = PeerDialer(
      onLink: (newLink) {
        _candidate = newLink;
        bindLink(newLink);
      },
      onError: (type) {
        if (status == 'connected' && brokerErrors.contains(type)) {
          return;
        }
        if (status != 'connecting') {
          return;
        }
        hangUp();
        setStatus('error', message: describePeerError(type));
      },
    );
    _dialer = dialer;
    await dialer.connect(code);
  }

  void _cancelTimer() {
    final timer = _timer;
    if (timer != null) {
      timer.cancel();
    }
  }

  @override
  void linkOpened(ShareLink openedLink) {
    if (openedLink != _candidate) {
      openedLink.close();
      return;
    }
    link = openedLink;
    _cancelTimer();
    setStatus('connected');
    send({'type': 'hello', 'v': protocolVersion});
  }

  @override
  void linkClosed(ShareLink closedLink, bool everOpened) {
    if (closedLink != link && closedLink != _candidate) {
      return;
    }
    link = null;
    _candidate = null;
    if (everOpened) {
      setStatus('dropped');
    } else {
      setStatus('unreachable');
    }
  }

  @override
  void send(Map<String, Object?> message) {
    final currentLink = link;
    if (currentLink == null || !currentLink.isOpen) {
      return;
    }
    try {
      currentLink.send(message);
    } catch (error) {
      // As on the host.
    }
  }

  /// Leaving on purpose: `bye` first, and a flushed close so it arrives.
  void leave() {
    send({'type': 'bye'});
    _cancelTimer();
    final linkToClose = link;
    final dialer = _dialer;
    link = null;
    _candidate = null;
    _dialer = null;
    onStatus = null;
    if (linkToClose != null) {
      linkToClose.close(flush: true);
    }
    Timer(const Duration(seconds: 1), () {
      if (dialer != null) {
        dialer.close();
      }
    });
    status = 'idle';
  }

  /// Drops the link (or the one still trying) and leaves the broker.
  void hangUp() {
    _cancelTimer();
    var linkToClose = link;
    if (linkToClose == null) {
      linkToClose = _candidate;
    }
    link = null;
    _candidate = null;
    if (linkToClose != null) {
      linkToClose.close();
    }
    final dialer = _dialer;
    if (dialer != null) {
      dialer.close();
    }
    _dialer = null;
  }

  @override
  void close() {
    hangUp();
    status = 'idle';
  }
}
