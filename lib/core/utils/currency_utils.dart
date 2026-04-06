import 'package:intl/intl.dart';

/// Ghana Cedis — build doc § Cursor Instructions #12
final NumberFormat _cedis = NumberFormat.currency(
  locale: 'en_GH',
  symbol: '₵',
  decimalDigits: 2,
);

String formatCedis(num amount) => _cedis.format(amount);
