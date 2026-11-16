// Card images and the avatar (main-site/js/images.js, docs/hide-images-spec.md). A signed-in
// user's image is fetched by its name from /api/images/get with the session in a header; a
// guest's is the data URL kept on this device; an old copy that still has a public `url` is
// read from it once. Each is fetched once per session and its bytes kept, so redrawing the
// board reuses them. All are let go on sign-out, when the account they belong to goes away.
import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as imaging;

import '../api/api.dart';
import 'board.dart';

/// An image's bytes and its type (such as image/png).
class LoadedImage {
  LoadedImage(this.bytes, this.type);
  final Uint8List bytes;
  final String type;
  String get dataUrl {
    return 'data:$type;base64,${base64Encode(bytes)}';
  }
}

/// Fetches card images and the avatar once each, and keeps them until sign-out.
class ImageStore {
  ImageStore._();

  static final Map<String, Future<LoadedImage>> _cache = {};
  static Future<LoadedImage>? _avatar;

  /// What an image is kept under: its file name, its id (for a data URL) or its address.
  static String? keyOf(Json? image) {
    if (image == null) {
      return null;
    }
    if (image['file'] is String) {
      return 'file:${image['file']}';
    }
    if (image['data'] is String) {
      return 'data:${image['id']}';
    }
    if (image['url'] is String) {
      return 'url:${image['url']}';
    }
    return null;
  }

  /// An image's bytes: the kept copy if there is one, else fetched (and kept).
  static Future<LoadedImage> load(Json image) {
    final key = keyOf(image);
    if (key == null) {
      return Future.error(StateError('No image'));
    }
    final cached = _cache[key];
    if (cached != null) {
      return cached;
    }
    final entry = _fetch(image);
    _cache[key] = entry;
    // A failure isn't kept, so the next draw tries again.
    entry.then<void>(
      (loaded) {},
      onError: (Object error) {
        if (identical(_cache[key], entry)) {
          _cache.remove(key);
        }
      },
    );
    return entry;
  }

  static Future<LoadedImage> _fetch(Json image) async {
    if (image['file'] is String) {
      final answer = await Api.bytes('/images/get?id=${Uri.encodeQueryComponent(image['file'] as String)}');
      return LoadedImage(answer.bytes, answer.type);
    }
    if (image['data'] is String) {
      final parsed = parseDataUrl(image['data'] as String);
      if (parsed == null) {
        throw StateError('Bad image');
      }
      return parsed;
    }
    final response = await Api.client.get(Uri.parse(image['url'] as String));
    if (response.statusCode != 200) {
      throw StateError('HTTP ${response.statusCode}');
    }
    final bodyBytes = response.bodyBytes;
    var contentType = response.headers['content-type'];
    if (contentType == null) {
      contentType = 'image/png';
    }
    return LoadedImage(bodyBytes, contentType.split(';').first.trim());
  }

  /// As a data URL, for an export file or another device.
  static Future<String> dataUrl(Json image) async {
    if (image['data'] is String) {
      return image['data'] as String;
    } else {
      return (await load(image)).dataUrl;
    }
  }

  /// The signed-in user's avatar. `fresh` after changing it, so the old one isn't reused.
  static Future<LoadedImage> avatar({bool fresh = false}) {
    if (fresh) {
      _avatar = null;
    }
    final existing = _avatar;
    if (existing != null) {
      return existing;
    }
    final entry = Api.bytes('/auth/avatar').then((answer) {
      return LoadedImage(answer.bytes, answer.type);
    });
    _avatar = entry;
    entry.then<void>(
      (loaded) {},
      onError: (Object error) {
        if (identical(_avatar, entry)) {
          _avatar = null;
        }
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

/// A base64 data URL's bytes and type, or null when it isn't one.
LoadedImage? parseDataUrl(String url) {
  final match = RegExp(r'^data:([\w/+.-]+);base64,').firstMatch(url);
  if (match == null) {
    return null;
  }
  try {
    return LoadedImage(base64Decode(url.substring(match.end)), match.group(1)!);
  } catch (error) {
    return null;
  }
}

/// A picked picture as the site's resizeImage() makes it: no wider than `maxWidth`, as a data
/// URL. The site writes WebP; Dart has no WebP writer, so this is a JPEG, or a PNG where the
/// picture is see-through. The server and device sync take all three.
String? resizeToDataUrl(Uint8List bytes, {int maxWidth = 1920}) {
  final decoded = imaging.decodeImage(bytes);
  if (decoded == null) {
    return null;
  }
  var picture = imaging.bakeOrientation(decoded);
  if (picture.width > maxWidth) {
    picture = imaging.copyResize(picture, width: maxWidth, interpolation: imaging.Interpolation.average);
  }
  final seeThrough = picture.numChannels == 4 && picture.any((pixel) {
    return pixel.a < pixel.maxChannelValue;
  });
  if (seeThrough) {
    return 'data:image/png;base64,${base64Encode(imaging.encodePng(picture))}';
  }
  return 'data:image/jpeg;base64,${base64Encode(imaging.encodeJpg(picture, quality: 90))}';
}
