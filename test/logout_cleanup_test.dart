import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/settings_page.dart';

void main() {
  test('remote sign-out failure does not block local logout cleanup', () async {
    final calls = <String>[];

    await performLogoutCleanup(
      signOutRemoteSession: () async {
        calls.add('remote');
        throw Exception('no Supabase Auth session');
      },
      clearLocalData: () async => calls.add('local'),
      clearApplicationState: () => calls.add('application'),
      clearCurrentUser: () => calls.add('user'),
    );

    expect(calls, <String>['remote', 'local', 'application', 'user']);
  });

  test('local cleanup failure remains a real logout failure', () async {
    final calls = <String>[];

    await expectLater(
      performLogoutCleanup(
        clearLocalData: () async {
          calls.add('local');
          throw Exception('storage unavailable');
        },
        clearApplicationState: () => calls.add('application'),
        clearCurrentUser: () => calls.add('user'),
      ),
      throwsException,
    );

    expect(calls, <String>['local']);
  });
}
