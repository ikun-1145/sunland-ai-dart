import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:sunland_ai_app/main.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
    );
  });

  setUp(() {
    currentUserNotifier.value = null;
  });

  tearDown(() {
    currentUserNotifier.value = null;
  });

  testWidgets(
    'free users see deep-thinking unavailable instead of quota exhausted',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChatPage()));
      await tester.pump();

      await tester.tap(find.text('深度思考'));
      await tester.pumpAndSettle();

      expect(find.text('深度思考不可用'), findsOneWidget);
      expect(find.text('今日免费次数已用完'), findsNothing);
    },
  );
}
