import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Flutter 业务层与 Sunland Core 之间的稳定调用边界。
///
/// Core 状态与上下文在 Dart 中均视为不透明数据。替换 JavaScript 执行容器时，
/// 只需实现本接口，无需修改 Provider 或 UI。
abstract interface class SunlandCoreClient {
  bool get isSupported;

  /// 可重复调用；实现必须复用已启动的 Core。
  Future<void> boot();

  Future<void> initializeNamespace({
    required String namespace,
    required Map<String, String> stateSnapshot,
  });

  Future<SunlandCoreResult> send(SunlandCoreRequest request);

  Future<void> dispose();
}

class SunlandCoreRequest {
  const SunlandCoreRequest({
    required this.namespace,
    required this.input,
    required this.requestId,
    required this.contextSnapshot,
  });

  final String namespace;
  final String input;
  final String requestId;

  /// 结构由 Core 拥有，Client 只做不透明传输。
  final Object? contextSnapshot;
}

class SunlandCoreResult {
  const SunlandCoreResult({
    required this.content,
    required this.stateSnapshot,
    required this.contextSnapshot,
  });

  final String content;
  final Map<String, String> stateSnapshot;
  final Map<String, dynamic> contextSnapshot;
}

class SunlandCoreClientException implements Exception {
  const SunlandCoreClientException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Core 状态快照的宿主持久化端口。
///
/// 快照内容由 Core 产生，Store 只按命名空间保存字符串键值，不理解其内容。
abstract interface class SunlandCoreStateStore {
  Future<Map<String, String>> read(String namespace);

  Future<void> write(String namespace, Map<String, String> stateSnapshot);
}

class SunlandCoreReleaseManifest {
  const SunlandCoreReleaseManifest({
    required this.schemaVersion,
    required this.artifact,
    required this.version,
    required this.algorithm,
    required this.sha256,
    required this.bytes,
  });

  final int schemaVersion;
  final String artifact;
  final String version;
  final String algorithm;
  final String sha256;
  final int bytes;

  static SunlandCoreReleaseManifest? tryParse(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map ||
          decoded['schemaVersion'] is! int ||
          decoded['artifact'] is! String ||
          decoded['version'] is! String ||
          decoded['algorithm'] is! String ||
          decoded['sha256'] is! String ||
          decoded['bytes'] is! int) {
        return null;
      }
      final manifest = SunlandCoreReleaseManifest(
        schemaVersion: decoded['schemaVersion'] as int,
        artifact: decoded['artifact'] as String,
        version: decoded['version'] as String,
        algorithm: decoded['algorithm'] as String,
        sha256: decoded['sha256'] as String,
        bytes: decoded['bytes'] as int,
      );
      if (manifest.schemaVersion != 1 ||
          manifest.artifact.isEmpty ||
          manifest.version.isEmpty ||
          manifest.algorithm != 'SHA-256' ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(manifest.sha256) ||
          manifest.bytes < 0) {
        return null;
      }
      return manifest;
    } catch (_) {
      return null;
    }
  }
}

class SunlandCoreIntegrityIssue {
  const SunlandCoreIntegrityIssue({
    required this.code,
    required this.asset,
    this.expected,
    this.actual,
  });

  final String code;
  final String asset;
  final String? expected;
  final String? actual;

  /// 字段固定且不接受账户或会话数据，避免完整性日志携带用户身份信息。
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'event': 'sunland_core_integrity_failure',
      'code': code,
      'asset': asset,
      'expected': expected,
      'actual': actual,
    };
  }
}

typedef SunlandCoreIntegrityReporter =
    void Function(SunlandCoreIntegrityIssue issue);

class SunlandCoreIntegrityVerifier {
  const SunlandCoreIntegrityVerifier();

  SunlandCoreReleaseManifest? verifyBundle({
    required Uint8List bundleBytes,
    required String bundleAsset,
    required String manifestSource,
    required SunlandCoreIntegrityReporter report,
  }) {
    final manifest = SunlandCoreReleaseManifest.tryParse(manifestSource);
    if (manifest == null) {
      report(
        SunlandCoreIntegrityIssue(code: 'manifest_invalid', asset: bundleAsset),
      );
      return null;
    }

    final expectedArtifact = bundleAsset.split('/').last;
    if (manifest.artifact != expectedArtifact) {
      report(
        SunlandCoreIntegrityIssue(
          code: 'artifact_mismatch',
          asset: bundleAsset,
          expected: expectedArtifact,
          actual: manifest.artifact,
        ),
      );
    }
    if (manifest.bytes != bundleBytes.lengthInBytes) {
      report(
        SunlandCoreIntegrityIssue(
          code: 'size_mismatch',
          asset: bundleAsset,
          expected: manifest.bytes.toString(),
          actual: bundleBytes.lengthInBytes.toString(),
        ),
      );
    }
    final actualHash = sha256.convert(bundleBytes).toString();
    if (manifest.sha256 != actualHash) {
      report(
        SunlandCoreIntegrityIssue(
          code: 'hash_mismatch',
          asset: bundleAsset,
          expected: manifest.sha256,
          actual: actualHash,
        ),
      );
    }
    return manifest;
  }

  void verifyRuntimeVersion({
    required SunlandCoreReleaseManifest manifest,
    required String runtimeVersion,
    required String bundleAsset,
    required SunlandCoreIntegrityReporter report,
  }) {
    if (runtimeVersion != manifest.version) {
      report(
        SunlandCoreIntegrityIssue(
          code: 'version_mismatch',
          asset: bundleAsset,
          expected: manifest.version,
          actual: runtimeVersion,
        ),
      );
    }
  }
}
