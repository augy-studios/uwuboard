// The site's own API (main-site/api/*), called as the site's script.js calls it: JSON both
// ways, the session's token as a Bearer header, and an `error` field in a failed answer. Plus
// one notifier for whether the network is there at all, which the offline bar listens to.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// The site's host: the API's base, the links the app opens, and the update check.
const siteHost = 'board.uwuapps.org';
const siteOrigin = 'https://$siteHost';

/// The Play build: no updater of its own (--dart-define=UWUBOARD_PLAY=true).
const isPlayBuild = bool.fromEnvironment('UWUBOARD_PLAY');

/// A failed API call: what the server said (or 'No connection') and the HTTP status.
class ApiError implements Exception {
  ApiError(this.message, {this.status = 0});
  final String message;

  /// The HTTP status, or 0 when the server was never reached.
  final int status;
  bool get offline {
    return status == 0;
  }

  @override
  String toString() {
    return message;
  }
}

class Api {
  Api._();

  /// The session's token, or null as a guest.
  static String? token;

  /// For tests: answers instead of the network.
  static http.Client client = http.Client();

  /// True while the last request couldn't reach the server.
  static final ValueNotifier<bool> offline = ValueNotifier(false);

  /// The session's token as a Bearer header, or no header at all as a guest.
  static Map<String, String> authorizationHeaders() {
    return {if (token != null) 'Authorization': 'Bearer $token'};
  }

  static Uri uri(String path) {
    return Uri.parse('$siteOrigin/api$path');
  }

  /// One JSON request to the API. Answers the JSON object the server sent, or throws an
  /// [ApiError] (with the server's `error` message) when it couldn't be reached or said no.
  static Future<Map<String, dynamic>> call(String method, String path, [Map<String, dynamic>? body]) async {
    final request = http.Request(method, uri(path));
    request.headers['Content-Type'] = 'application/json';
    request.headers.addAll(authorizationHeaders());
    if (body != null) {
      request.body = jsonEncode(body);
    }
    late final http.Response response;
    try {
      response = await http.Response.fromStream(await client.send(request).timeout(const Duration(seconds: 30)));
    } catch (error) {
      offline.value = true;
      throw ApiError('No connection', status: 0);
    }
    offline.value = false;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      } else {
        data = {};
      }
    } catch (error) {
      data = {};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      Object? errorMessage = data['error'];
      if (errorMessage == null) {
        errorMessage = 'Request failed';
      }
      throw ApiError('$errorMessage', status: response.statusCode);
    }
    return data;
  }

  /// Bytes from a route that answers with an image.
  static Future<({Uint8List bytes, String type})> bytes(String path) async {
    late final http.Response response;
    try {
      response = await client.get(uri(path), headers: authorizationHeaders()).timeout(const Duration(seconds: 30));
    } catch (error) {
      offline.value = true;
      throw ApiError('No connection', status: 0);
    }
    offline.value = false;
    if (response.statusCode != 200) {
      throw ApiError('HTTP ${response.statusCode}', status: response.statusCode);
    }
    final bodyBytes = response.bodyBytes;
    var contentType = response.headers['content-type'];
    if (contentType == null) {
      contentType = 'image/png';
    }
    return (bytes: bodyBytes, type: contentType.split(';').first.trim());
  }

  /// Asks again, quietly, until the network is back. Started once, as the app opens.
  static Timer? _probeTimer;
  static bool _watching = false;
  static void watchOffline() {
    if (_watching) {
      return;
    }
    _watching = true;
    offline.addListener(() {
      final probeTimer = _probeTimer;
      if (probeTimer != null) {
        probeTimer.cancel();
      }
      if (!offline.value) {
        return;
      }
      _probeTimer = Timer.periodic(const Duration(seconds: 15), (timer) async {
        try {
          await client.head(Uri.parse('$siteOrigin/manifest.json')).timeout(const Duration(seconds: 8));
          offline.value = false;
          timer.cancel();
        } catch (error) {
          // Still gone.
        }
      });
    });
  }
}
