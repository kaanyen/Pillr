import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:the_pillr/features/auth/domain/user_church_index.dart';
import 'package:the_pillr/features/auth/providers/auth_providers.dart';

void main() {
  Future<bool> figuresFor(String role) async {
    final c = ProviderContainer(
      overrides: [
        userChurchIndexProvider.overrideWith(
          (ref) => Stream.value(UserChurchIndex(uid: 'u', churchId: 'c', role: role)),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(canSeeFiguresProvider, (_, _) {});
    for (var i = 0; i < 5 && !c.read(canSeeFiguresProvider); i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c.read(canSeeFiguresProvider);
  }

  test('an admin sees no figures', () async => expect(await figuresFor('admin'), isFalse));
  test('a pastor does', () async => expect(await figuresFor('pastor'), isTrue));
  test('staff see the ones they recorded', () async => expect(await figuresFor('staff'), isTrue));
}
