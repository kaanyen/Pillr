import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

String formatFirestoreDate(DateTime dt, {String pattern = 'MMMM d, y'}) {
  return DateFormat(pattern).format(dt);
}

DateTime? timestampToDateTime(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}

/// When someone last opened Pillr, in words: "Today", "Yesterday",
/// "3 days ago", "12 Oct", or "Not yet".
String lastActiveLabel(DateTime? at) {
  if (at == null) return 'Not yet';
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return formatFirestoreDate(at, pattern: days > 300 ? 'd MMM y' : 'd MMM');
}

