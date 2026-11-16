// PeerJS's public broker and its data channels, STUN only (uwuBoard's main-site/js/p2p.js, and
// docs/STUN-p2p-spec.md): the same broker, ids, ICE servers, wire and BinaryPack as
// PeerJS 1.5's, so the app shares with the site on another device and the other way round.
//
//   The broker  wss://0.peerjs.com/peerjs?key=peerjs&id=…&token=…: OPEN once registered, ID-TAKEN,
//               EXPIRE (the peer asked for isn't there), and OFFER, ANSWER and CANDIDATE between
//               peers, relayed by `dst` and `src`; a HEARTBEAT every 5 s.
//   A link      one WebRTC data channel, made by the guest (its label the connection's id, "dc_…"),
//               each message BinaryPack-packed, and one over 16300 bytes sent as chunks:
//               { __peerData, n, total, data }, put back together on arrival.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'binarypack.dart';

const peerPrefix = 'uwuboard-sync-';
const _brokerHost = '0.peerjs.com';
// STUN only: nothing passes through a server once the two have met.
const _iceServers = [
  {'urls': 'stun:stun.l.google.com:19302'},
  {'urls': 'stun:stun.cloudflare.com:3478'},
];
// The biggest message sent whole; a bigger one goes as chunks of this size.
const _maximumMessageBytes = 16300;
// More than this waiting to go out counts as congested.
const _congestedBufferBytes = 1024 * 1024;

// Not 1 << 32, which is 0 in Dart on the web.
String _randomToken() {
  return [for (var index = 0; index < 2; index = index + 1) math.Random.secure().nextInt(0x7fffffff).toRadixString(36)].join();
}

/// A link to one other device over PeerJS.
abstract class ShareLink {
  /// The other end's name: its broker id.
  String get peer;
  bool get isOpen;

  void Function()? onOpen;
  void Function(Map<String, dynamic> message)? onData;
  void Function()? onClose;

  void send(Map<String, Object?> message);
  Future<void> close({bool flush = false});

  /// Whether a picture's next chunk should wait.
  Future<bool> congested();
}

/// What went wrong, as js/p2p.js's describePeerError says it.
String describePeerError(String type) {
  switch (type) {
    case 'peer-unavailable':
      return 'Nobody is sharing with that code. Check it and try again.';
    case 'unavailable-id':
      return 'That code is already in use. Generate a new one.';
    case 'network':
    case 'server-error':
    case 'socket-error':
    case 'socket-closed':
      return 'Cannot reach the pairing service. Everything else still works.';
    default:
      return 'The connection failed.';
  }
}

const brokerErrors = {'network', 'server-error', 'socket-error', 'socket-closed', 'disconnected'};

/// One id on the broker. The socket can drop while channels stay up: it comes back under the same
/// id, backing off while it keeps failing.
class PeerBroker {
  PeerBroker(this.id, {required this.onMessage, required this.onOpen, required this.onError});

  final String id;
  final Future<void> Function(Map<String, dynamic> message) onMessage;
  final void Function() onOpen;
  final void Function(String type) onError;
  final String _tokenValue = _randomToken();

  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _retryTimer;
  Duration _retryDelay = const Duration(seconds: 1);
  bool _closed = false;
  bool isOpen = false;

  // One at a time, in order: a candidate must not overtake the offer it belongs to.
  Future<void> _queue = Future.value();

