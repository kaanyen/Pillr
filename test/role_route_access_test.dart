import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/core/router/role_route_access.dart';
import 'package:the_pillr/features/auth/domain/user_church_index.dart';

void main() {
  test('admin can open fellowships and use the manage tools', () {
    expect(isPathForbiddenForRole('/fellowships', 'admin'), isFalse);
    expect(isPathForbiddenForRole('/fellowships?view=manage', 'admin'), isFalse);
    expect(
      UserChurchIndex(uid: 'a', churchId: 'c1', role: 'admin')
          .canManageFellowships,
      isTrue,
    );
  });

  test('admin still cannot open records or partners', () {
    expect(isPathForbiddenForRole('/records', 'admin'), isTrue);
    expect(isPathForbiddenForRole('/partners', 'admin'), isTrue);
  });

  test('pastor, admin and staff can manage fellowships', () {
    expect(
      UserChurchIndex(uid: 'p', churchId: 'c1', role: 'pastor')
          .canManageFellowships,
      isTrue,
    );
    expect(
      UserChurchIndex(uid: 's', churchId: 'c1', role: 'staff')
          .canManageFellowships,
      isTrue,
    );
  });

  test('pastor, admin and staff can edit exchange rates', () {
    expect(
      UserChurchIndex(uid: 'p', churchId: 'c1', role: 'pastor')
          .canEditExchangeRates,
      isTrue,
    );
    expect(
      UserChurchIndex(uid: 'a', churchId: 'c1', role: 'admin')
          .canEditExchangeRates,
      isTrue,
    );
    expect(
      UserChurchIndex(uid: 's', churchId: 'c1', role: 'staff')
          .canEditExchangeRates,
      isTrue,
    );
  });

  test('staff can open Tools', () {
    expect(isPathForbiddenForRole('/tools', 'staff'), isFalse);
    expect(isPathForbiddenForRole('/tools', 'pastor'), isFalse);
    expect(isPathForbiddenForRole('/tools', 'admin'), isFalse);
    expect(
      UserChurchIndex(uid: 's', churchId: 'c1', role: 'staff').canUseTools,
      isTrue,
    );
  });

  test('monthly letters are for pastors only', () {
    expect(isPathForbiddenForRole('/settings/letters', 'pastor'), isFalse);
    expect(isPathForbiddenForRole('/settings/letters', 'staff'), isTrue);
    expect(isPathForbiddenForRole('/settings/letters', 'admin'), isTrue);
    expect(isPathForbiddenForRole('/settings', 'staff'), isFalse);
  });
}
