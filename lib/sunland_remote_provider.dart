import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String sunlandProviderId = 'sunland';
const String deepSeekProviderId = 'deepseek';
const String sunlandModelId = 'frost';

typedef RemoteAppTokenProvider = Future<String?> Function({bool forceRefresh});

class SunlandRemoteProvider {
  SunlandRemoteProvider({
    required this.tokenProvider,
    Dio? dio,
    this.baseUrl = 'https://ai-core.sunland.dev',
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 30),
             ),
           );

  final RemoteAppTokenProvider tokenProvider;
  final Dio _dio;
  final String baseUrl;
  CancelToken? _activeCancelToken;

  static String _legacyStateSnapshotKey(String userId) =>
      'sunland_remote_legacy_state_$userId';
  static String _legacyConversationsSnapshotKey(String userId) =>
      'sunland_remote_legacy_conversations_$userId';

  bool get isSupported => true;

  Future<SunlandRemoteResponse> send({
    required String userId,
    required String conversationUserId,
    required String conversationId,
    required String input,
    required String turnId,
    String observationMode = 'off',
  }) async {
    if (_normalizeUserId(userId) == null || conversationUserId != userId) {
      throw const SunlandRemoteProviderException('登录状态好像出了点问题，请重新登录后再试一下。');
    }
    final cancelToken = CancelToken();
    _activeCancelToken?.cancel('superseded');
    _activeCancelToken = cancelToken;
    try {
      final migrationWarning = await _ensureLegacyMigration(
        userId,
        cancelToken,
      );
      final data = await _authorizedPost(
        '/v1/turns',
        <String, dynamic>{
          'conversationId': conversationId,
          'turnId': turnId,
          'input': input,
          'observationMode': observationMode == 'summary' ? 'summary' : 'off',
        },
        cancelToken,
        userId,
      );
      final content = data['response']?.toString();
      if (content == null || content.trim().isEmpty) {
        throw const SunlandRemoteProviderException('Sunland AI 返回了无效内容');
      }
      return SunlandRemoteResponse(
        content: content,
        migrationWarning: migrationWarning,
        observationSummary: data['observationSummary'] is Map
            ? Map<String, dynamic>.from(
                (data['observationSummary'] as Map).map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              )
            : null,
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        throw const SunlandRemoteProviderException('请求已取消');
      }
      throw SunlandRemoteProviderException(
        error.response?.statusCode == 429
            ? '请求有点频繁，请稍后再试。'
            : 'Sunland AI 暂时不可用，请稍后重试。',
      );
    } finally {
      if (identical(_activeCancelToken, cancelToken)) _activeCancelToken = null;
    }
  }

  Future<void> deleteConversationContext({
    required String userId,
    required String conversationId,
  }) async {
    final cancelToken = CancelToken();
    await _authorizedDelete(
      '/v1/conversations/${Uri.encodeComponent(conversationId)}/context',
      cancelToken,
      userId,
    );
  }

  Future<List<SunlandKnowledgeRecord>> listKnowledge({
    required String userId,
  }) async {
    try {
      final data = await _authorizedGet(
        '/v1/knowledge',
        userId,
        queryParameters: const <String, dynamic>{'limit': 100},
      );
      final items = data['items'];
      if (items is! List || items.length > 100) {
        throw const FormatException('invalid knowledge response');
      }
      return items.map(SunlandKnowledgeRecord.fromJson).toList(growable: false);
    } on DioException catch (error) {
      throw SunlandRemoteProviderException(
        error.response?.statusCode == 429
            ? '请求有点频繁，请稍后再试。'
            : '暂时无法读取教学知识，请稍后再试。',
      );
    } on SunlandRemoteProviderException {
      rethrow;
    } catch (_) {
      throw const SunlandRemoteProviderException('教学知识数据格式无效');
    }
  }

  Future<void> deleteKnowledge({
    required String userId,
    required String knowledgeId,
  }) {
    final normalizedId = _boundedText(knowledgeId, 128);
    return _deleteUserData(
      '/v1/knowledge/${Uri.encodeComponent(normalizedId)}',
      userId,
    );
  }

  Future<void> deleteAllKnowledge({required String userId}) {
    return _deleteUserData('/v1/knowledge', userId);
  }

  Future<void> deleteRememberedName({required String userId}) {
    return _deleteUserData('/v1/memory/name', userId);
  }

  Future<void> _deleteUserData(String path, String userId) async {
    try {
      await _authorizedDelete(path, CancelToken(), userId);
    } on DioException catch (error) {
      throw SunlandRemoteProviderException(
        error.response?.statusCode == 429
            ? '请求有点频繁，请稍后再试。'
            : '暂时无法完成这个操作，请稍后再试。',
      );
    }
  }

  void cancelCurrent() {
    _activeCancelToken?.cancel('user-cancelled');
    _activeCancelToken = null;
  }

  /// Preserve the old opaque Core and conversation payload before normal app
  /// hydration can rewrite it. This local-only snapshot is removed only after
  /// the server returns the matching migration receipt.
  Future<void> preserveLegacyState(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final marker = prefs.getString('sunland_remote_migration_$userId');
    if (marker != null) {
      try {
        final decoded = jsonDecode(marker);
        if (decoded is Map && decoded['status'] == 'complete') return;
      } catch (_) {}
    }
    final stateKey = 'sunland_core_storage_v1::$userId';
    final conversationsKey = 'conversations_$userId';
    final rawState = prefs.getString(stateKey);
    final rawConversations = prefs.getString(conversationsKey);
    if (rawState != null &&
        !prefs.containsKey(_legacyStateSnapshotKey(userId))) {
      await prefs.setString(_legacyStateSnapshotKey(userId), rawState);
    }
    if (rawConversations != null &&
        !prefs.containsKey(_legacyConversationsSnapshotKey(userId))) {
      await prefs.setString(
        _legacyConversationsSnapshotKey(userId),
        rawConversations,
      );
    }
  }

  Future<Map<String, dynamic>> _authorizedPost(
    String path,
    Map<String, dynamic> body,
    CancelToken cancelToken,
    String expectedUserId,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await tokenProvider(forceRefresh: attempt == 1);
      if (token == null) {
        throw const SunlandRemoteProviderException('登录已过期，请重新登录');
      }
      if (_tokenUserId(token) != expectedUserId) {
        throw const SunlandRemoteProviderException('登录身份已切换，请重新发送');
      }
      try {
        final response = await _dio.post<Map<String, dynamic>>(
          '$baseUrl$path',
          data: body,
          options: Options(
            headers: {
              'authorization': 'Bearer $token',
              'content-type': 'application/json',
            },
          ),
          cancelToken: cancelToken,
        );
        return response.data ?? <String, dynamic>{};
      } on DioException catch (error) {
        if (error.response?.statusCode != 401 || attempt == 1) rethrow;
      }
    }
    throw const SunlandRemoteProviderException('登录已过期，请重新登录');
  }

  Future<Map<String, dynamic>> _authorizedGet(
    String path,
    String expectedUserId, {
    Map<String, dynamic>? queryParameters,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await tokenProvider(forceRefresh: attempt == 1);
      if (token == null) {
        throw const SunlandRemoteProviderException('登录已过期，请重新登录');
      }
      if (_tokenUserId(token) != expectedUserId) {
        throw const SunlandRemoteProviderException('登录身份已切换，请重试');
      }
      try {
        final response = await _dio.get<Map<String, dynamic>>(
          '$baseUrl$path',
          queryParameters: queryParameters,
          options: Options(headers: {'authorization': 'Bearer $token'}),
        );
        return response.data ?? <String, dynamic>{};
      } on DioException catch (error) {
        if (error.response?.statusCode != 401 || attempt == 1) rethrow;
      }
    }
    throw const SunlandRemoteProviderException('登录已过期，请重新登录');
  }

  Future<void> _authorizedDelete(
    String path,
    CancelToken cancelToken,
    String expectedUserId,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await tokenProvider(forceRefresh: attempt == 1);
      if (token == null) {
        throw const SunlandRemoteProviderException('登录已过期，请重新登录');
      }
      if (_tokenUserId(token) != expectedUserId) {
        throw const SunlandRemoteProviderException('登录身份已切换，请重试');
      }
      try {
        await _dio.delete<void>(
          '$baseUrl$path',
          options: Options(headers: {'authorization': 'Bearer $token'}),
          cancelToken: cancelToken,
        );
        return;
      } on DioException catch (error) {
        if (error.response?.statusCode != 401 || attempt == 1) rethrow;
      }
    }
    throw const SunlandRemoteProviderException('登录已过期，请重新登录');
  }

  Future<String?> _ensureLegacyMigration(
    String userId,
    CancelToken cancelToken,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final markerKey = 'sunland_remote_migration_$userId';
    Map<String, dynamic>? marker;
    try {
      final decoded = jsonDecode(prefs.getString(markerKey) ?? 'null');
      if (decoded is Map) marker = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    if (marker?['status'] == 'complete') return null;

    await preserveLegacyState(userId);

    final stateKey = 'sunland_core_storage_v1::$userId';
    final rawState =
        prefs.getString(_legacyStateSnapshotKey(userId)) ??
        prefs.getString(stateKey);
    final rawConversations =
        prefs.getString(_legacyConversationsSnapshotKey(userId)) ??
        prefs.getString('conversations_$userId');
    Map<String, dynamic> state = <String, dynamic>{};
    List<dynamic> conversations = <dynamic>[];
    try {
      if (rawState != null) {
        final decoded = jsonDecode(rawState);
        if (decoded is! Map) throw const FormatException();
        state = Map<String, dynamic>.from(decoded);
      }
      if (rawConversations != null) {
        final decoded = jsonDecode(rawConversations);
        if (decoded is! List) throw const FormatException();
        conversations = decoded;
      }
    } catch (_) {
      return '检测到损坏的旧 Sunland 数据，已保留在本机以便恢复。';
    }

    List<dynamic> decodeRecords(String key) {
      final value = state[key];
      if (value == null) return <dynamic>[];
      final decoded = jsonDecode(value.toString());
      if (decoded is! List) throw const FormatException();
      return decoded;
    }

    final storageKey = 'sunland_knowledge_$userId';
    late final List<dynamic> knowledge;
    late final List<dynamic> memory;
    try {
      knowledge = decodeRecords(storageKey);
      memory = decodeRecords('$storageKey::memory');
    } catch (_) {
      return '检测到损坏的旧 Sunland 数据，已保留在本机以便恢复。';
    }
    final contexts = <Map<String, dynamic>>[];
    for (final value in conversations.whereType<Map>()) {
      final context = value['semanticContext'];
      if (value['provider'] == 'sunland' &&
          context is Map &&
          context['schemaVersion'] == 1 &&
          context['version'] is int) {
        contexts.add(<String, dynamic>{
          'conversationId': value['id'].toString(),
          'context': context,
        });
      }
    }
    final migrationId =
        marker?['migrationId']?.toString() ??
        '${DateTime.now().microsecondsSinceEpoch}-${userId.hashCode.abs()}';
    await prefs.setString(
      markerKey,
      jsonEncode({'migrationId': migrationId, 'status': 'pending'}),
    );
    final receipt = await _authorizedPost(
      '/v1/migrations/local-state',
      {
        'migrationId': migrationId,
        'knowledge': knowledge,
        'memory': memory,
        'contexts': contexts,
      },
      cancelToken,
      userId,
    );
    if (receipt['migrationId'] != migrationId ||
        receipt['status'] != 'complete') {
      throw const SunlandRemoteProviderException('旧数据迁移回执无效，本地数据已保留');
    }
    await prefs.remove(stateKey);
    await prefs.remove(_legacyStateSnapshotKey(userId));
    await prefs.remove(_legacyConversationsSnapshotKey(userId));
    final currentConversations = prefs.getString('conversations_$userId');
    if (currentConversations != null) {
      try {
        final decoded = jsonDecode(currentConversations);
        if (decoded is List) {
          final cleaned = decoded.map((value) {
            if (value is! Map || value['provider'] != 'sunland') return value;
            return Map<String, dynamic>.from(value)..remove('semanticContext');
          }).toList();
          await prefs.setString('conversations_$userId', jsonEncode(cleaned));
        }
      } catch (_) {
        // Keep damaged current data untouched. The successfully imported
        // snapshot has already been accepted by the server.
      }
    }
    await prefs.setString(
      markerKey,
      jsonEncode({'migrationId': migrationId, 'status': 'complete'}),
    );
    return null;
  }

  Future<void> dispose() async {
    cancelCurrent();
    _dio.close(force: true);
  }
}

