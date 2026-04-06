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
