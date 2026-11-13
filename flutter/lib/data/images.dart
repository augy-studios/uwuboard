// Card images and the avatar (main-site/js/images.js, docs/hide-images-spec.md). A signed-in
// user's image is fetched by its name from /api/images/get with the session in a header; a
// guest's is the data URL kept on this device; an old copy that still has a public `url` is
// read from it once. Each is fetched once per session and its bytes kept, so redrawing the
// board reuses them. All are let go on sign-out, when the account they belong to goes away.
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../api/api.dart';
import 'board.dart';

class LoadedImage {
  LoadedImage(this.bytes, this.type);
  final Uint8List bytes;
  final String type;
  String get dataUrl => 'data:$type;base64,${base64Encode(bytes)}';
}

class ImageStore {
  ImageStore._();

  static final Map<String, Future<LoadedImage>> _cache = {};
  static Future<LoadedImage>? _avatar;

  static String? keyOf(Json? image) {
    if (image == null) return null;
    if (image['file'] is String) return 'file:${image['file']}';
    if (image['data'] is String) return 'data:${image['id']}';
    if (image['url'] is String) return 'url:${image['url']}';
    return null;
  }

  static Future<LoadedImage> load(Json image) {
    final key = keyOf(image);
    if (key == null) return Future.error(StateError('No image'));
    final cached = _cache[key];
    if (cached != null) return cached;
    final entry = _fetch(image);
    _cache[key] = entry;
    // A failure isn't kept, so the next draw tries again.
    entry.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_cache[key], entry)) _cache.remove(key);
      },
    );
    return entry;
  }

  static Future<LoadedImage> _fetch(Json image) async {
    if (image['file'] is String) {
      final r = await Api.bytes('/images/get?id=${Uri.encodeQueryComponent(image['file'] as String)}');
      return LoadedImage(r.bytes, r.type);
    }
    if (image['data'] is String) {
      final parsed = parseDataUrl(image['data'] as String);
      if (parsed == null) throw StateError('Bad image');
      return parsed;
    }
    final res = await Api.client.get(Uri.parse(image['url'] as String));
    if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
    return LoadedImage(res.bodyBytes, (res.headers['content-type'] ?? 'image/png').split(';').first.trim());
  }

  /// As a data URL, for an export file or another device.
  static Future<String> dataUrl(Json image) async => image['data'] is String ? image['data'] as String : (await load(image)).dataUrl;

  /// The signed-in user's avatar. `fresh` after changing it, so the old one isn't reused.
  static Future<LoadedImage> avatar({bool fresh = false}) {
    if (fresh) _avatar = null;
    final existing = _avatar;
    if (existing != null) return existing;
    final entry = Api.bytes('/auth/avatar').then((r) => LoadedImage(r.bytes, r.type));
    _avatar = entry;
    entry.then<void>(
      (_) {},
      onError: (Object _) {
        if (identical(_avatar, entry)) _avatar = null;
      },
    );
    return entry;
  }

  /// Signing out: nothing of one account is left for the next.
  static void clear() {
    _cache.clear();
    _avatar = null;
  }
}

LoadedImage? parseDataUrl(String url) {
  final m = RegExp(r'^data:([\w/+.-]+);base64,').firstMatch(url);
  if (m == null) return null;
  try {
    return LoadedImage(base64Decode(url.substring(m.end)), m.group(1)!);
  } catch (_) {
    return null;
  }
}

/// A picked picture as the site's resizeImage() makes it: no wider than `maxWidth`, as a data
/// URL. The site writes WebP; Dart has no WebP writer, so this is a JPEG, or a PNG where the
/// picture is see-through. The server and device sync take all three.
String? resizeToDataUrl(Uint8List bytes, {int maxWidth = 1920}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return null;
  var picture = img.bakeOrientation(decoded);
  if (picture.width > maxWidth) picture = img.copyResize(picture, width: maxWidth, interpolation: img.Interpolation.average);
  final seeThrough = picture.numChannels == 4 && picture.any((p) => p.a < p.maxChannelValue);
  if (seeThrough) return 'data:image/png;base64,${base64Encode(img.encodePng(picture))}';
  return 'data:image/jpeg;base64,${base64Encode(img.encodeJpg(picture, quality: 90))}';
}
