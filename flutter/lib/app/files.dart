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
      final result = await Native.call('App', 'saveFile', {'name': name, 'mime': mime, 'data': base64Encode(bytes)});
      String? savedPath;
      if (result != null) {
        savedPath = result['path'] as String?;
      }
      if (savedPath == null) {
        return 'Downloads';
      }
      return savedPath;
    }
    if (kIsWeb) {
      downloadInBrowser(name, bytes, mime);
      return name;
    }
    final where = await getSaveLocation(suggestedName: name);
    if (where == null) {
      return null;
    }
    await XFile.fromData(bytes, name: name, mimeType: mime).saveTo(where.path);
    return where.path;
  } catch (error) {
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

/// Lets the person choose one or more pictures; an empty list when they cancel or it fails.
Future<List<XFile>> pickImages({bool multiple = true}) async {
  try {
    if (multiple) {
      return await openFiles(acceptedTypeGroups: const [imageTypes]);
    }
    final pickedFile = await openFile(acceptedTypeGroups: const [imageTypes]);
    if (pickedFile == null) {
      return const [];
    } else {
      return [pickedFile];
    }
  } catch (error) {
    return const [];
  }
}

/// Lets the person choose a board file; null when they cancel or it fails.
Future<XFile?> pickJson() async {
  try {
    return await openFile(acceptedTypeGroups: const [jsonTypes]);
  } catch (error) {
    return null;
  }
}
