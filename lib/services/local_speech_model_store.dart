import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// SenseVoiceSmall 模型的分发来源。
///
/// 发布方只需修改本类的常量即可把下载切到自有 CDN / 对象存储，无需改动
/// 其他代码：
///
/// ```bash
/// # 实测文件大小
/// curl -sIL "<modelUrl>" | grep -i content-length
/// # 实测 SHA-256
/// curl -sL "<modelUrl>" | shasum -a 256
/// ```
///
/// 默认使用 hf-mirror.com 镜像（国内可达）。模型文件只写入应用私有目录，
/// 不会落到相册、下载目录等公共位置。
abstract final class SenseVoiceModelSource {
  static const String modelFileName = 'model.int8.onnx';
  static const String tokensFileName = 'tokens.txt';

  static final Uri modelUrl = Uri.parse(
    'https://hf-mirror.com/csukuangfj/'
    'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/'
    'model.int8.onnx',
  );

  static final Uri tokensUrl = Uri.parse(
    'https://hf-mirror.com/csukuangfj/'
    'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/'
    'tokens.txt',
  );

  /// TODO(release): 发布前用上面的命令实测并填入。
  ///
  /// 留空表示"未知"，此时下载只做字节数上限与文件可解析性校验，跳过哈希
  /// 比对；填入后启用完整的 SHA-256 完整性校验与损坏自动重下。
  static const String modelSha256 = '';

  /// TODO(release): 同上，int8 模型约 228 MiB。
  static const int modelBytes = 0;

  /// TODO(release): 同上，tokens.txt 约 308 KiB。
  static const String tokensSha256 = '';

  /// TODO(release): 同上。
  static const int tokensBytes = 0;
}

/// 一次下载的进度快照。
@immutable
class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.label,
  });

  final int receivedBytes;

  /// 服务端未提供 Content-Length 时为 0。
  final int totalBytes;
  final String label;

  double? get fraction {
    if (totalBytes <= 0) return null;
    final value = receivedBytes / totalBytes;
    return value.clamp(0.0, 1.0);
  }
}

/// 可取消令牌。取消时 [throwIfCancelled] 抛出 [ModelDownloadCancelledException]。
class ModelDownloadCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw const ModelDownloadCancelledException();
  }
}

class ModelDownloadCancelledException implements Exception {
  const ModelDownloadCancelledException();

  @override
  String toString() => '模型下载已取消';
}

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `HttpClient` 的薄封装，便于在单元测试中替换为假实现。
abstract interface class HttpDownloader {
  Future<HttpDownloadResponse> open(
    Uri uri, {
    int? rangeStart,
    Duration idleTimeout,
  });

  void close();
}

class HttpDownloadResponse {
  const HttpDownloadResponse({required this.statusCode, required this.bytes});

  final int statusCode;
  final Stream<List<int>> bytes;
}

class IoHttpDownloader implements HttpDownloader {
  IoHttpDownloader();

  final HttpClient _client = HttpClient();

  @override
  Future<HttpDownloadResponse> open(
    Uri uri, {
    int? rangeStart,
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    final request = await _client.getUrl(uri);
    request.followRedirects = true;
    request.maxRedirects = 5;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    if (rangeStart != null && rangeStart > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$rangeStart-');
    }
    final response = await request.close();
    return HttpDownloadResponse(
      statusCode: response.statusCode,
      // 空闲超时：连接卡住时不会永远挂起，已下载的 .part 仍可在下次续传。
      bytes: response.timeout(idleTimeout),
    );
  }

  @override
  void close() => _client.close(force: true);
}

/// SenseVoice 模型文件仓储：负责落盘、续传、完整性校验与损坏重下。
///
/// [expectedModelSha256] / [expectedTokensSha256] 为空的字符串表示"未知"，
/// 此时跳过哈希比对（仍会校验文件长度与可读性）。生产默认值来自
/// [SenseVoiceModelSource] 的发布常量；测试可注入以覆盖校验分支。
class SenseVoiceModelStore {
  SenseVoiceModelStore({
    HttpDownloader? downloader,
    Directory? directory,
    String? expectedModelSha256,
    String? expectedTokensSha256,
    int? expectedModelBytes,
    int? expectedTokensBytes,
  }) : _downloader = downloader ?? IoHttpDownloader(),
       _directoryOverride = directory,
       _modelSha256 = expectedModelSha256 ?? SenseVoiceModelSource.modelSha256,
       _tokensSha256 =
           expectedTokensSha256 ?? SenseVoiceModelSource.tokensSha256,
       _modelBytes = expectedModelBytes ?? SenseVoiceModelSource.modelBytes,
       _tokensBytes = expectedTokensBytes ?? SenseVoiceModelSource.tokensBytes;

  static const String modelAssetName = SenseVoiceModelSource.modelFileName;
  static const String tokensAssetName = SenseVoiceModelSource.tokensFileName;

