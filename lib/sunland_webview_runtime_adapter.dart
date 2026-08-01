import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'sunland_core_client.dart';

/// 当前的 Sunland JS 运行时实现。
///
/// WebView 仅作为不可见的 JavaScript 执行容器。桥接代码只创建 Core、传递
/// 输入和导出 Core 产生的状态，不包含 Semantic、Reasoner、Knowledge、
/// Memory 业务规则。
class WebViewSunlandCoreClient implements SunlandCoreClient {
  WebViewSunlandCoreClient({
    this.bundleAsset = 'assets/sunland-core.js',
    this.manifestAsset = 'assets/sunland-core.manifest.json',
    SunlandCoreIntegrityReporter? integrityReporter,
  }) : _integrityReporter = integrityReporter ?? _reportIntegrityIssue;

  final String bundleAsset;
  final String manifestAsset;
  final SunlandCoreIntegrityReporter _integrityReporter;
  final SunlandCoreIntegrityVerifier _integrityVerifier =
      const SunlandCoreIntegrityVerifier();
  WebViewController? _controller;
  Future<void>? _bootFuture;

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  bool get isSupported => isPlatformSupported;

  @override
  Future<void> boot() async {
    if (!isSupported) {
      throw const SunlandCoreClientException(
        '当前平台暂不支持本地 Sunland AI，请在 Android、iOS 或 macOS 端使用。',
      );
    }

    final running = _bootFuture ??= _createRuntime();
    try {
      await running;
    } catch (_) {
      if (identical(_bootFuture, running)) {
        _bootFuture = null;
        _controller = null;
      }
      rethrow;
    }
  }

