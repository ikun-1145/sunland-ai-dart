import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunland_ai_app/sunland_remote_provider.dart';

typedef AdapterHandler =
    Future<ResponseBody> Function(
      RequestOptions options,
      Future<void>? cancelFuture,
    );

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

  final AdapterHandler handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options, cancelFuture);

  @override
  void close({bool force = false}) {}
}

Dio _dio(AdapterHandler handler) {
  final dio = Dio();
  dio.httpClientAdapter = _FakeAdapter(handler);
  return dio;
}

ResponseBody _jsonBody(Object value, [int status = 200]) {
  return ResponseBody.fromString(
    jsonEncode(value),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

Map<String, dynamic> _body(RequestOptions options) {
  final value = options.data is String
      ? jsonDecode(options.data as String)
      : options.data;
  return Map<String, dynamic>.from(value as Map);
}

String _appToken(String userId, [String marker = 'token']) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256'})}.${encode({'id': userId})}.$marker';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'preserves legacy state before app hydration, imports once, then executes a turn',
    () async {
      final requests = <String>[];
      final bodies = <Map<String, dynamic>>[];
      final token = _appToken('user-a');
      final dio = _dio((options, _) async {
        requests.add(options.uri.path);
        bodies.add(_body(options));
        if (options.uri.path == '/v1/migrations/local-state') {
          return _jsonBody({
            'migrationId': bodies.last['migrationId'],
            'status': 'complete',
          });
        }
        expect(options.headers['authorization'], 'Bearer $token');
        return _jsonBody({'response': '远程回答'});
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'sunland_core_storage_v1::user-a',
        jsonEncode({
          'sunland_knowledge_user-a': jsonEncode(<Object>[]),
          'sunland_knowledge_user-a::memory': jsonEncode(<Object>[]),
        }),
      );
      await prefs.setString(
        'conversations_user-a',
        jsonEncode([
          {
            'id': 'conversation-a',
            'provider': 'sunland',
            'semanticContext': {
              'schemaVersion': 1,
              'version': 2,
              'recentTurns': <Object>[],
            },
          },
        ]),
      );
      final provider = SunlandRemoteProvider(
        dio: dio,
        baseUrl: 'https://ai-core.test',
        tokenProvider: ({bool forceRefresh = false}) async => token,
      );
      await provider.preserveLegacyState('user-a');

      // Simulate ordinary app hydration rewriting the current conversation
      // record before the first remote Sunland turn.
      await prefs.setString(
        'conversations_user-a',
        jsonEncode([
          {
            'id': 'conversation-a',
            'provider': 'sunland',
            'title': 'newer local title',
          },
        ]),
      );

      final result = await provider.send(
        userId: 'user-a',
        conversationUserId: 'user-a',
        conversationId: 'conversation-a',
        input: '你好',
        turnId: 'turn-a',
      );

      expect(result.content, '远程回答');
      expect(requests, ['/v1/migrations/local-state', '/v1/turns']);
      expect(bodies.first['contexts'], [
        {
          'conversationId': 'conversation-a',
          'context': {
            'schemaVersion': 1,
            'version': 2,
            'recentTurns': <Object>[],
          },
        },
      ]);
      expect(bodies.last['conversationId'], 'conversation-a');
      expect(prefs.getString('sunland_core_storage_v1::user-a'), isNull);
      expect(
        prefs.getString('sunland_remote_legacy_conversations_user-a'),
        isNull,
      );
      expect(
        prefs.getString('conversations_user-a'),
        contains('newer local title'),
      );
      await provider.dispose();
    },
  );

  test('401 refreshes the shared app token once', () async {
    var calls = 0;
    final refreshFlags = <bool>[];
    final oldToken = _appToken('user-a', 'old');
    final freshToken = _appToken('user-a', 'fresh');
    final provider = SunlandRemoteProvider(
      dio: _dio((options, _) async {
        calls++;
        return calls == 1
            ? _jsonBody(<String, Object>{}, 401)
            : _jsonBody({'response': '重试成功'});
      }),
      baseUrl: 'https://ai-core.test',
      tokenProvider: ({bool forceRefresh = false}) async {
        refreshFlags.add(forceRefresh);
        return forceRefresh ? freshToken : oldToken;
      },
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sunland_remote_migration_user-a',
      jsonEncode({'status': 'complete'}),
    );

    final result = await provider.send(
      userId: 'user-a',
      conversationUserId: 'user-a',
      conversationId: 'conversation-a',
      input: '你好',
      turnId: 'turn-a',
    );

    expect(result.content, '重试成功');
    expect(refreshFlags, [false, true]);
    await provider.dispose();
  });

  test(
    'summary observation mode returns only the server summary payload',
    () async {
      final provider = SunlandRemoteProvider(
        dio: _dio((options, _) async {
          final body = _body(options);
          expect(body['observationMode'], 'summary');
          expect(body, isNot(contains('userId')));
          return _jsonBody({
            'response': '已理解',
            'observationSummary': {
              'schemaVersion': 1,
              'sunlandCoreVersion': '0.1.0',
            },
          });
        }),
        baseUrl: 'https://ai-core.test',
        tokenProvider: ({bool forceRefresh = false}) async =>
            _appToken('user-a'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'sunland_remote_migration_user-a',
        jsonEncode({'status': 'complete'}),
      );

      final result = await provider.send(
        userId: 'user-a',
        conversationUserId: 'user-a',
        conversationId: 'conversation-a',
        input: '你好',
        turnId: 'turn-summary',
        observationMode: 'summary',
      );

      expect(result.content, '已理解');
      expect(result.observationSummary, {
        'schemaVersion': 1,
        'sunlandCoreVersion': '0.1.0',
      });
      await provider.dispose();
    },
  );

  test(
    'knowledge and memory controls use authenticated user-scoped routes',
    () async {
      final requests = <RequestOptions>[];
      final provider = SunlandRemoteProvider(
        dio: _dio((options, _) async {
          requests.add(options);
          expect(options.headers['authorization'], startsWith('Bearer '));
          if (options.method == 'GET') {
            return _jsonBody({
              'items': [
                {
                  'id': 'knowledge/a',
                  'subject': '小蓝',
                  'relation': '喜欢',
                  'object': '猫',
                  'negated': false,
                },
              ],
              'nextCursor': null,
            });
          }
          return ResponseBody.fromString('', 204);
        }),
        baseUrl: 'https://ai-core.test',
        tokenProvider: ({bool forceRefresh = false}) async =>
            _appToken('user-a'),
      );

      final records = await provider.listKnowledge(userId: 'user-a');
      await provider.deleteKnowledge(
        userId: 'user-a',
        knowledgeId: records.single.id,
      );
      await provider.deleteAllKnowledge(userId: 'user-a');
      await provider.deleteRememberedName(userId: 'user-a');

      expect(records.single.label, '小蓝 喜欢 猫');
      expect(
        requests.map((request) => '${request.method} ${request.uri.path}'),
        <String>[
          'GET /v1/knowledge',
          'DELETE /v1/knowledge/knowledge%2Fa',
          'DELETE /v1/knowledge',
          'DELETE /v1/memory/name',
        ],
      );
      expect(requests.first.uri.queryParameters['limit'], '100');
      await provider.dispose();
    },
  );

  test('CancelToken terminates an in-flight remote request', () async {
    final provider = SunlandRemoteProvider(
      dio: _dio((options, cancelFuture) async {
        return Future.any<ResponseBody>([
          Future<ResponseBody>.delayed(
            const Duration(seconds: 2),
            () => _jsonBody({'response': 'too late'}),
          ),
          cancelFuture!.then<ResponseBody>(
            (_) => throw DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          ),
        ]);
      }),
      baseUrl: 'https://ai-core.test',
      tokenProvider: ({bool forceRefresh = false}) async => _appToken('user-a'),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'sunland_remote_migration_user-a',
      jsonEncode({'status': 'complete'}),
    );
    final pending = provider.send(
      userId: 'user-a',
      conversationUserId: 'user-a',
      conversationId: 'conversation-a',
      input: '停止',
      turnId: 'turn-cancel',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    provider.cancelCurrent();

    await expectLater(pending, throwsA(isA<SunlandRemoteProviderException>()));
    await provider.dispose();
  });

  test(
    'damaged legacy data stays local and surfaces a recovery warning',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('sunland_core_storage_v1::user-a', '{damaged');
      final provider = SunlandRemoteProvider(
        dio: _dio((_, _) async => _jsonBody({'response': '仍可远程回答'})),
        baseUrl: 'https://ai-core.test',
        tokenProvider: ({bool forceRefresh = false}) async =>
            _appToken('user-a'),
      );

      final result = await provider.send(
        userId: 'user-a',
        conversationUserId: 'user-a',
        conversationId: 'conversation-a',
        input: '你好',
        turnId: 'turn-damaged',
      );

      expect(result.content, '仍可远程回答');
      expect(result.migrationWarning, contains('损坏'));
      expect(prefs.getString('sunland_core_storage_v1::user-a'), '{damaged');
      await provider.dispose();
    },
  );

  test(
    'never sends a body-provided identity when conversation owner differs',
    () async {
      var networkCalls = 0;
      final provider = SunlandRemoteProvider(
        dio: _dio((_, _) async {
          networkCalls++;
          return _jsonBody({'response': 'unexpected'});
        }),
        tokenProvider: ({bool forceRefresh = false}) async =>
            _appToken('user-a'),
      );
      await expectLater(
        provider.send(
          userId: 'user-a',
          conversationUserId: 'user-b',
          conversationId: 'conversation-a',
          input: '你好',
          turnId: 'turn-a',
        ),
        throwsA(isA<SunlandRemoteProviderException>()),
      );
      expect(networkCalls, 0);
      await provider.dispose();
    },
  );

  test(
    '401 refresh cannot move an old request into a different user',
    () async {
      var networkCalls = 0;
      final provider = SunlandRemoteProvider(
        dio: _dio((_, _) async {
          networkCalls++;
          return _jsonBody(<String, Object>{}, 401);
        }),
        tokenProvider: ({bool forceRefresh = false}) async => forceRefresh
            ? _appToken('user-b', 'fresh')
            : _appToken('user-a', 'old'),
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'sunland_remote_migration_user-a',
        jsonEncode({'status': 'complete'}),
      );

      await expectLater(
        provider.send(
          userId: 'user-a',
          conversationUserId: 'user-a',
          conversationId: 'conversation-a',
          input: '你好',
          turnId: 'turn-a',
        ),
        throwsA(isA<SunlandRemoteProviderException>()),
      );
      expect(networkCalls, 1);
      await provider.dispose();
    },
  );
}
