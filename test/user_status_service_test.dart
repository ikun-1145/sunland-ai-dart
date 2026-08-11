import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/user_status_service.dart';

void main() {
  group('UserStatusService', () {
    test('returns active for a normal user', () async {
      final service = UserStatusService(
        currentUserIdLoader: () async => 'user-a',
        rowLoader: (_) async => <String, dynamic>{
          'is_banned': false,
          'ban_reason': null,
        },
      );

      final status = await service.fetchCurrentUserStatus();

      expect(status.isBanned, isFalse);
      expect(status.banReason, isNull);
    });

    test('returns banned with a normalized reason', () async {
      final service = UserStatusService(
        currentUserIdLoader: () async => 'user-a',
        rowLoader: (_) async => <String, dynamic>{
          'is_banned': true,
          'ban_reason': '  违反使用规范  ',
        },
      );

      final status = await service.fetchCurrentUserStatus();

      expect(status.isBanned, isTrue);
      expect(status.banReason, '违反使用规范');
    });

    test(
      'returns active without querying when there is no current user',
      () async {
        var rowLoadCount = 0;
        final service = UserStatusService(
          currentUserIdLoader: () async => null,
          rowLoader: (_) async {
            rowLoadCount++;
            return <String, dynamic>{'is_banned': true, 'ban_reason': null};
          },
        );

        final status = await service.fetchCurrentUserStatus();

        expect(status.isBanned, isFalse);
        expect(rowLoadCount, 0);
      },
    );

    test('fails open when the user row is missing', () async {
      final service = UserStatusService(
        currentUserIdLoader: () async => 'missing-user',
        rowLoader: (_) async => null,
      );

      final status = await service.fetchCurrentUserStatus();

      expect(status.isBanned, isFalse);
    });

    test('fails open when the request throws', () async {
      final service = UserStatusService(
        currentUserIdLoader: () async => 'user-a',
        rowLoader: (_) async => throw Exception('network error'),
      );

      final status = await service.fetchCurrentUserStatus();

      expect(status.isBanned, isFalse);
    });

    test('fails open when the request times out', () async {
      final response = Completer<Map<String, dynamic>?>();
      final service = UserStatusService(
        currentUserIdLoader: () async => 'user-a',
        rowLoader: (_) => response.future,
        requestTimeout: const Duration(milliseconds: 10),
      );

      final status = await service.fetchCurrentUserStatus();

      expect(status.isBanned, isFalse);
    });

    test('fails open when is_banned has an invalid type', () async {
      final service = UserStatusService(
        currentUserIdLoader: () async => 'user-a',
        rowLoader: (_) async => <String, dynamic>{
          'is_banned': 'true',
          'ban_reason': null,
        },
      );

      final status = await service.fetchCurrentUserStatus();

      expect(status.isBanned, isFalse);
    });

    test('fails open when ban_reason has an invalid type', () async {
      final service = UserStatusService(
        currentUserIdLoader: () async => 'user-a',
        rowLoader: (_) async => <String, dynamic>{
          'is_banned': true,
          'ban_reason': 123,
        },
      );

      final status = await service.fetchCurrentUserStatus();

      expect(status.isBanned, isFalse);
    });

    test('coalesces concurrent requests', () async {
      var rowLoadCount = 0;
      final response = Completer<Map<String, dynamic>?>();
      final service = UserStatusService(
        currentUserIdLoader: () async => 'user-a',
        rowLoader: (_) {
          rowLoadCount++;
          return response.future;
        },
      );

      final first = service.fetchCurrentUserStatus();
      final second = service.fetchCurrentUserStatus();
      response.complete(<String, dynamic>{
        'is_banned': true,
        'ban_reason': null,
      });

      expect(identical(first, second), isTrue);
      expect((await first).isBanned, isTrue);
      expect((await second).isBanned, isTrue);
      expect(rowLoadCount, 1);
    });
  });
}