  Future<void> _createRuntime() async {
    final bundleData = await rootBundle.load(bundleAsset);
    final bundleBytes = bundleData.buffer.asUint8List(
      bundleData.offsetInBytes,
      bundleData.lengthInBytes,
    );
    final bundle = utf8.decode(bundleBytes);
    final manifest = await _verifyBundle(bundleBytes);
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    _controller = controller;

    final html =
        '''
<!doctype html>
<html>
<head><meta charset="utf-8"></head>
<body>
<script>
window.__sunlandReady = false;
window.__sunlandBootError = '';
window.__sunlandCore = null;
window.__sunlandEngines = new Map();
window.__sunlandStores = new Map();

window.__sunlandBridge = {
  metadata() {
    return JSON.stringify({
      ok: true,
      version: String(window.__sunlandCore && window.__sunlandCore.SUNLAND_CORE_VERSION || '')
    });
  },

  initialize(request) {
    try {
      const userId = String(request && request.userId || '');
      if (!userId || !window.__sunlandCore) {
        return JSON.stringify({ ok: false, error: 'Sunland Core 尚未就绪' });
      }
      if (window.__sunlandEngines.has(userId)) {
        return JSON.stringify({ ok: true });
      }
      const entries = Object.entries(request.storage || {})
        .filter(([key, value]) => typeof key === 'string' && typeof value === 'string');
      const store = new Map(entries);
      const adapter = {
        getItem(key) { return store.has(key) ? store.get(key) : null; },
        setItem(key, value) { store.set(String(key), String(value)); },
        removeItem(key) { store.delete(String(key)); }
      };
      const engine = window.__sunlandCore.createSunlandEngine({
        storage: { adapter, key: 'sunland_knowledge_' + userId },
        semanticMode: 'passive',
        semanticDebug: false,
        semanticContextMode: 'enabled'
      });
      window.__sunlandStores.set(userId, store);
      window.__sunlandEngines.set(userId, engine);
      return JSON.stringify({ ok: true });
    } catch (error) {
      return JSON.stringify({ ok: false, error: String(error && error.message || error) });
    }
  },

  process(request) {
    try {
      const userId = String(request && request.userId || '');
      const engine = window.__sunlandEngines.get(userId);
      const store = window.__sunlandStores.get(userId);
      if (!engine || !store) {
        return JSON.stringify({ ok: false, error: 'Sunland 用户引擎尚未初始化' });
      }
      const semanticContext = window.__sunlandCore.normalizeSemanticContext(
        request.semanticContext
      );
      const processed = engine.process(String(request.input || ''), {
        semanticContext,
        turnId: String(request.turnId || ''),
        observationMode: 'off',
        canCommitSemanticContext: () => true
      });
      const nextSemanticContext = window.__sunlandCore.applySemanticContextUpdate(
        semanticContext,
        processed.semanticContextUpdate
      );
      return JSON.stringify({
        ok: true,
        content: processed.response,
        semanticContext: nextSemanticContext,
        storage: Object.fromEntries(store)
      });
    } catch (error) {
      return JSON.stringify({ ok: false, error: String(error && error.message || error) });
    }
  }
};

(async () => {
  try {
    const source = ${jsonEncode(bundle)};
    const url = URL.createObjectURL(new Blob([source], { type: 'text/javascript' }));
    window.__sunlandCore = await import(url);
    URL.revokeObjectURL(url);
    window.__sunlandReady = true;
  } catch (error) {
    window.__sunlandBootError = String(error && error.message || error);
  }
})();
</script>
</body>
</html>
''';

    await controller.loadHtmlString(html);
    for (var attempt = 0; attempt < 100; attempt += 1) {
      final ready = await controller.runJavaScriptReturningResult(
        'window.__sunlandReady === true',
      );
      if (ready == true || ready.toString() == 'true') {
        await _verifyRuntimeVersion(manifest);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final rawError = await controller.runJavaScriptReturningResult(
      'window.__sunlandBootError || "Sunland Core 初始化超时"',
    );
    throw SunlandCoreClientException(rawError.toString());
  }

  Future<SunlandCoreReleaseManifest?> _verifyBundle(
    Uint8List bundleBytes,
  ) async {
    try {
      final manifestSource = await rootBundle.loadString(manifestAsset);
      return _integrityVerifier.verifyBundle(
        bundleBytes: bundleBytes,
        bundleAsset: bundleAsset,
        manifestSource: manifestSource,
        report: _integrityReporter,
      );
    } catch (_) {
      _integrityReporter(
        SunlandCoreIntegrityIssue(
          code: 'manifest_unavailable',
          asset: manifestAsset,
        ),
      );
      return null;
    }
  }

  Future<void> _verifyRuntimeVersion(
    SunlandCoreReleaseManifest? manifest,
  ) async {
    if (manifest == null) return;
    try {
      final raw = await _controller!.runJavaScriptReturningResult(
        'window.__sunlandBridge.metadata()',
      );
      final result = _decodeBridgeResult(raw);
      if (result['ok'] != true) throw const FormatException();
      _integrityVerifier.verifyRuntimeVersion(
        manifest: manifest,
        runtimeVersion: (result['version'] ?? '').toString(),
        bundleAsset: bundleAsset,
        report: _integrityReporter,
      );
    } catch (_) {
      _integrityReporter(
        SunlandCoreIntegrityIssue(
          code: 'runtime_version_unavailable',
          asset: bundleAsset,
        ),
      );
    }
  }

  @override
  Future<void> initializeNamespace({
    required String namespace,
    required Map<String, String> stateSnapshot,
  }) async {
    await boot();
    final request = <String, dynamic>{
      'userId': namespace,
      'storage': stateSnapshot,
    };
    final raw = await _controller!.runJavaScriptReturningResult(
      'window.__sunlandBridge.initialize(${jsonEncode(request)})',
    );
    final result = _decodeBridgeResult(raw);
    if (result['ok'] != true) {
      throw SunlandCoreClientException(
        (result['error'] ?? 'Sunland 用户引擎初始化失败').toString(),
      );
    }
  }

  @override
  Future<SunlandCoreResult> send(SunlandCoreRequest request) async {
    await boot();
    final payload = <String, dynamic>{
      'userId': request.namespace,
      'input': request.input,
      'turnId': request.requestId,
      'semanticContext': request.contextSnapshot,
    };
    final raw = await _controller!
        .runJavaScriptReturningResult(
          'window.__sunlandBridge.process(${jsonEncode(payload)})',
        )
        .timeout(const Duration(seconds: 8));
    final result = _decodeBridgeResult(raw);
    if (result['ok'] != true) {
      throw SunlandCoreClientException(
        (result['error'] ?? 'Sunland AI 暂时出了点问题，请稍后重试').toString(),
      );
    }

    final storage = <String, String>{};
    final rawStorage = result['storage'];
    if (rawStorage is Map) {
      rawStorage.forEach((key, value) {
        if (value is String) storage[key.toString()] = value;
      });
    }
    final rawSemanticContext = result['semanticContext'];
    if (rawSemanticContext is! Map) {
      throw const SunlandCoreClientException('Sunland Core 未返回有效的上下文快照');
    }
    return SunlandCoreResult(
      content: (result['content'] ?? '').toString(),
      stateSnapshot: storage,
      contextSnapshot: Map<String, dynamic>.from(
        rawSemanticContext.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }

  @override
  Future<void> dispose() async {
    _controller = null;
    _bootFuture = null;
  }
}

Map<String, dynamic> _decodeBridgeResult(Object raw) {
  dynamic value = raw;
  for (var attempt = 0; attempt < 2 && value is String; attempt += 1) {
    try {
      value = jsonDecode(value);
    } catch (_) {
      break;
    }
  }
  if (value is Map) {
    return Map<String, dynamic>.from(
      value.map((key, item) => MapEntry(key.toString(), item)),
    );
  }
  throw const SunlandCoreClientException('Sunland Core 返回了无法识别的数据');
}

void _reportIntegrityIssue(SunlandCoreIntegrityIssue issue) {
  final structuredError = jsonEncode(issue.toJson());
  developer.log(structuredError, name: 'sunland.core.integrity', level: 1000);
  if (kDebugMode) {
    debugPrint('Sunland Core 完整性警告：$structuredError');
  }
}
