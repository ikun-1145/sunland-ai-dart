import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunland_ai_app/main.dart';
import 'package:sunland_ai_app/maintenance_page.dart';
import 'package:sunland_ai_app/services/app_config_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, dynamic> _configRow(bool maintenanceEnabled) {
  return <String, dynamic>{
    'maintenance_enabled': maintenanceEnabled,
    'maintenance_title': '服务器维护中',
    'maintenance_message': '测试维护消息',
    'maintenance_estimated_end': null,
  };
}

User _testUser() {
  return User.fromJson(<String, dynamic>{
    'id': 'test-user',
    'email': 'test@example.com',
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

  testWidgets('continues to the existing app when maintenance is disabled', (
    tester,
  ) async {
    final service = AppConfigService(rowLoader: () async => _configRow(false));

    await tester.pumpWidget(MyApp(appConfigService: service));
    await tester.pumpAndSettle();

    expect(find.byType(MaintenancePage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
  });

  testWidgets('blocks the existing app when maintenance is enabled', (
    tester,
  ) async {
    final service = AppConfigService(rowLoader: () async => _configRow(true));

    await tester.pumpWidget(MyApp(appConfigService: service));
    await tester.pumpAndSettle();

    expect(find.byType(MaintenancePage), findsOneWidget);
    expect(find.text('测试维护消息'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(Navigator), findsNothing);
  });

  testWidgets('manual recheck unlocks the app without a restart', (
    tester,
  ) async {
    var maintenanceEnabled = true;
    final service = AppConfigService(
      rowLoader: () async => _configRow(maintenanceEnabled),
    );

    await tester.pumpWidget(MyApp(appConfigService: service));
    await tester.pumpAndSettle();
    expect(find.byType(MaintenancePage), findsOneWidget);

    maintenanceEnabled = false;
    await tester.tap(find.text('重新检查'));
    await tester.pumpAndSettle();

    expect(find.byType(MaintenancePage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(MyApp), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
  });

  testWidgets('manual recovery preserves an existing login in one app', (
    tester,
  ) async {
    var maintenanceEnabled = true;
    currentUserNotifier.value = _testUser();
    final service = AppConfigService(
      rowLoader: () async => _configRow(maintenanceEnabled),
    );

    await tester.pumpWidget(MyApp(appConfigService: service));
    await tester.pumpAndSettle();
    expect(find.byType(MaintenancePage), findsOneWidget);

    maintenanceEnabled = false;
    await tester.tap(find.text('重新检查'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(MyApp), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
    expect(find.byType(SplashPage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('checks again on resume and enters maintenance', (tester) async {
    var maintenanceEnabled = false;
    final service = AppConfigService(
      rowLoader: () async => _configRow(maintenanceEnabled),
    );

    await tester.pumpWidget(
      MyApp(appConfigService: service, resumeCheckInterval: Duration.zero),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    maintenanceEnabled = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(MaintenancePage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
  });

  testWidgets('manual recheck joins an active resumed request with loading', (
    tester,
  ) async {
    final responses = <Completer<Map<String, dynamic>?>>[];
    var requestCount = 0;
    final service = AppConfigService(
      rowLoader: () {
        requestCount++;
        final response = Completer<Map<String, dynamic>?>();
        responses.add(response);
        return response.future;
      },
    );

    await tester.pumpWidget(
      MyApp(appConfigService: service, resumeCheckInterval: Duration.zero),
    );
    responses.single.complete(_configRow(true));
    await tester.pumpAndSettle();
    expect(find.byType(MaintenancePage), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(requestCount, 2);

    await tester.tap(find.text('重新检查'));
    await tester.pump();

    expect(requestCount, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    responses.last.complete(_configRow(true));
    await tester.pumpAndSettle();

    expect(find.text('重新检查'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a completed request does not set state after app disposal', (
    tester,
  ) async {
    final response = Completer<Map<String, dynamic>?>();
    final service = AppConfigService(rowLoader: () => response.future);

    await tester.pumpWidget(MyApp(appConfigService: service));
    await tester.pumpWidget(const SizedBox.shrink());

    response.complete(_configRow(true));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
