import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/local_speech_model_store.dart';

/// 按 URL 返回固定内容的假下载器，用于验证落盘、续传与校验逻辑。
///
/// `ensureReady` 会下载 model 与 tokens 两个文件，因此这里必须按 URL 分别
/// 返回内容，否则两个文件会互相覆盖、断言失真。
class _FakeDownloader implements HttpDownloader {
  _FakeDownloader({
    List<int>? payload,
    this.supportsRange = true,
    this.failAfterBytes,
    this.statusCode = 200,
  }) : payload = payload ?? const <int>[];

  /// tokens.txt 固定返回这个短载荷（内容为 "tokens"）。
  static const List<int> tokensBytes = <int>[116, 111, 107, 101, 110, 115];

  final List<int> payload;
  final bool supportsRange;

  /// model 传输到该字节数后中断连接，模拟下载中断。
  final int? failAfterBytes;
  final int statusCode;

  int openCalls = 0;
  int modelOpenCalls = 0;
  int? lastModelRangeStart;
  bool closed = false;

  bool _isTokens(Uri uri) => uri.path.endsWith('tokens.txt');

  @override
  Future<HttpDownloadResponse> open(
    Uri uri, {
    int? rangeStart,
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    openCalls++;
    final tokens = _isTokens(uri);
    if (!tokens) {
      modelOpenCalls++;
      lastModelRangeStart = rangeStart;
    }

    if (statusCode != 200) {
      return HttpDownloadResponse(
        statusCode: statusCode,
        bytes: const Stream<List<int>>.empty(),
      );
    }

    final bytes = tokens ? tokensBytes : payload;
    // 只让 model 下载可中断，tokens 始终完整，便于单独断言 model 的续传行为。
    final failAt = tokens ? null : failAfterBytes;

    if (rangeStart != null && rangeStart > 0 && supportsRange) {
      return HttpDownloadResponse(
        statusCode: 206,
        bytes: _stream(bytes, rangeStart, failAt),
      );
    }
    return HttpDownloadResponse(
      statusCode: 200,
      bytes: _stream(bytes, 0, failAt),
    );
  }

  Stream<List<int>> _stream(List<int> bytes, int from, int? failAt) async* {
    const chunkSize = 512;
    var sent = 0;
    for (var offset = from; offset < bytes.length; offset += chunkSize) {
      final end = (offset + chunkSize).clamp(0, bytes.length);
      final chunk = bytes.sublist(offset, end);
      if (failAt != null && sent + chunk.length > failAt) {
        throw const SocketException('模拟网络中断');
      }
      sent += chunk.length;
      yield chunk;
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  void close() => closed = true;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('speech_model_store_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // 模型只写入传入目录下的 speech_models 子目录，不落公共目录。
  Directory modelDir() =>
      Directory('${tempDir.path}${Platform.pathSeparator}speech_models');

  String inDir(Directory dir, String name) =>
      '${dir.path}${Platform.pathSeparator}$name';

  File modelFile() =>
      File(inDir(modelDir(), SenseVoiceModelSource.modelFileName));

  File tokensFile() =>
      File(inDir(modelDir(), SenseVoiceModelSource.tokensFileName));

  File modelPartFile() => File('${modelFile().path}.part');

  test('默认模型来源使用 HTTPS 且文件名稳定', () {
    expect(SenseVoiceModelSource.modelUrl.scheme, 'https');
    expect(SenseVoiceModelSource.tokensUrl.scheme, 'https');
    expect(SenseVoiceModelSource.modelUrl.path, endsWith('model.int8.onnx'));
    expect(SenseVoiceModelSource.tokensUrl.path, endsWith('tokens.txt'));
  });

  test('下载成功后写入正式文件，不残留 .part', () async {
    final payload = List<int>.generate(4096, (index) => index % 251);
    final downloader = _FakeDownloader(payload: payload);
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
    );

    final progress = <ModelDownloadProgress>[];
    await store.ensureReady(onProgress: progress.add);

    expect(modelFile().existsSync(), isTrue);
    expect(modelFile().readAsBytesSync(), payload);
    expect(tokensFile().existsSync(), isTrue);
    expect(tokensFile().readAsBytesSync(), _FakeDownloader.tokensBytes);
    expect(modelPartFile().existsSync(), isFalse);
    expect(progress, isNotEmpty);
    expect(progress.last.receivedBytes, greaterThan(0));
    store.dispose();
  });

  test('模型落在应用私有目录的 speech_models 子目录中', () async {
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: const [1, 2, 3, 4]),
      directory: tempDir,
    );
    await store.ensureReady();

    expect(store.modelPath, contains('speech_models'));
    expect(store.tokensPath, contains('speech_models'));
    expect(
      store.modelPath.startsWith(tempDir.path),
      isTrue,
      reason: '不得写入公共目录，必须位于传入的应用私有目录下',
    );
    store.dispose();
  });

  test('已就绪时不重复下载', () async {
    final downloader = _FakeDownloader(
      payload: List<int>.generate(2048, (index) => index % 97),
    );
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
    );

    await store.ensureReady();
    expect(downloader.openCalls, 2);
    expect(downloader.modelOpenCalls, 1);

    await store.ensureReady();
    // 复用已通过校验的文件，不再发起新的请求。
    expect(downloader.openCalls, 2);
    store.dispose();
  });