  /// A random id from the broker, for a guest.
  static Future<String> newId() async {
    final response = await http
        .get(Uri.parse('https://$_brokerHost:443/peerjs/id?ts=${DateTime.now().millisecondsSinceEpoch}${math.Random().nextDouble()}'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw 'server-error';
    }
    return response.body.trim();
  }

  /// Opens the socket to the broker under this id, handles what the broker says, and sends a
  /// heartbeat every 5 seconds. A failure tries again later (see [_dropped]).
  Future<void> connect() async {
    if (_closed) {
      return;
    }
    final url = 'wss://$_brokerHost:443/peerjs?key=peerjs&id=${Uri.encodeComponent(id)}&token=$_tokenValue&version=1.5.4';
    final WebSocketChannel socket;
    try {
      socket = WebSocketChannel.connect(Uri.parse(url));
      await socket.ready.timeout(const Duration(seconds: 15));
    } catch (error) {
      _dropped('network');
      return;
    }
    if (_closed) {
      socket.sink.close();
      return;
    }
    _socket = socket;
    _subscription = socket.stream.listen(
      (raw) {
        final Map<String, dynamic> message;
        try {
          message = Map<String, dynamic>.from(jsonDecode('$raw') as Map);
        } catch (error) {
          return;
        }
        switch (message['type']) {
          case 'OPEN':
            isOpen = true;
            _retryDelay = const Duration(seconds: 1);
            onOpen();
          case 'ID-TAKEN':
            onError('unavailable-id');
          case 'ERROR':
            onError('server-error');
          case 'HEARTBEAT':
            break;
          default:
            _queue = _queue.then((previous) {
              return onMessage(message);
            }).catchError((Object error) {});
        }
      },
      onDone: () {
        _dropped('socket-closed');
      },
      onError: (Object error) {
        _dropped('socket-error');
      },
    );
    final heartbeatTimer = _heartbeatTimer;
    if (heartbeatTimer != null) {
      heartbeatTimer.cancel();
    }
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      send({'type': 'HEARTBEAT'});
    });
  }

  void _dropped(String reason) {
    final heartbeatTimer = _heartbeatTimer;
    if (heartbeatTimer != null) {
      heartbeatTimer.cancel();
    }
    final subscription = _subscription;
    if (subscription != null) {
      subscription.cancel();
    }
    _subscription = null;
    _socket = null;
    final wasOpen = isOpen;
    isOpen = false;
    if (_closed) {
      return;
    }
    // Said once for each time it's lost, and tried again after a while.
    if (wasOpen || reason == 'network') {
      onError(reason);
    }
    final retryTimer = _retryTimer;
    if (retryTimer != null) {
      retryTimer.cancel();
    }
    _retryTimer = Timer(_retryDelay, connect);
    _retryDelay = Duration(milliseconds: math.min(_retryDelay.inMilliseconds * 2, 30000));
  }

  void send(Map<String, Object?> message) {
    try {
      final socket = _socket;
      if (socket != null) {
        socket.sink.add(jsonEncode(message));
      }
    } catch (error) {
      // Going down: its close says so.
    }
  }

  void close() {
    _closed = true;
    isOpen = false;
    final heartbeatTimer = _heartbeatTimer;
    if (heartbeatTimer != null) {
      heartbeatTimer.cancel();
    }
    final retryTimer = _retryTimer;
    if (retryTimer != null) {
      retryTimer.cancel();
    }
    final subscription = _subscription;
    if (subscription != null) {
      subscription.cancel();
    }
    final socket = _socket;
    if (socket != null) {
      socket.sink.close();
    }
    _socket = null;
  }
}

Future<RTCPeerConnection> _newConnection() {
  return createPeerConnection({'iceServers': _iceServers, 'sdpSemantics': 'unified-plan'});
}

/// One data channel to the other device.
class PeerLink extends ShareLink {
  PeerLink._(this.peer, this.connectionId, this._peerConnection);

  @override
  final String peer;
  final String connectionId;
  final RTCPeerConnection _peerConnection;

  RTCDataChannel? _dataChannel;
  bool _open = false;
  bool _gone = false;
  bool _remoteDescriptionSet = false;
  // Candidates that came before the other end's description, added once it's there.
  final List<RTCIceCandidate> _earlyCandidates = [];
  // The chunks of long messages still arriving, by message id.
  final Map<int, List<Uint8List?>> _chunks = {};
  int _nextChunkedMessageId = 0;

