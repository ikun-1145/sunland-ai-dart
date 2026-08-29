// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sunland_ai_app/main.dart';
import 'package:sunland_ai_app/services/app_config_service.dart';
import 'package:sunland_ai_app/services/user_status_service.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('App shows splash screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'theme_chosen': true,
    });

    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MyApp(
        networkConnectivityService: onlineNetworkConnectivityService(),
        appConfigService: AppConfigService(rowLoader: () async => null),
        userStatusService: UserStatusService(
          currentUserIdLoader: () async => null,
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
