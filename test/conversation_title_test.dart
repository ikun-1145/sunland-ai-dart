import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';

void main() {
  test('AI title request contains only the completed first exchange', () async {
    Uri? requestUri;
    Map<String, dynamic>? requestBody;
    final client = SunlandApiClient(
      tokenProvider: () async => 'test-token',
      client: MockClient((request) async {
        requestUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'title': '「缓存一致性修复。」'}),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(client.close);

    final title = await client.generateTitle(
      conversationId: 'conversation-1',
      userMessage: '用户第一次提问',
      aiMessage: 'AI 第一次回复',
    );

    expect(requestUri?.path, '/v1/conversation-title');
    expect(requestBody, {
      'conversationId': 'conversation-1',
      'userMessage': '用户第一次提问',
      'aiMessage': 'AI 第一次回复',
    });
    expect(title, '缓存一致性修复');
  });

  test(
    'title generation is eligible only after the first completed exchange',
    () {
      expect(
        shouldGenerateConversationTitle(
          userMessageCount: 1,
          titleGenerated: false,
          userMessage: '第一问',
          aiMessage: '第一答',
        ),
        isTrue,
      );
      expect(
        shouldGenerateConversationTitle(
          userMessageCount: 2,
          titleGenerated: false,
          userMessage: '第二问',
          aiMessage: '第二答',
        ),
        isFalse,
      );
      expect(
        shouldGenerateConversationTitle(
          userMessageCount: 1,
          titleGenerated: true,
          userMessage: '第一问',
          aiMessage: '第一答',
        ),
        isFalse,
      );
      expect(
        shouldGenerateConversationTitle(
          userMessageCount: 1,
          titleGenerated: false,
          userMessage: '第一问',
          aiMessage: '   ',
        ),
        isFalse,
      );
    },
  );

  test('chat completion wires the first reply into AI title generation', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains('shouldGenerateConversationTitle('));
    expect(mainSource, contains('userMessageCount: userMsgCount'));
    expect(mainSource, contains('aiMessage: responseContent'));
    expect(mainSource, contains('_generateFirstConversationTitle('));
    expect(mainSource, contains("if (model.autoTitle) '_autoTitle': true"));
    expect(mainSource, isNot(contains('aiMessage: messages.last["text"]')));
  });
}