  test('下载中断时保留 .part 并在下次续传', () async {
    final payload = List<int>.generate(8192, (index) => index % 233);
    final failing = _FakeDownloader(payload: payload, failAfterBytes: 1024);
    final store = SenseVoiceModelStore(
      downloader: failing,
      directory: tempDir,
    );

    await expectLater(
      store.ensureReady(),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(modelPartFile().existsSync(), isTrue);
    final partialLength = modelPartFile().lengthSync();
    expect(partialLength, greaterThan(0));
    expect(modelFile().existsSync(), isFalse);

    // 第二次换成正常下载器，校验续传起点与最终内容。
    final healthy = _FakeDownloader(payload: payload);
    final resumedStore = SenseVoiceModelStore(
      downloader: healthy,
      directory: tempDir,
    );
    await resumedStore.ensureReady();

    expect(healthy.lastModelRangeStart, partialLength);
    expect(modelFile().readAsBytesSync(), payload);
    expect(modelPartFile().existsSync(), isFalse);
    store.dispose();
    resumedStore.dispose();
  });

  test('服务端不支持 Range 时丢弃半成品并重新下载', () async {
    final payload = List<int>.generate(4096, (index) => index % 199);
    await modelPartFile().create(recursive: true);
    await modelPartFile().writeAsBytes(payload.sublist(0, 512));

    final downloader = _FakeDownloader(payload: payload, supportsRange: false);
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
    );
    await store.ensureReady();

    expect(modelFile().readAsBytesSync(), payload);
    store.dispose();
  });

  test('HTTP 非 200 时抛出可读错误且不写入正式文件', () async {
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: const [], statusCode: 404),
      directory: tempDir,
    );

