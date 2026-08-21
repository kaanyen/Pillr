// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

/// Web: a real file download, so the template lands in the Downloads folder
/// where the user expects it rather than in a share sheet.
Future<void> saveTextFile({
  required String fileName,
  required String contents,
  String mimeType = 'text/csv',
}) async {
  // A BOM makes Excel open UTF-8 CSV without mangling accented names.
  final bytes = utf8.encode('﻿$contents');
  final blob = html.Blob(<Object>[bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);
  final anchor = html.AnchorElement(href: url)
    ..download = fileName
    ..style.display = 'none';
  html.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  html.Url.revokeObjectUrl(url);
}
