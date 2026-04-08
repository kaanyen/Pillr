import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<({String name, Uint8List bytes})?> pickBulkImportXlsx() async {
  final pick = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    withData: true,
  );
  if (pick == null || pick.files.isEmpty) return null;
  final f = pick.files.first;
  final bytes = f.bytes;
  if (bytes == null) return null;
  return (name: f.name, bytes: bytes);
}
