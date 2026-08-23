import 'package:share_plus/share_plus.dart';

/// Mobile and desktop: hand the template to the share sheet, matching how the
/// app's other exports behave.
Future<void> saveTextFile({
  required String fileName,
  required String contents,
  String mimeType = 'text/csv',
}) async {
  await SharePlus.instance.share(
    ShareParams(text: contents, subject: fileName),
  );
}