  @override
  bool get isOpen {
    return _open;
  }

  void _sayOpen() {
    _open = true;
    final openCallback = onOpen;
    if (openCallback != null) {
      openCallback();
    }
  }

  void _bindChannel(RTCDataChannel channel) {
    _dataChannel = channel;
    channel.onDataChannelState = (state) {
      if (state == RTCDataChannelState.RTCDataChannelOpen && !_open) {
        _sayOpen();
      } else if (state == RTCDataChannelState.RTCDataChannelClosed) {
        _handleClosed();
      }
    };
    channel.onMessage = (message) {
      final Uint8List bytes;
      if (message.isBinary) {
        bytes = message.binary;
      } else {
        bytes = Uint8List.fromList(utf8.encode(message.text));
      }
      _receive(bytes);
    };
    // Opened before the handler above was there.
    if (channel.state == RTCDataChannelState.RTCDataChannelOpen && !_open) {
      _sayOpen();
    }
  }

  void _watchConnection() {
    _peerConnection.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed || state == RTCIceConnectionState.RTCIceConnectionStateClosed) {
        _handleClosed();
      }
    };
  }

  void _handleClosed() {
    if (_gone) {
      return;
    }
    _gone = true;
    _open = false;
    final closeCallback = onClose;
    if (closeCallback != null) {
      closeCallback();
    }
  }

  /// One message's bytes: a chunk is kept until all its message's chunks are there, then the
  /// whole is read; a whole message with a type goes to [onData].
  void _receive(Uint8List bytes) {
    Object? decoded;
    try {
      decoded = BinaryPack.unpack(bytes);
    } catch (error) {
      return;
    }
    if (decoded is! Map) {
      return;
    }
    if (decoded['__peerData'] != null) {
      final messageId = decoded['__peerData'];
      final total = decoded['total'];
      final chunkIndex = decoded['n'];
      final part = decoded['data'];
      if (messageId is! num || total is! num || chunkIndex is! num || part is! Uint8List) {
        return;
      }
      if (total < 1 || total > 100000 || chunkIndex < 0 || chunkIndex >= total) {
        return;
      }
      // Bounded, so a device that starts long messages and never finishes them can't fill this
      // one's memory.
      if (!_chunks.containsKey(messageId.toInt()) && _chunks.length >= 8) {
        _chunks.remove(_chunks.keys.first);
      }
      var parts = _chunks[messageId.toInt()];
      if (parts == null) {
        parts = List<Uint8List?>.filled(total.toInt(), null);
        _chunks[messageId.toInt()] = parts;
      }
      if (chunkIndex >= parts.length) {
        return;
      }
      parts[chunkIndex.toInt()] = part;
      final complete = parts.every((piece) {
        return piece != null;
      });
      if (complete) {
        _chunks.remove(messageId.toInt());
        final whole = BytesBuilder(copy: false);
        for (final piece in parts) {
          whole.add(piece!);
        }
        _receive(whole.takeBytes());
      }
      return;
    }
    if (decoded['type'] is String) {
      final dataCallback = onData;
      if (dataCallback != null) {
        dataCallback(Map<String, dynamic>.from(decoded));
      }
    }
  }

  /// Sends one message, packed; one too big for a single send goes as numbered chunks.
  @override
  void send(Map<String, Object?> message) {
    final channel = _dataChannel;
    if (channel == null || !_open) {
      return;
    }
    final bytes = BinaryPack.pack(message);
    if (bytes.length <= _maximumMessageBytes) {
      channel.send(RTCDataChannelMessage.fromBinary(bytes)).catchError((Object error) {});
      return;
    }
    final messageId = _nextChunkedMessageId;
    _nextChunkedMessageId = _nextChunkedMessageId + 1;
    final total = (bytes.length / _maximumMessageBytes).ceil();
    for (var chunkIndex = 0; chunkIndex < total; chunkIndex = chunkIndex + 1) {
      final part = Uint8List.sublistView(bytes, chunkIndex * _maximumMessageBytes, math.min(bytes.length, (chunkIndex + 1) * _maximumMessageBytes));
      channel.send(RTCDataChannelMessage.fromBinary(BinaryPack.pack({'__peerData': messageId, 'n': chunkIndex, 'total': total, 'data': part}))).catchError((Object error) {});
    }
  }

  @override
  Future<bool> congested() async {
    final channel = _dataChannel;
    if (channel == null) {
      return false;
    }
    try {
      return await channel.getBufferedAmount() > _congestedBufferBytes;
    } catch (error) {
      return false;
    }
  }

  Future<void> _setRemoteDescription(Map sessionDescription) async {
    await _peerConnection.setRemoteDescription(RTCSessionDescription('${sessionDescription['sdp']}', '${sessionDescription['type']}'));
    _remoteDescriptionSet = true;
    for (final candidate in _earlyCandidates) {
      await _peerConnection.addCandidate(candidate);
    }
    _earlyCandidates.clear();
  }

  Future<void> _addCandidate(Map candidateJson) async {
    final candidateText = candidateJson['candidate'] as String?;
    final mediaId = candidateJson['sdpMid'] as String?;
    final lineIndexNumber = candidateJson['sdpMLineIndex'] as num?;
    int? lineIndex;
    if (lineIndexNumber != null) {
      lineIndex = lineIndexNumber.toInt();
    }
    final candidate = RTCIceCandidate(candidateText, mediaId, lineIndex);
    if (_remoteDescriptionSet) {
      await _peerConnection.addCandidate(candidate);
    } else {
      _earlyCandidates.add(candidate);
    }
  }

  @override
  Future<void> close({bool flush = false}) async {
    if (flush) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      final channel = _dataChannel;
      if (channel != null) {
        await channel.close();
      }
    } catch (error) {
      // Already closing.
    }
    try {
      await _peerConnection.close();
    } catch (error) {
      // Already closed.
    }
    _handleClosed();
  }
}

