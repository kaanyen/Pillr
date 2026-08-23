import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/entries/domain/partnership_entry.dart';
import 'package:the_pillr/screens/approval_playback.dart';

PartnershipEntry _entry(int i) => PartnershipEntry(
  id: '$i',
  churchId: 'c',
  partnerId: 'p$i',
  partnerSnapshot: const {'fullName': 'Ama Boateng'},
  partnershipArmId: 'a',
  armSnapshot: const {'name': 'Missions'},
  partnershipPeriodId: 'per',
  periodSnapshot: const {'name': 'Q3'},
  amountCedis: 100,
  dateGiven: DateTime(2026, 8, 1),
  notes: null,
  status: 'approved',
  createdBy: 'u',
  createdBySnapshot: const {'fullName': 'Staff'},
  createdAt: DateTime(2026, 8, 1),
  updatedAt: DateTime(2026, 8, 1),
  reviewedBy: 'pastor',
  reviewedBySnapshot: const {'fullName': 'Pastor'},
  reviewedAt: DateTime(2026, 8, 1),
  declineReason: null,
  editHistory: const [],
);

void main() {
  // A batch of eleven or fewer used to invert the clamp bounds and throw
  // mid-build, which painted a blank screen instead of the tally.
  for (final n in [2, 3, 4, 7, 11, 12, 30, 100]) {
    testWidgets('plays back $n entries without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ApprovalPlayback(
            entries: [for (var i = 0; i < n; i++) _entry(i)],
            formatMoney: (v) => 'GHS $v',
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull);

      // And it holds at the end rather than closing itself: the finished
      // total stays on screen with a Done button to dismiss it.
      await tester.pump(const Duration(seconds: 30));
      expect(tester.takeException(), isNull);
      expect(find.text('Done'), findsOneWidget);
    });
  }
}
