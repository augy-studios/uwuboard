// A download in the browser, for the build the Playwright suite drives.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Starts a browser download of [bytes] named [name], through a hidden link that is clicked
/// and removed straight away. The temporary address is let go ten seconds later.
void downloadInBrowser(String name, Uint8List bytes, String mime) {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement();
  link.href = url;
  link.download = name;
  final body = web.document.body;
  if (body != null) {
    body.append(link);
  }
  link.click();
  link.remove();
  Future.delayed(const Duration(seconds: 10), () {
    web.URL.revokeObjectURL(url);
  });
}