// A broker message's payload, or an empty map when it has none.
Map _payloadOf(Map<String, dynamic> message) {
  final payload = message['payload'] as Map?;
  if (payload == null) {
    return const {};
  }
  return payload;
}

/// Takes the links that come to one id on the broker, for the device sharing.
class PeerListener {
  PeerListener(String code, {required this.onLink, required this.onOpen, required this.onError}) {
    _broker = PeerBroker(peerPrefix + code, onMessage: _handleBrokerMessage, onOpen: onOpen, onError: onError);
  }

  final void Function(ShareLink link) onLink;
  final void Function() onOpen;
  final void Function(String type) onError;
  late final PeerBroker _broker;
  final Map<String, PeerLink> _links = {}; // connection id -> link

  Future<void> start() {
    return _broker.connect();
  }

  /// A guest's offer starts a new link and is answered; its candidates go to that link.
  Future<void> _handleBrokerMessage(Map<String, dynamic> message) async {
    final payload = _payloadOf(message);
    Object? source = message['src'];
    if (source == null) {
      source = '';
    }
    final sourceId = '$source';
    final connectionId = '${payload['connectionId']}';
    if (message['type'] == 'OFFER') {
      final peerConnection = await _newConnection();
      final link = PeerLink._(sourceId, connectionId, peerConnection);
      _links[connectionId] = link;
      peerConnection.onIceCandidate = (candidate) {
        _broker.send({
          'type': 'CANDIDATE',
          'payload': {'candidate': candidate.toMap(), 'type': 'data', 'connectionId': connectionId},
          'dst': sourceId,
        });
      };
      peerConnection.onDataChannel = link._bindChannel;
      link._watchConnection();
      onLink(link);
      await link._setRemoteDescription(payload['sdp'] as Map);
      final answer = await peerConnection.createAnswer();
      await peerConnection.setLocalDescription(answer);
      _broker.send({
        'type': 'ANSWER',
        'payload': {
          'sdp': {'type': answer.type, 'sdp': answer.sdp},
          'type': 'data',
          'connectionId': connectionId,
          'browser': 'flutter',
        },
        'dst': sourceId,
      });
    } else if (message['type'] == 'CANDIDATE') {
      final link = _links[connectionId];
      if (link != null) {
        await link._addCandidate(payload['candidate'] as Map);
      }
    } else if (message['type'] == 'LEAVE' || message['type'] == 'EXPIRE') {
      // Its channels say so themselves when they close.
    }
  }

