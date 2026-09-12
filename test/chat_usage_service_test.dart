import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sunland_ai_app/services/chat_usage_service.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';

void main() {
  test('a late chat response cannot apply yesterday quota to today', () async {
    for (final date in ['2000-01-01', chatUsageDate(DateTime.now())]) {
      int? remaining;
      final client = SunlandApiClient(
        tokenProvider: () async => 'test-token',
        client: MockClient(
          (_) async => http.Response(
            'data: {"choices":[{"delta":{"content":"hello"}}]}\n\ndata: [DONE]\n\n',
            200,
            headers: {'x-remain': '17', 'x-usage-date': date},
          ),
        ),
      );
      await client.sendChat(
        messages: [const ChatMessage(role: 'user', content: 'hello')],
        model: 'deepseek-v4-flash',
        deep: false,
        onRemainUpdated: (value) => remaining = value,
      );
      expect(remaining, date == '2000-01-01' ? isNull : 17);
      client.close();
    }
  });

  test(
    'reads shared quota on each request and switches day at UTC+8 midnight',
    () async {
      var now = DateTime.parse('2026-09-11T15:59:59Z');
      var remaining = 17;
      final service = ChatUsageService(
        tokenProvider: () async => 'test-token',
        now: () => now,
        client: MockClient((request) async {
          expect(request.url.path, '/v1/usage');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(request.body, '{}');
          return http.Response(
            jsonEncode({
              'userId': 'a',
              'date': chatUsageDate(now),
              'remain': remaining,
              'isPro': false,
            }),
            200,
          );
        }),
      );
      addTearDown(service.close);
      expect((await service.read('a')).remaining, 17);
      remaining = 16; // Web used one: no device cache can hide it.
      expect((await service.read('a')).remaining, 16);
      now = DateTime.parse('2026-09-11T16:00:00Z');
      remaining = 20;
      expect((await service.read('a')).date, '2026-09-12');
      expect((await service.read('a')).remaining, 20);
    },
  );

  test(
    'rejects wrong accounts, yesterday values and failed requests',
    () async {
      final now = DateTime.parse('2026-09-12T00:00:00Z');
      var body = {
        'userId': 'b',
        'date': '2026-09-12',
        'remain': 17,
        'isPro': false,
      };
      var status = 200;
      final service = ChatUsageService(
        tokenProvider: () async => 'test-token',
        now: () => now,
        client: MockClient(
          (_) async => http.Response(jsonEncode(body), status),
        ),
      );
      addTearDown(service.close);
      await expectLater(service.read('a'), throwsException);
      body = {...body, 'userId': 'a', 'date': '2026-09-11'};
      await expectLater(service.read('a'), throwsException);
      body = {...body, 'date': '2026-09-12', 'remain': -1, 'isPro': true};
      expect((await service.read('a')).isPro, true);
      status = 503;
      await expectLater(service.read('a'), throwsException);
    },
  );
}
