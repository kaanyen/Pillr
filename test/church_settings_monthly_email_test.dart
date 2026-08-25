import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/church/domain/church_settings.dart';

void main() {
  test('monthly partner email settings default off', () {
    final s = ChurchSettings.fromData('demo-church', {
      'name': 'Demo Community Church',
    });
    expect(s.sendMonthlyPartnerEmails, isFalse);
    expect(s.primaryPastorUid, isNull);
    expect(s.partnerEmailFrom, isNull);
  });

  test('monthly partner email settings read from nested map', () {
    final s = ChurchSettings.fromData('c1', {
      'name': 'The Airport City Church',
      'settings': {
        'sendMonthlyPartnerEmails': true,
        'primaryPastorUid': 'pastor-1',
        'partnerEmailFrom':
            'Partner Appreciation <pastor@theairportcitychurch.com>',
      },
    });
    expect(s.sendMonthlyPartnerEmails, isTrue);
    expect(s.primaryPastorUid, 'pastor-1');
    expect(
      s.partnerEmailFrom,
      'Partner Appreciation <pastor@theairportcitychurch.com>',
    );
  });
}
