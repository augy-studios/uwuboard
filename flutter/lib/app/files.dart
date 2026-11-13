// Saving a file the person asked for (a board export, a card image) and picking ones to open.
// On a computer the system's Save window; on Android the Downloads folder through the App
// plugin (MediaStore, no permission needed); in a browser a download.
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

import '../native/bridge.dart';
import 'env.dart';
import 'files_web_stub.dart' if (dart.library.js_interop) 'files_web.dart';
import 'nav.dart';

/// Returns where it went, or null if it didn't.
Future<String?> saveFile(String name, Uint8List bytes, {String mime = 'application/octet-stream'}) async {
  try {
    if (Env.android) {
      final r = await Native.call('App', 'saveFile', {'name': name, 'mime': mime, 'data': base64Encode(bytes)});
      return r?['path'] as String? ?? 'Downloads';
    }
    if (kIsWeb) {
      downloadInBrowser(name, bytes, mime);
      return name;
    }
    final where = await getSaveLocation(suggestedName: name);
    if (where == null) return null;
    await XFile.fromData(bytes, name: name, mimeType: mime).saveTo(where.path);
    return where.path;
  } catch (e) {
    AppNav.toast('Couldn’t save $name', error: true);
    return null;
  }
}

const imageTypes = XTypeGroup(
  label: 'Images',
  extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'heic'],
  mimeTypes: ['image/*'],
  uniformTypeIdentifiers: ['public.image'],
);
const jsonTypes = XTypeGroup(label: 'Board file', extensions: ['json'], mimeTypes: ['application/json'], uniformTypeIdentifiers: ['public.json']);

Future<List<XFile>> pickImages({bool multiple = true}) async {
  try {
    if (multiple) return await openFiles(acceptedTypeGroups: const [imageTypes]);
    final f = await openFile(acceptedTypeGroups: const [imageTypes]);
    return f == null ? const [] : [f];
  } catch (_) {
    return const [];
  }
}

Future<XFile?> pickJson() async {
  try {
    return await openFile(acceptedTypeGroups: const [jsonTypes]);
  } catch (_) {
    return null;
  }
}