    await expectLater(
      store.ensureReady(),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(modelFile().existsSync(), isFalse);
    store.dispose();
  });

  test('取消下载时保留 .part 并抛出取消异常', () async {
    final payload = List<int>.generate(64 * 1024, (index) => index % 211);
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: payload),
      directory: tempDir,
    );
    final token = ModelDownloadCancellationToken();

    final pending = store.ensureReady(cancel: token);
    unawaited(Future<void>.delayed(Duration.zero, token.cancel));

    await expectLater(pending, throwsA(isA<ModelDownloadCancelledException>()));
    expect(modelFile().existsSync(), isFalse);
    store.dispose();
  });

  test('字节数超过预期时中止且不入库', () async {
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(
        payload: List<int>.generate(4096, (index) => index % 71),
      ),
      directory: tempDir,
      expectedModelBytes: 1024,
      expectedTokensBytes: _FakeDownloader.tokensBytes.length,
    );

    await expectLater(
      store.ensureReady(),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(modelFile().existsSync(), isFalse);
    store.dispose();
  });

  test('字节数不足时判定为不完整且不入库', () async {
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: const [1, 2, 3, 4]),
      directory: tempDir,
      expectedModelBytes: 4096,
      expectedTokensBytes: _FakeDownloader.tokensBytes.length,
    );

    await expectLater(
      store.ensureReady(),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(modelFile().existsSync(), isFalse);
    store.dispose();
  });

  test('长度不符的已有文件会被重新下载', () async {
    final payload = List<int>.generate(2048, (index) => index % 89);
    await modelFile().create(recursive: true);
    await modelFile().writeAsBytes(List<int>.filled(64, 7));

    final downloader = _FakeDownloader(payload: payload);
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
      expectedModelBytes: payload.length,
      expectedTokensBytes: _FakeDownloader.tokensBytes.length,
    );
    await store.ensureReady();

    expect(modelFile().readAsBytesSync(), payload);
    expect(downloader.modelOpenCalls, 1);
    store.dispose();
  });

  test('isReady 反映两个文件是否都已就绪', () async {
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: const [1, 2, 3, 4]),
      directory: tempDir,
    );
    expect(await store.isReady, isFalse);
    await store.ensureReady();
    expect(await store.isReady, isTrue);
    store.dispose();
  });

  test('未就绪时访问路径抛出可读错误', () {
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: const []),
      directory: tempDir,
    );
    expect(() => store.modelPath, throwsA(isA<ModelDownloadException>()));
    expect(() => store.tokensPath, throwsA(isA<ModelDownloadException>()));
    store.dispose();
  });

  test('哈希不匹配时不写入正式文件', () async {
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: List<int>.filled(2048, 3)),
      directory: tempDir,
      expectedModelSha256: _sha256Of(const [9, 9, 9, 9]),
      expectedTokensSha256: _sha256Of(_FakeDownloader.tokensBytes),
    );

    await expectLater(
      store.ensureReady(),
      throwsA(isA<ModelDownloadException>()),
    );
    expect(modelFile().existsSync(), isFalse);
    store.dispose();
  });

  test('哈希匹配时正常落盘', () async {
    final payload = List<int>.generate(2048, (index) => index % 89);
    final downloader = _FakeDownloader(payload: payload);
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
      expectedModelSha256: _sha256Of(payload),
      expectedTokensSha256: _sha256Of(_FakeDownloader.tokensBytes),
    );

    await store.ensureReady();
    expect(modelFile().readAsBytesSync(), payload);
    expect(downloader.modelOpenCalls, 1);
    store.dispose();
  });

  test('已存在但内容损坏的文件会被删除并重新下载', () async {
    await modelFile().create(recursive: true);
    await modelFile().writeAsBytes(List<int>.filled(2048, 1));

    final payload = List<int>.generate(2048, (index) => index % 89);
    final downloader = _FakeDownloader(payload: payload);
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
      expectedModelSha256: _sha256Of(payload),
      expectedTokensSha256: _sha256Of(_FakeDownloader.tokensBytes),
    );

    await store.ensureReady();
    expect(downloader.modelOpenCalls, 1);
    expect(modelFile().readAsBytesSync(), payload);
    store.dispose();
  });

  test('进度回调带标签并可换算百分比', () {
    const progress = ModelDownloadProgress(
      receivedBytes: 50,
      totalBytes: 200,
      label: '语音模型',
    );
    expect(progress.fraction, 0.25);
    expect(progress.label, '语音模型');
    const unknownTotal = ModelDownloadProgress(
      receivedBytes: 50,
      totalBytes: 0,
      label: '语音模型',
    );
    expect(unknownTotal.fraction, isNull);
  });

  test('取消令牌在被取消后立即抛错', () {
    final token = ModelDownloadCancellationToken();
    expect(token.isCancelled, isFalse);
    token.throwIfCancelled();
    token.cancel();
    expect(token.isCancelled, isTrue);
    expect(
      token.throwIfCancelled,
      throwsA(isA<ModelDownloadCancelledException>()),
    );
  });

  test('close 会释放底层下载器', () {
    final downloader = _FakeDownloader(payload: const [1]);
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
    );
    store.dispose();
    expect(downloader.closed, isTrue);
  });

  test('字节内容按原样保存（不会因解码破坏二进制）', () async {
    final payload = Uint8List.fromList(
      List<int>.generate(4096, (index) => (index * 37) % 256),
    );
    final store = SenseVoiceModelStore(
      downloader: _FakeDownloader(payload: payload),
      directory: tempDir,
    );
    await store.ensureReady();
    expect(modelFile().readAsBytesSync(), payload);
    store.dispose();
  });

  test('并发 ensureReady 复用同一个请求', () async {
    final downloader = _FakeDownloader(
      payload: List<int>.generate(8192, (index) => index % 61),
    );
    final store = SenseVoiceModelStore(
      downloader: downloader,
      directory: tempDir,
    );

    await Future.wait(<Future<void>>[
      store.ensureReady(),
      store.ensureReady(),
      store.ensureReady(),
    ]);
    // model + tokens 各一次，而不是三次。
    expect(downloader.openCalls, 2);
    store.dispose();
  });
}

String _sha256Of(List<int> bytes) => sha256.convert(bytes).toString();
