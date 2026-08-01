import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';
import 'package:sunland_ai_app/sunland_core_client.dart';
import 'package:sunland_ai_app/sunland_local_provider.dart';

class _FakeSunlandCoreClient implements SunlandCoreClient {
  var bootCount = 0;
  var initializeCount = 0;
  var sendCount = 0;
  var disposed = false;
  Map<String, String>? initializedState;
  SunlandCoreRequest? lastRequest;

  @override
  bool get isSupported => true;

  @override
  Future<void> boot() async {
    bootCount += 1;
  }

  @override
  Future<void> initializeNamespace({
    required String namespace,
    required Map<String, String> stateSnapshot,
  }) async {
    initializeCount += 1;
    initializedState = Map<String, String>.from(stateSnapshot);
  }

  @override
  Future<SunlandCoreResult> send(SunlandCoreRequest request) async {
    sendCount += 1;
    lastRequest = request;
    final incoming = Map<String, dynamic>.from(request.contextSnapshot! as Map);
    return SunlandCoreResult(
      content: '来自替代运行时',
      stateSnapshot: const {'sunland_knowledge_user-1': 'opaque-core-state'},
      contextSnapshot: {...incoming, 'runtimeApplied': true},
    );
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _MemorySunlandStateStore implements SunlandCoreStateStore {
  Map<String, String> value = {'existing': 'opaque-snapshot'};
  String? writtenUserId;

  @override
  Future<Map<String, String>> read(String userId) async {
    return Map<String, String>.from(value);
  }

  @override
  Future<void> write(String userId, Map<String, String> storage) async {
    writtenUserId = userId;
    value = Map<String, String>.from(storage);
  }
}

void main() {
  test('DeepSeek 聊天历史继续注入独立的 Provider 提示词', () {
    final history = buildChatHistory(
      rawMessages: const [
        {'isUser': true, 'text': '你好'},
      ],
      maxHistory: 20,
    );

    expect(history.first.role, 'system');
    expect(history.first.content, deepSeekSystemPrompt);
    expect(deepSeekSystemPrompt, contains('兽聚卡片协作协议'));
    expect(deepSeekSystemPrompt, isNot(contains('霜蓝')));
    expect(history.last.content, '你好');
  });

  test('旧 Flutter 会话安全迁移为 DeepSeek 会话', () {
    final conversation = Conversation.fromJson({
      'id': '100',
      'title': '旧对话',
      'updatedAt': 100,
      'history': [
        {'role': 'user', 'content': '你好'},
      ],
    });

    expect(conversation.provider, 'deepseek');
    expect(conversation.model, 'deepseek-v4-flash');
    expect(conversation.coreContext, isNull);
    expect(conversation.toJson()['provider'], 'deepseek');
  });

  test('网页 Sunland 会话字段可在 Flutter 无损往返', () {
    final conversation = Conversation.fromJson({
      'id': 200,
      'title': 'Sunland 对话',
      'provider': 'sunland',
      'model': 'frost',
      'userId': 'user@example.com',
      'createdAt': 180,
      'updatedAt': 200,
      'semanticContext': {
        'schemaVersion': 1,
        'version': 2,
        'recentTurns': [
          {'turnId': 'turn-2', 'speaker': 'user'},
        ],
      },
      'history': [
        {
          'role': 'assistant',
          'content': '',
          'isFurryCard': true,
          'furryEvents': [],
          'furryQuery': {'city': '上海', 'month': 9, 'year': 2026},
          'isEmpty': true,
        },
      ],
    });

    final encoded = conversation.toJson();
    expect(conversation.provider, 'sunland');
    expect(conversation.model, 'frost');
    expect(conversation.userId, 'user@example.com');
    expect(conversation.coreContext?['version'], 2);
    expect(encoded['provider'], 'sunland');
    expect(encoded['semanticContext']['version'], 2);
    expect(encoded['history'][0]['furryQuery']['city'], '上海');
    expect(encoded['history'][0]['furryEvents'], isEmpty);
  });

  test('Dart 不解释未知版本的 Core Semantic Context', () {
    final futureContext = {
      'schemaVersion': 99,
      'futureSemanticShape': {'ownedByCore': true},
    };

    expect(cloneSunlandCoreContext(futureContext), futureContext);
    expect(
      Conversation(
        id: 'future-context',
        title: '未来上下文',
        history: const [],
        updatedAt: 1,
        provider: 'sunland',
        coreContext: futureContext,
      ).toJson()['semanticContext'],
      futureContext,
    );
  });

  test('Provider 可替换运行时且不解释 Core 业务状态', () async {
    final client = _FakeSunlandCoreClient();
    final stateStore = _MemorySunlandStateStore();
    final provider = SunlandLocalProvider(
      client: client,
      stateStore: stateStore,
    );
    final contextSnapshot = {
      'schemaVersion': 1,
      'version': 2,
      'recentTurns': <dynamic>[],
      'futureCoreField': {'kept': true},
    };

    final first = await provider.send(
      userId: 'user-1',
      conversationUserId: 'user-1',
      input: '你好',
      turnId: 'turn-1',
      contextSnapshot: contextSnapshot,
    );
    await provider.send(
      userId: 'user-1',
      conversationUserId: 'user-1',
      input: '第二轮',
      turnId: 'turn-2',
      contextSnapshot: contextSnapshot,
    );

    expect(provider.isSupported, true);
    expect(first.content, '来自替代运行时');
    expect(first.contextSnapshot['runtimeApplied'], true);
    expect(first.contextSnapshot['futureCoreField'], {'kept': true});
    expect(client.initializeCount, 1);
    expect(client.sendCount, 2);
    expect(client.initializedState, {'existing': 'opaque-snapshot'});
    expect((client.lastRequest?.contextSnapshot as Map?)?['futureCoreField'], {
      'kept': true,
    });
    expect(stateStore.writtenUserId, 'user-1');
    expect(stateStore.value, {'sunland_knowledge_user-1': 'opaque-core-state'});

    await provider.dispose();
    expect(client.disposed, true);
  });

  test('Flutter Core bundle 与 manifest 的 hash 一致', () {
    final bundle = File('assets/sunland-core.js').readAsBytesSync();
    final manifestSource = File(
      'assets/sunland-core.manifest.json',
    ).readAsStringSync();
    final issues = <SunlandCoreIntegrityIssue>[];
    const verifier = SunlandCoreIntegrityVerifier();

    final manifest = verifier.verifyBundle(
      bundleBytes: bundle,
      bundleAsset: 'assets/sunland-core.js',
      manifestSource: manifestSource,
      report: issues.add,
    );
    expect(manifest, isNotNull);
    final verifiedManifest = manifest!;
    verifier.verifyRuntimeVersion(
      manifest: verifiedManifest,
      runtimeVersion: verifiedManifest.version,
      bundleAsset: 'assets/sunland-core.js',
      report: issues.add,
    );

    expect(issues, isEmpty);
  });

  test('Core 完整性失败非阻塞且结构化日志不含身份字段', () {
    final bundle = File('assets/sunland-core.js').readAsBytesSync();
    final manifestSource = File(
      'assets/sunland-core.manifest.json',
    ).readAsStringSync();
    final issues = <SunlandCoreIntegrityIssue>[];
    const verifier = SunlandCoreIntegrityVerifier();

    final changedBundle = [...bundle, 0];
    final manifest = verifier.verifyBundle(
      bundleBytes: Uint8List.fromList(changedBundle),
      bundleAsset: 'assets/sunland-core.js',
      manifestSource: manifestSource,
      report: issues.add,
    );
    expect(manifest, isNotNull);
    verifier.verifyRuntimeVersion(
      manifest: manifest!,
      runtimeVersion: 'unexpected-version',
      bundleAsset: 'assets/sunland-core.js',
      report: issues.add,
    );

    expect(issues.map((issue) => issue.code), contains('hash_mismatch'));
    expect(issues.map((issue) => issue.code), contains('version_mismatch'));
    for (final issue in issues) {
      expect(issue.toJson().keys.toSet(), {
        'event',
        'code',
        'asset',
        'expected',
        'actual',
      });
      final encoded = issue.toJson().toString().toLowerCase();
      expect(encoded, isNot(contains('userid')));
      expect(encoded, isNot(contains('email')));
    }
  });

  test('Flutter 生产链路包含本地 Core、Provider 锁定和能力禁用', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final providerSource = File(
      'lib/sunland_local_provider.dart',
    ).readAsStringSync();
    final clientContract = File(
      'lib/sunland_core_client.dart',
    ).readAsStringSync();
    final coreSource = File('lib/sunland_ai_core.dart').readAsStringSync();
    final webViewRuntime = File(
      'lib/sunland_webview_runtime_adapter.dart',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final coreBundle = File('assets/sunland-core.js');
    final coreManifest = File('assets/sunland-core.manifest.json');
    final logo = File('assets/studio.png');

    expect(mainSource, contains('if (isSunlandRequest)'));
    expect(mainSource, contains('sunlandProvider.send('));
    expect(mainSource, contains('当前对话已绑定 Sunland AI'));
    expect(mainSource, contains("onPressed: isSunlandConversation\n"));
    expect(mainSource, contains("'assets/studio.png'"));
    expect(providerSource, isNot(contains('WebViewController')));
    expect(providerSource, isNot(contains('createSunlandEngine')));
    expect(providerSource, isNot(contains('applySemanticContextUpdate')));
    expect(
      clientContract,
      contains('abstract interface class SunlandCoreClient'),
    );
    expect(clientContract, isNot(contains('webview_flutter')));
    expect(mainSource, isNot(contains('semanticContext')));
    expect(mainSource, isNot(contains('Reasoner')));
    expect(mainSource, isNot(contains('Knowledge')));
    expect(providerSource, isNot(contains('semanticContext')));
    expect(clientContract, isNot(contains('semanticContext')));
    expect(webViewRuntime, contains("semanticMode: 'passive'"));
    expect(webViewRuntime, contains("semanticContextMode: 'enabled'"));
    expect(webViewRuntime, contains('createSunlandEngine'));
    expect(webViewRuntime, contains('normalizeSemanticContext'));
    expect(webViewRuntime, contains('applySemanticContextUpdate'));
    expect(webViewRuntime, contains('SUNLAND_CORE_VERSION'));
    expect(webViewRuntime, contains('sunland.core.integrity'));
    expect(coreSource, contains('const String deepSeekSystemPrompt'));
    expect(coreSource, isNot(contains('sunlandSystemPrompt')));
    expect(coreSource, isNot(contains('你就是“霜蓝”')));
    for (final legacyFurrySymbol in [
      'isFurryQuery(',
      'extractCity(',
      'extractTimeRange(',
      'queryFurryEvents(',
      'fetchWeather(',
    ]) {
      expect(coreSource, isNot(contains(legacyFurrySymbol)));
    }
    expect(pubspec, contains('assets/sunland-core.js'));
    expect(pubspec, contains('assets/sunland-core.manifest.json'));
    expect(pubspec, contains('assets/studio.png'));
    expect(coreBundle.lengthSync(), greaterThan(100000));
    expect(coreManifest.lengthSync(), greaterThan(100));
    expect(logo.lengthSync(), greaterThan(10000));
  });
}
