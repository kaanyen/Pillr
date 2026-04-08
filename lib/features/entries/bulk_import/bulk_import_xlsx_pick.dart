/// Picks a single `.xlsx` file and returns its bytes.
///
/// **Web** uses a hidden `<input type="file">` ([dart:html]) because `file_picker`'s
/// method channel is not available in all Flutter web / DDC setups.
/// **IO** (mobile, desktop) uses [package:file_picker].
library;

export 'bulk_import_xlsx_pick_stub.dart'
    if (dart.library.html) 'bulk_import_xlsx_pick_web.dart'
    if (dart.library.io) 'bulk_import_xlsx_pick_io.dart';
