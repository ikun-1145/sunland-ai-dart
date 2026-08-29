import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/main.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _testUser() {
  return User.fromJson(<String, dynamic>{
    'id': 'test-user',
    'email': 'test@example.com',
    'aud': 'authenticated',
    'created_at': '2026-08-29T00:00:00.000Z',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
  })!;
}

void main() {
  setUp(() {
    currentUserNotifier.value = null;
  });

  tearDown(() {
    currentUserNotifier.value = null;
  });

  testWidgets('keeps the loading page visible while login is restoring', (
    tester,
  ) async {
    final restore = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: RootPage(
          loginRestorer: () async {
            await restore.future;
            currentUserNotifier.value = _testUser();
          },
        ),
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(SplashPage), findsNothing);

    restore.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LoginPage), findsNothing);
    expect(find.byType(SplashPage), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows login only after restoring finds no session', (
    tester,
  ) async {
    final restore = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(home: RootPage(loginRestorer: () => restore.future)),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);

    restore.complete();
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LoginPage), findsOneWidget);
  });
}
