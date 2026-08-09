import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sunland_ai_app/database_token_provider.dart';

String _token(Map<String, Object> claims) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256'})}.${encode(claims)}.signature';
}

void main() {
  test(
    'clear invalidates an in-flight database token after identity switch',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      var userId = 'user-a';
      final firstResponse = Completer<http.Response>();
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        if (calls == 1) return firstResponse.future;
        return http.Response(
          jsonEncode({
            'token': _token({
              'id': 'user-b',
              'sub': 'user-b',
              'role': 'authenticated',
              'aud': 'authenticated',
              'exp': now + 900,
            }),
          }),
          200,
        );
      });
      final provider = DatabaseTokenProvider(
        client: client,
        appTokenProvider: ({bool forceRefresh = false}) async =>
            _token({'id': userId, 'exp': now + 3600}),
      );

      final stale = provider.getToken();
      provider.clear();
      userId = 'user-b';
      final fresh = provider.getToken();
      firstResponse.complete(
        http.Response(
          jsonEncode({
            'token': _token({
              'id': 'user-a',
              'sub': 'user-a',
              'role': 'authenticated',
              'aud': 'authenticated',
              'exp': now + 900,
            }),
          }),
          200,
        ),
      );

      await expectLater(stale, completion(isNull));
      expect(await fresh, isNotNull);
      expect(calls, 2);
      provider.dispose();
    },
  );

  test('expired and cross-user database tokens are rejected', () async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (final claims in <Map<String, Object>>[
      {
        'id': 'user-a',
        'sub': 'user-a',
        'role': 'authenticated',
        'aud': 'authenticated',
        'exp': now - 1,
      },
      {
        'id': 'user-b',
        'sub': 'user-b',
        'role': 'authenticated',
        'aud': 'authenticated',
        'exp': now + 900,
      },
    ]) {
      final provider = DatabaseTokenProvider(
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'token': _token(claims)}), 200),
        ),
        appTokenProvider: ({bool forceRefresh = false}) async =>
            _token({'id': 'user-a', 'exp': now + 3600}),
      );
      await expectLater(provider.getToken(), throwsA(isA<ApiTokenException>()));
      provider.dispose();
    }
  });
}
