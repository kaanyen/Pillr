// Web-only: native file input (file_picker's channel is unavailable under DDC web).
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Web: native file input — avoids [file_picker] MethodChannel (missing on DDC / web).
///
/// The input must be attached to the document or some browsers ignore [click].
Future<({String name, Uint8List bytes})?> pickBulkImportXlsx() async {
  final completer = Completer<({String name, Uint8List bytes})?>();

  final input = html.FileUploadInputElement()
    ..accept = '.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ..style.display = 'none';

  html.document.body?.append(input);

  var cleanedUp = false;
  void Function(html.Event)? changeHandler;

  void cleanup() {
    if (cleanedUp) return;
    cleanedUp = true;
    final h = changeHandler;
    changeHandler = null;
    if (h != null) {
      input.removeEventListener('change', h);
    }
    input.remove();
  }

  void completeNull() {
    if (!completer.isCompleted) completer.complete(null);
  }

  changeHandler = (_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      cleanup();
      completeNull();
      return;
    }
    final file = files[0];
    final reader = html.FileReader();

    reader.onLoadEnd.listen((_) {
      if (reader.readyState != html.FileReader.DONE) return;

      try {
        final raw = reader.result;
        if (raw == null) {
          cleanup();
          completeNull();
          return;
        }
        final bytes = _bytesFromReaderResult(raw);
        cleanup();
        if (!completer.isCompleted) {
          completer.complete((name: file.name, bytes: bytes));
        }
      } catch (_) {
        cleanup();
        completeNull();
      }
    });

    reader.onError.listen((_) {
      cleanup();
      completeNull();
    });

    reader.readAsArrayBuffer(file);
  };

  input.addEventListener('change', changeHandler!);
  input.click();

  return completer.future.timeout(
    const Duration(minutes: 2),
    onTimeout: () {
      cleanup();
      return null;
    },
  );
}

Uint8List _bytesFromReaderResult(Object raw) {
  if (raw is Uint8List) return raw;
  if (raw is ByteBuffer) return Uint8List.view(raw);
  return Uint8List.view(raw as ByteBuffer);
}