  final HttpDownloader _downloader;
  final Directory? _directoryOverride;
  final String _modelSha256;
  final String _tokensSha256;
  final int _modelBytes;
  final int _tokensBytes;
  Directory? _resolvedDirectory;
  Future<void>? _inFlightEnsure;

  /// 两个文件都已存在且通过校验时为 true。不会触发下载。
  Future<bool> get isReady async {
    final directory = await _resolveDirectory();
    return _isUsable(
          File(_pathOf(directory, modelAssetName, suffix: '')),
          _modelBytes,
        ) &&
        _isUsable(
          File(_pathOf(directory, tokensAssetName, suffix: '')),
          _tokensBytes,
        );
  }

  String? _modelPath;
  String? _tokensPath;

  /// 已就绪的模型绝对路径；未就绪时抛出 [ModelDownloadException]。
  String get modelPath =>
      _modelPath ??
      (throw const ModelDownloadException('语音模型尚未准备完成，请先完成下载'));

  /// 已就绪的 tokens 绝对路径；未就绪时抛出 [ModelDownloadException]。
  String get tokensPath =>
      _tokensPath ??
      (throw const ModelDownloadException('语音模型尚未准备完成，请先完成下载'));

  /// 确保模型可用：缺失则下载，已存在但损坏则重新下载。并发调用会复用同一个请求。
  Future<void> ensureReady({
    void Function(ModelDownloadProgress progress)? onProgress,
    ModelDownloadCancellationToken? cancel,
  }) {
    final existing = _inFlightEnsure;
    if (existing != null) return existing;

    late final Future<void> request;
    request = _ensureReady(onProgress: onProgress, cancel: cancel).whenComplete(
      () {
        if (identical(_inFlightEnsure, request)) _inFlightEnsure = null;
      },
    );
    _inFlightEnsure = request;
    return request;
  }

  Future<void> _ensureReady({
    void Function(ModelDownloadProgress progress)? onProgress,
    ModelDownloadCancellationToken? cancel,
  }) async {
    final directory = await _resolveDirectory();

    final modelFile = File(_pathOf(directory, modelAssetName, suffix: ''));
    final tokensFile = File(_pathOf(directory, tokensAssetName, suffix: ''));

    if (!await _ensureFile(
      target: modelFile,
      uri: SenseVoiceModelSource.modelUrl,
      expectedBytes: _modelBytes,
      expectedSha256: _modelSha256,
      label: '语音模型',
      onProgress: onProgress,
      cancel: cancel,
    )) {
      throw const ModelDownloadException('语音模型下载失败，请检查网络后重试');
    }

    if (!await _ensureFile(
      target: tokensFile,
      uri: SenseVoiceModelSource.tokensUrl,
      expectedBytes: _tokensBytes,
      expectedSha256: _tokensSha256,
      label: '语音词表',
      onProgress: onProgress,
      cancel: cancel,
    )) {
      throw const ModelDownloadException('语音词表下载失败，请检查网络后重试');
    }

    _modelPath = modelFile.path;
    _tokensPath = tokensFile.path;
  }

  /// 销毁网络资源。模型文件保留在磁盘上供下次复用。
  void dispose() => _downloader.close();

  Future<Directory> _resolveDirectory() async {
    final cached = _resolvedDirectory;
    if (cached != null) return cached;

    final base = _directoryOverride ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${base.path}${Platform.pathSeparator}speech_models',
    );
    await directory.create(recursive: true);
    _resolvedDirectory = directory;
    return directory;
  }

  String _pathOf(Directory directory, String fileName, {required String suffix}) {
    return '${directory.path}${Platform.pathSeparator}$fileName$suffix';
  }

  /// 判断文件是否可复用：大小符合预期时才进一步比对哈希。
  bool _isUsable(File file, int expectedBytes) {
    if (!file.existsSync()) return false;
    final length = file.lengthSync();
    if (length <= 0) return false;
    if (expectedBytes > 0 && length != expectedBytes) return false;
    return true;
  }

  /// 返回 true 表示目标文件已就绪；false 表示本次下载失败（不抛异常）。
  Future<bool> _ensureFile({
    required File target,
    required Uri uri,
    required int expectedBytes,
    required String expectedSha256,
    required String label,
    required void Function(ModelDownloadProgress progress)? onProgress,
    required ModelDownloadCancellationToken? cancel,
  }) async {
    cancel?.throwIfCancelled();

    if (_isUsable(target, expectedBytes) &&
        await _matchesDigest(target, expectedSha256)) {
      onProgress?.call(
        ModelDownloadProgress(
          receivedBytes: target.lengthSync(),
          totalBytes: expectedBytes,
          label: label,
        ),
      );
      return true;
    }

    // 已损坏或大小不符：删除后重新下载，绝不使用半成品。
    if (target.existsSync() && !await _matchesDigest(target, expectedSha256)) {
      _deleteQuietly(target);
    }

    return _download(
      target: target,
      uri: uri,
      expectedBytes: expectedBytes,
      expectedSha256: expectedSha256,
      label: label,
      onProgress: onProgress,
      cancel: cancel,
    );
  }

