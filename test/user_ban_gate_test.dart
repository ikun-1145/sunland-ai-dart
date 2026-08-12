import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunland_ai_app/ban_page.dart';
import 'package:sunland_ai_app/main.dart';
import 'package:sunland_ai_app/maintenance_page.dart';
import 'package:sunland_ai_app/services/app_config_service.dart';
import 'package:sunland_ai_app/services/user_status_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_helpers.dart';

Map<String, dynamic> _configRow(bool maintenanceEnabled) {
  return <String, dynamic>{
    'maintenance_enabled': maintenanceEnabled,
    'maintenance_title': '服务器维护中',
    'maintenance_message': '测试维护消息',
    'maintenance_estimated_end': null,
  };
}

Map<String, dynamic> _statusRow(bool isBanned, {String? reason}) {
  return <String, dynamic>{'is_banned': isBanned, 'ban_reason': reason};
}

User _testUser(String id) {
  return User.fromJson(<String, dynamic>{
    'id': id,
    'email': '$id@example.com',
    'aud': 'authenticated',
    'created_at': '2026-08-11T00:00:00.000Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
  })!;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_chosen': true,
    });
    currentUserNotifier.value = null;
  });

  tearDown(() {
    currentUserNotifier.value = null;
  });

  testWidgets('normal users continue to the existing app', (tester) async {
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async => _statusRow(false),
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(false),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BanPage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
  });

  testWidgets('banned users see BanPage and no Navigator', (tester) async {
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async => _statusRow(true, reason: '违反使用规范'),
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(false),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BanPage), findsOneWidget);
    expect(find.text('账号已限制使用'), findsOneWidget);
    expect(find.text('违反使用规范'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(Navigator), findsNothing);
  });

  testWidgets('maintenance has priority and skips the ban query', (
    tester,
  ) async {
    var statusRequestCount = 0;
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async {
        statusRequestCount++;
        return _statusRow(true);
      },
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(true),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MaintenancePage), findsOneWidget);
    expect(find.byType(BanPage), findsNothing);
    expect(statusRequestCount, 0);
  });

  testWidgets('ending maintenance reveals a still-banned account', (
    tester,
  ) async {
    var maintenanceEnabled = true;
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async => _statusRow(true, reason: '账号审核中'),
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(maintenanceEnabled),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MaintenancePage), findsOneWidget);

    maintenanceEnabled = false;
    await tester.tap(find.text('重新检查'));
    await tester.pumpAndSettle();

    expect(find.byType(MaintenancePage), findsNothing);
    expect(find.byType(BanPage), findsOneWidget);
    expect(find.text('账号审核中'), findsOneWidget);
    expect(find.byType(Navigator), findsNothing);
  });

  testWidgets('manual recheck unbans without logout or a second app', (
    tester,
  ) async {
    var isBanned = true;
    currentUserNotifier.value = _testUser('user-a');
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async => _statusRow(isBanned),
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(false),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BanPage), findsOneWidget);

    isBanned = false;
    await tester.tap(find.text('重新检查'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(BanPage), findsNothing);
    expect(find.byType(MyApp), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
    expect(find.byType(SplashPage), findsOneWidget);
    expect(currentUserNotifier.value?.id, 'user-a');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing ban reason keeps the default explanation', (
    tester,
  ) async {
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async => _statusRow(true),
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(false),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('你的账号目前无法使用 Sunland AI。'), findsOneWidget);
    expect(find.text('原因：'), findsNothing);
    expect(find.text(BanPage.appealEmail), findsOneWidget);
    expect(find.text('复制邮箱'), findsOneWidget);
  });

  testWidgets('status network errors fail open', (tester) async {
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async => throw Exception('network error'),
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(false),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BanPage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });

  testWidgets('resume detects a newly banned user', (tester) async {
    var isBanned = false;
    final statusService = UserStatusService(
      currentUserIdLoader: () async => 'user-a',
      rowLoader: (_) async => _statusRow(isBanned),
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(false),
        ),
        userStatusService: statusService,
        resumeCheckInterval: Duration.zero,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BanPage), findsNothing);

    isBanned = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(BanPage), findsOneWidget);
    expect(find.byType(Navigator), findsNothing);
  });

  testWidgets('an old identity request cannot overwrite the new user state', (
    tester,
  ) async {
    final responses = <String, Completer<Map<String, dynamic>?>>{};
    final requestedUsers = <String>[];
    final statusService = UserStatusService(
      currentUserIdLoader: () async => currentUserNotifier.value?.id,
      rowLoader: (userId) {
        requestedUsers.add(userId);
        final response = Completer<Map<String, dynamic>?>();
        responses[userId] = response;
        return response.future;
      },
    );

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(
          rowLoader: () async => _configRow(false),
        ),
        userStatusService: statusService,
      ),
    );
    await tester.pumpAndSettle();

    currentUserNotifier.value = _testUser('user-a');
    await tester.pump();
    expect(requestedUsers, <String>['user-a']);

    currentUserNotifier.value = _testUser('user-b');
    responses['user-a']!.complete(_statusRow(true, reason: '旧状态'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(BanPage), findsNothing);
    expect(requestedUsers, <String>['user-a', 'user-b']);

    responses['user-b']!.complete(_statusRow(false));
    await tester.pumpAndSettle();

    expect(find.byType(BanPage), findsNothing);
    expect(currentUserNotifier.value?.id, 'user-b');

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
