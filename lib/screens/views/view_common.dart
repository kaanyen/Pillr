import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../design/seline.dart';
import '../../features/leaderboard/giving_view.dart';

/// "Jan", "Feb"… for a [GivingView] month key.
String monthShort(int key) => DateFormat.MMM().format(GivingView.monthOf(key));

/// "January 2026" for a [GivingView] month key.
String monthLong(int key) => DateFormat.yMMMM().format(GivingView.monthOf(key));

/// "12 Oct" this year, "12 Oct 2025" otherwise, "Not yet" when there is none.
String gaveOn(DateTime? d) {
  if (d == null) return 'Not yet';
  final sameYear = d.year == DateTime.now().year;
  return DateFormat(sameYear ? 'd MMM' : 'd MMM y').format(d);
}

/// "1st", "2nd", "3rd", "4th"…
String ordinal(int n) {
  if (n <= 0) return '–';
  final teen = n % 100 >= 11 && n % 100 <= 13;
  final suffix = teen
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix';
}

/// The loading shape every giving view shows while entries arrive.
class ViewLoading extends StatelessWidget {
  const ViewLoading({super.key});

  @override
  Widget build(BuildContext context) => const SelCard(child: SelSkeletonRows());
}

/// A search box sized for the top of a list.
class ViewSearch extends StatelessWidget {
  const ViewSearch({super.key, required this.hint, required this.onChanged});

  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: SelField(
      hint: hint,
      prefixIcon: LucideIcons.search,
      onChanged: (v) => onChanged(v.trim().toLowerCase()),
    ),
  );
}
