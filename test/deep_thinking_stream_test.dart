import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';

void main() {
  test(
    'reasoning-only SSE deltas are emitted and retained through completion',
    () async {
      Map<String, dynamic>? requestBody;
      final client = SunlandApiClient(
        tokenProvider: () async => 'test-token',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            [
              'data: {"choices":[{"delta":{"reasoning_content":"先看图"}}]}',
              '',
              'data: {"choices":[{"delta":{"reasoning_content":"，再分析"}}]}',
              '',
              'data: {"choices":[{"delta":{"content":"这是答案"}}]}',
              '',
              'data: [DONE]',
              '',
            ].join('\n'),
            200,
            headers: const {'content-type': 'text/event-stream'},
          );
        }),
      );
      addTearDown(client.close);

      final responses = await client
          .sendChatStream(
            messages: const [ChatMessage(role: 'user', content: '识别这张图')],
            model: 'deepseek-v4-flash',
            deep: true,
          )
          .toList();

      expect(responses.first.content, isEmpty);
      expect(responses.first.reasoning, '先看图');
      expect(responses[1].reasoning, '先看图，再分析');
      expect(responses.last.content, '这是答案');
      expect(responses.last.reasoning, '先看图，再分析');
      expect(requestBody?['deep'], isTrue);
    },
  );

  test('assistant reasoning survives conversation serialization', () {
    const original = ChatMessage(
      role: 'assistant',
      content: '最终回答',
      reasoning: '完整思考内容',
    );

    final restored = ChatMessage.fromJson(original.toJson());

    expect(restored.content, '最终回答');
    expect(restored.reasoning, '完整思考内容');
  });
}