class SunlandRemoteResponse {
  const SunlandRemoteResponse({
    required this.content,
    this.migrationWarning,
    this.observationSummary,
  });
  final String content;
  final String? migrationWarning;
  final Map<String, dynamic>? observationSummary;
}

class SunlandKnowledgeRecord {
  const SunlandKnowledgeRecord({
    required this.id,
    required this.subject,
    required this.relation,
    required this.object,
    required this.negated,
  });

  final String id;
  final String subject;
  final String relation;
  final String object;
  final bool negated;

  String get label => '$subject ${negated ? '不' : ''}$relation $object';

  factory SunlandKnowledgeRecord.fromJson(Object? value) {
    if (value is! Map || value['negated'] is! bool) {
      throw const FormatException('invalid knowledge record');
    }
    return SunlandKnowledgeRecord(
      id: _boundedText(value['id'], 128),
      subject: _boundedText(value['subject'], 256),
      relation: _boundedText(value['relation'], 128),
      object: _boundedText(value['object'], 512),
      negated: value['negated'] as bool,
    );
  }
}

class SunlandRemoteProviderException implements Exception {
  const SunlandRemoteProviderException(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _normalizeUserId(String value) {
  if (value != value.trim() || value.isEmpty || value.length > 128) return null;
  return RegExp(r'^[A-Za-z0-9][A-Za-z0-9@._+\-]{0,127}$').hasMatch(value)
      ? value
      : null;
}

String _boundedText(Object? value, int maximumLength) {
  if (value is! String ||
      value != value.trim() ||
      value.isEmpty ||
      value.length > maximumLength) {
    throw const FormatException('invalid text');
  }
  return value;
}

String? _tokenUserId(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (value is! Map) return null;
    final userId = (value['id'] ?? value['sub'])?.toString();
    return userId == null ? null : _normalizeUserId(userId);
  } catch (_) {
    return null;
  }
}