  Future<bool> _download({
    required File target,
    required Uri uri,
    required int expectedBytes,
    required String expectedSha256,
    required String label,
    required void Function(ModelDownloadProgress progress)? onProgress,
    required ModelDownloadCancellationToken? cancel,
  }) async {
    final partial = File('${target.path}.part');
    var received = 0;
    IOSink? sink;
    var resumed = false;

    try {
      if (partial.existsSync()) {
        received = partial.lengthSync();
        if (expectedBytes > 0 && received >= expectedBytes) {
          // 上次留下的数据已经不比目标小，续传没有意义，直接重来。
          _deleteQuietly(partial);
          received = 0;
        }
      }

      final response = await _downloader.open(
        uri,
        rangeStart: received > 0 ? received : null,
      );

      if (received > 0 && response.statusCode == HttpStatus.partialContent) {
        resumed = true;
      } else if (response.statusCode == HttpStatus.ok) {
        // 服务端不支持 Range，必须从零开始，丢弃已有的 .part。
        _deleteQuietly(partial);
        received = 0;
      } else if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      sink = partial.openWrite(
        mode: resumed ? FileMode.append : FileMode.write,
      );

      final digest = _DigestAccumulator();
      if (resumed) {
        // 续传：先把磁盘上已有的片段喂给哈希，保证最终摘要覆盖完整文件。
        digest.seedFrom(partial);
      }

      await for (final chunk in response.bytes) {
        cancel?.throwIfCancelled();
        if (chunk.isEmpty) continue;
        sink.add(chunk);
        digest.add(chunk);
        received += chunk.length;
        if (expectedBytes > 0 && received > expectedBytes) {
          throw const ModelDownloadException('下载数据超过预期大小，已中止');
        }
        onProgress?.call(
          ModelDownloadProgress(
            receivedBytes: received,
            totalBytes: expectedBytes,
            label: label,
          ),
        );
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (received <= 0) return false;
      if (expectedBytes > 0 && received != expectedBytes) {
        throw const ModelDownloadException('下载未完成，请重试');
      }

      if (expectedSha256.isNotEmpty) {
        final actual = digest.finish();
        if (!_digestEquals(actual, expectedSha256)) {
          throw const ModelDownloadException('模型校验失败，请重试');
        }
      }

      // 校验通过后才原子替换正式文件。
      if (target.existsSync()) _deleteQuietly(target);
      await partial.rename(target.path);
      return true;
    } on ModelDownloadCancelledException {
      // 取消：保留 .part 供下次续传，不写入半成品。
      await _closeQuietly(sink);
      rethrow;
    } catch (error) {
      debugPrint('SenseVoice 模型下载失败（$label）：$error');
      await _closeQuietly(sink);
      // 保留 .part，下次可续传。
      return false;
    }
  }

  Future<void> _closeQuietly(IOSink? sink) async {
    if (sink == null) return;
    try {
      await sink.close();
    } catch (_) {
      // 关闭失败不影响状态恢复。
    }
  }

  Future<bool> _matchesDigest(File file, String expectedSha256) async {
    if (expectedSha256.isEmpty) return true;
    if (!file.existsSync()) return false;
    final actual = await sha256.bind(file.openRead()).first;
    return _digestEquals(actual, expectedSha256);
  }

  bool _digestEquals(Digest digest, String expected) =>
      digest.toString().toLowerCase() == expected.trim().toLowerCase();

  void _deleteQuietly(FileSystemEntity entity) {
    try {
      if (entity.existsSync()) entity.deleteSync();
    } on FileSystemException {
      // 删除失败会在后续校验中被重新识别为损坏文件。
    }
  }
}

/// 增量 SHA-256 摘要器。支持先从已有 `.part` 片段续算，再继续喂新下载的数据。
class _DigestAccumulator {
  _DigestAccumulator() {
    _output = sha256.startChunkedConversion(_sink);
  }

  static const int _seedChunkBytes = 256 * 1024;

  final _DigestSink _sink = _DigestSink();
  late final ByteConversionSink _output;
  bool _finished = false;

  void add(List<int> chunk) {
    if (_finished || chunk.isEmpty) return;
    _output.add(chunk);
  }

  /// 分块读取 [source] 的全部内容并计入摘要，避免把 228 MiB 一次性读进内存。
  void seedFrom(File source) {
    final handle = source.openSync();
    try {
      while (true) {
        final chunk = handle.readSync(_seedChunkBytes);
        if (chunk.isEmpty) break;
        add(chunk);
      }
    } finally {
      handle.closeSync();
    }
  }

  Digest finish() {
    if (!_finished) {
      _finished = true;
      _output.close();
    }
    return _sink.value;
  }
}

/// [Hash.startChunkedConversion] 需要一个只接收一次结果的 sink。
class _DigestSink implements Sink<Digest> {
  Digest? _digest;

  Digest get value =>
      _digest ?? (throw StateError('SHA-256 摘要尚未生成'));

  @override
  void add(Digest value) => _digest = value;

  @override
  void close() {}
}
