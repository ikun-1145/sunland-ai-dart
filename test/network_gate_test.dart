import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunland_ai_app/main.dart';
import 'package:sunland_ai_app/network_unavailable_page.dart';
import 'package:sunland_ai_app/services/app_config_service.dart';
import 'package:sunland_ai_app/services/network_connectivity_service.dart';
import 'package:sunland_ai_app/services/user_status_service.dart';

Map<String, dynamic> _activeConfigRow() {
  return <String, dynamic>{
    'maintenance_enabled': false,
    'maintenance_title': '服务器维护中',
    'maintenance_message': '测试维护消息',
    'maintenance_estimated_end': null,
  };
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_chosen': true,
    });
    currentUserNotifier.value = null;
    themeNotifier.value = ThemeMode.dark;
  });

  tearDown(() {
    currentUserNotifier.value = null;
    themeNotifier.value = ThemeMode.system;
  });

  testWidgets('offline startup shows the full-screen white retry page', (
    tester,
  ) async {
    var configRequestCount = 0;

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: NetworkConnectivityService(
          availabilityProbe: () async => false,
        ),
        appConfigService: AppConfigService(
          rowLoader: () async {
            configRequestCount++;
            return _activeConfigRow();
          },
        ),
        userStatusService: UserStatusService(
          currentUserIdLoader: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NetworkUnavailablePage), findsOneWidget);
    expect(find.text('网络连接异常'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(Navigator), findsNothing);
    expect(configRequestCount, 0);

    final pageScaffold = tester.widget<Scaffold>(
      find.descendant(
        of: find.byType(NetworkUnavailablePage),
        matching: find.byType(Scaffold),
      ),
    );
    expect(pageScaffold.backgroundColor, Colors.white);

    final image = tester.widget<Image>(
      find.descendant(
        of: find.byType(NetworkUnavailablePage),
        matching: find.byType(Image),
      ),
    );
    expect(
      image.image,
      isA<AssetImage>().having(
        (provider) => provider.assetName,
        'assetName',
        'assets/network_unavailable.jpg',
      ),
    );
  });

  testWidgets('refresh continues startup after the network recovers', (
    tester,
  ) async {
    var isOnline = false;
    var configRequestCount = 0;

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: NetworkConnectivityService(
          availabilityProbe: () async => isOnline,
        ),
        appConfigService: AppConfigService(
          rowLoader: () async {
            configRequestCount++;
            return _activeConfigRow();
          },
        ),
        userStatusService: UserStatusService(
          currentUserIdLoader: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NetworkUnavailablePage), findsOneWidget);
    expect(configRequestCount, 0);

    isOnline = true;
    await tester.tap(find.text('刷新'));
    await tester.pumpAndSettle();

    expect(find.byType(NetworkUnavailablePage), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(Navigator), findsOneWidget);
    expect(configRequestCount, 1);
  });

  testWidgets('returning to the foreground detects a lost connection', (
    tester,
  ) async {
    var isOnline = true;

    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: NetworkConnectivityService(
          availabilityProbe: () async => isOnline,
        ),
        appConfigService: AppConfigService(
          rowLoader: () async => _activeConfigRow(),
        ),
        userStatusService: UserStatusService(
          currentUserIdLoader: () async => null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);

    isOnline = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.byType(NetworkUnavailablePage), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(Navigator), findsNothing);
  });
}
