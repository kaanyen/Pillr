import 'dart:typed_data';

/// Never used in normal Flutter targets (web and VM each resolve to a real impl).
Future<({String name, Uint8List bytes})?> pickBulkImportXlsx() async {
  throw UnsupportedError('pickBulkImportXlsx: unsupported platform');
}