  void close() {
    _links.clear();
    _broker.close();
  }
}

/// Connects to the device sharing a code, for the other screen.
class PeerDialer {
  PeerDialer({required this.onLink, required this.onError});

  final void Function(ShareLink link) onLink;
  final void Function(String type) onError;
  PeerBroker? _broker;
  PeerLink? _link;
  bool _closed = false;

  /// Gets an id of its own from the broker, registers it, and dials once the broker says it's
  /// open.
  Future<void> connect(String code) async {
    final String id;
    try {
      id = await PeerBroker.newId();
    } catch (error) {
      if (!_closed) {
        onError('network');
      }
      return;
    }
    if (_closed) {
      return;
    }
    var dialed = false;
    late final PeerBroker broker;
    broker = PeerBroker(
      id,
      onMessage: _handleBrokerMessage,
      onOpen: () {
        // Once: a broker reconnect says it's open again.
        if (dialed || _closed) {
          return;
        }
        dialed = true;
        _dial(broker, code);
      },
      onError: (type) {
        if (!_closed) {
          onError(type);
        }
      },
    );
    _broker = broker;
    await broker.connect();
  }

  /// Makes the data channel and sends the offer for it to the code's id on the broker.
  Future<void> _dial(PeerBroker broker, String code) async {
    final peerConnection = await _newConnection();
    if (_closed) {
      await peerConnection.close();
      return;
    }
    final connectionId = 'dc_${_randomToken()}';
    final destination = peerPrefix + code;
    final link = PeerLink._(destination, connectionId, peerConnection);
    _link = link;
    peerConnection.onIceCandidate = (candidate) {
      broker.send({
        'type': 'CANDIDATE',
        'payload': {'candidate': candidate.toMap(), 'type': 'data', 'connectionId': connectionId},
        'dst': destination,
      });
    };
    link._watchConnection();
    onLink(link);
    final channelOptions = RTCDataChannelInit();
    channelOptions.ordered = true;
    link._bindChannel(await peerConnection.createDataChannel(connectionId, channelOptions));
    final offer = await peerConnection.createOffer();
    await peerConnection.setLocalDescription(offer);
    broker.send({
      'type': 'OFFER',
      'payload': {
        'sdp': {'type': offer.type, 'sdp': offer.sdp},
        'type': 'data',
        'connectionId': connectionId,
        'label': connectionId,
        'reliable': true,
        'serialization': 'binary',
        'browser': 'flutter',
      },
      'dst': destination,
    });
  }

  Future<void> _handleBrokerMessage(Map<String, dynamic> message) async {
    final payload = _payloadOf(message);
    if (message['type'] == 'EXPIRE') {
      if (!_closed) {
        onError('peer-unavailable');
      }
      return;
    }
    final link = _link;
    if (link == null || payload['connectionId'] != link.connectionId) {
      return;
    }
    if (message['type'] == 'ANSWER') {
      await link._setRemoteDescription(payload['sdp'] as Map);
    }
    if (message['type'] == 'CANDIDATE') {
      await link._addCandidate(payload['candidate'] as Map);
    }
  }

  /// Off the broker: links already open carry on without it.
  void close() {
    _closed = true;
    final broker = _broker;
    if (broker != null) {
      broker.close();
    }
    _broker = null;
  }
}
