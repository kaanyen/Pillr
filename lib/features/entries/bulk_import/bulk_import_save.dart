/// Saves generated text (the import template) to the user's device.
///
/// **Web** triggers a real download via an anchor element. **IO** hands the
/// text to the platform share sheet, which is how the app's other exports
/// already behave.
library;

export 'bulk_import_save_stub.dart'
    if (dart.library.html) 'bulk_import_save_web.dart'
    if (dart.library.io) 'bulk_import_save_io.dart';
