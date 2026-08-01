import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sunland_core_client.dart';
import 'sunland_webview_runtime_adapter.dart';

const String sunlandProviderId = 'sunland';
const String deepSeekProviderId = 'deepseek';
const String sunlandModelId = 'frost';

class SunlandLocalProviderException implements Exception {
  const SunlandLocalProviderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SunlandLocalResponse {
  const SunlandLocalResponse({
    required this.content,
    required this.contextSnapshot,
  });

  final String content;
  final Map<String, dynamic> contextSnapshot;
}

/// Sunland 的 Flutter 应用层入口。
///
/// 本类只负责用户边界、状态快照持久化和不透明上下文的转交。
/// 所有 AI 业务均由 Client 执行的同一份 JS Core 提供。
class SunlandLocalProvider {
  SunlandLocalProvider({
    SunlandCoreClient? client,
    SunlandCoreStateStore? stateStore,
  }) : _client = client ?? WebViewSunlandCoreClient(),
       _stateStore = stateStore ?? SharedPreferencesSunlandCoreStateStore();

  final SunlandCoreClient _client;
  final SunlandCoreStateStore _stateStore;
  final Set<String> _initializedNamespaces = <String>{};

  bool get isSupported => _client.isSupported;

  Future<SunlandLocalResponse> send({
    required String userId,
    required String conversationUserId,
    required String input,
    required String turnId,
    required Object? contextSnapshot,
  }) async {
    final normalizedUserId = _normalizeUserId(userId);
    final normalizedOwnerId = _normalizeUserId(conversationUserId);
    if (normalizedUserId == null || normalizedOwnerId != normalizedUserId) {
      throw const SunlandLocalProviderException('登录状态好像出了点问题，请重新登录后再试一下。');
    }
    if (!isSupported) {
      throw const SunlandLocalProviderException(
        '当前平台暂不支持本地 Sunland AI，请在 Android、iOS 或 macOS 端使用。',
      );
    }

    try {
      await _client.boot();
      await _initializeNamespace(normalizedUserId);
      final result = await _client.send(
        SunlandCoreRequest(
          namespace: normalizedUserId,
          input: input,
          requestId: turnId,
          contextSnapshot: contextSnapshot,
        ),
      );
      await _stateStore.write(normalizedUserId, result.stateSnapshot);
      return SunlandLocalResponse(
        content: result.content,
        contextSnapshot: result.contextSnapshot,
      );
    } on SunlandCoreClientException catch (error) {
      throw SunlandLocalProviderException(error.message);
    }
  }

  Future<void> _initializeNamespace(String namespace) async {
    if (_initializedNamespaces.contains(namespace)) return;
    final stateSnapshot = await _stateStore.read(namespace);
    await _client.initializeNamespace(
      namespace: namespace,
      stateSnapshot: stateSnapshot,
    );
    _initializedNamespaces.add(namespace);
  }

  Future<void> dispose() async {
    _initializedNamespaces.clear();
    await _client.dispose();
  }
}

class SharedPreferencesSunlandCoreStateStore implements SunlandCoreStateStore {
  static const String _storagePrefix = 'sunland_core_storage_v1::';

  @override
  Future<Map<String, String>> read(String namespace) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_storagePrefix$namespace');
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      final storage = <String, String>{};
      decoded.forEach((key, value) {
        if (value is String) storage[key.toString()] = value;
      });
      return storage;
    } catch (_) {
      return <String, String>{};
    }
  }

  @override
  Future<void> write(
    String namespace,
    Map<String, String> stateSnapshot,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_storagePrefix$namespace',
      jsonEncode(stateSnapshot),
    );
  }
}

String? _normalizeUserId(String value) {
  if (value != value.trim() || value.isEmpty || value.length > 128) return null;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9@._+\-]{0,127}$').hasMatch(value)) {
    return null;
  }
  const reserved = {'anonymous', 'default', 'guest', 'null', 'undefined'};
  return reserved.contains(value.toLowerCase()) ? null : value;
}
