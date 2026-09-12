import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:sunland_ai_app/services/local_speech_model_store.dart';
import 'package:sunland_ai_app/services/local_speech_recognition_service.dart';

/// 假引擎：不加载任何模型，用于验证状态机与异常收敛。
class _FakeEngine implements LocalSpeechEngine {
  _FakeEngine({this.initError});

  /// 默认识别结果，测试可直接改写。
  String result = '你好';
  Object? initError;

  int initCalls = 0;
  int recognizeCalls = 0;
  int disposeCalls = 0;
  Float32List? lastSamples;

  @override
  Future<void> ensureInitialized() async {
    initCalls++;
    final error = initError;
    if (error != null) throw error;
  }

  @override
  Future<String> recognize(Float32List samples, int sampleRate) async {
    recognizeCalls++;
    lastSamples = samples;
    return result;
  }

  @override
  void dispose() => disposeCalls++;
}

/// 立刻成功的假下载器，避免测试碰网络与 path_provider。
class _InstantDownloader implements HttpDownloader {
  _InstantDownloader(this.payload);

  final List<int> payload;

  @override
  Future<HttpDownloadResponse> open(
    Uri uri, {
    int? rangeStart,
    Duration idleTimeout = const Duration(seconds: 30),
  }) async {
    return HttpDownloadResponse(
      statusCode: 200,
      bytes: Stream<List<int>>.value(payload),
    );
  }

  @override
  void close() {}
}


/// 用假的 [RecordPlatform] 接管 record 插件，测试环境不加载任何原生插件。
///
/// `AudioRecorder` 的构造函数会立刻调用 `RecordPlatform.instance.create(...)`，
/// 单测里没有该插件会抛 MissingPluginException，因此这里替换掉平台实例。
class _FakeRecordPlatform extends RecordPlatform {
  bool permissionGranted = true;
  int createCalls = 0;
  int disposeCalls = 0;
  int startStreamCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  RecordConfig? lastConfig;

  @override
  Future<void> create(String recorderId) async => createCalls++;

  @override
  Future<void> dispose(String recorderId) async {
    disposeCalls++;
    closeStreams();
  }

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permissionGranted;

  /// 测试可主动把 PCM16 数据推给 service，模拟麦克风采集。
  void emit(List<int> pcm16) {
    for (final controller in List<StreamController<Uint8List>>.from(_controllers)) {
      if (controller.isClosed) continue;
      controller.add(Uint8List.fromList(pcm16));
    }
  }

  /// 停止时关闭数据流，模拟原生侧停止采集，避免测试进程被未关闭的流挂住。
  void closeStreams() {
    for (final controller in _controllers) {
      if (!controller.isClosed) controller.close();
    }
    _controllers.clear();
  }

  final List<StreamController<Uint8List>> _controllers = [];

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) async {
    startStreamCalls++;
    lastConfig = config;
    final controller = StreamController<Uint8List>();
    _controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<String?> stop(String recorderId) async {
    stopCalls++;
    closeStreams();
    return null;
  }

  @override
  Future<void> cancel(String recorderId) async {
    cancelCalls++;
    closeStreams();
  }

  /// `AudioRecorder.startStream` 会顺带监听录音状态，给一个空流即可。
  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: 0, max: 0);

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const <InputDevice>[];

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async => true;

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {}
}

/// 权限查询直接抛错，用来验证 service 的容错分支。
class _ThrowingPermissionPlatform extends _FakeRecordPlatform {
  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) {
    throw StateError('权限通道不可用');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _FakeEngine engine;
  late _FakeRecordPlatform recordPlatform;
  late LocalSpeechRecognitionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('speech_service_test');
    engine = _FakeEngine();
    recordPlatform = _FakeRecordPlatform();
    RecordPlatform.instance = recordPlatform;
    service = LocalSpeechRecognitionService(
      engine: engine,
      modelStore: SenseVoiceModelStore(
        downloader: _InstantDownloader(const [1, 2, 3, 4]),
        directory: tempDir,
      ),
    );
  });

  tearDown(() async {
    await service.dispose();
    recordPlatform.closeStreams();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('状态机', () {
    test('初始为 idle 且未在录音', () {
      expect(service.state, VoiceInputState.idle);
      expect(service.isRecording, isFalse);
    });

    test('未开始录音时 stopAndRecognize 返回 null 且保持 idle', () async {
      expect(await service.stopAndRecognize(), isNull);
      expect(service.state, VoiceInputState.idle);
      expect(engine.recognizeCalls, 0);
    });

    test('未录音时 cancel 安全并把状态复位', () async {
      await expectLater(service.cancel(), completes);
      expect(service.state, VoiceInputState.idle);
      expect(service.isRecording, isFalse);
    });

    test('录音→松手识别：状态机走完并返回识别文本', () async {
      engine.result = '今天东京天气';
      await service.initialize();

      await service.startRecording();
      expect(service.state, VoiceInputState.recording);
      expect(service.isRecording, isTrue);
      expect(recordPlatform.startStreamCalls, 1);

      // 采集参数必须是 16kHz / 单声道 / PCM16，否则 SenseVoice 无法识别。
      expect(recordPlatform.lastConfig?.encoder, AudioEncoder.pcm16bits);
      expect(recordPlatform.lastConfig?.sampleRate, 16000);
      expect(recordPlatform.lastConfig?.numChannels, 1);

      // 推入约 1 秒的 PCM16 数据，并让录音时长超过 300ms 的最短阈值。
      recordPlatform.emit(List<int>.filled(32000, 0));
      await Future<void>.delayed(const Duration(milliseconds: 350));

      final result = await service.stopAndRecognize();
      expect(result?.text, '今天东京天气');
      expect(engine.recognizeCalls, 1);
      expect(service.state, VoiceInputState.idle);
      expect(service.isRecording, isFalse);
      expect(recordPlatform.stopCalls, 1);
    });

    test('录音期间再次长按会被忽略而不是并发启动第二个录音', () async {
      await service.initialize();
      await service.startRecording();
      expect(service.isRecording, isTrue);

      await expectLater(
        service.startRecording(),
        throwsA(isA<VoiceRecognitionException>()),
      );
      // 只创建了一个录音会话。
      expect(recordPlatform.startStreamCalls, 1);
      expect(service.state, VoiceInputState.recording);
      await service.cancel();
    });

    test('识别结果为空时返回 null，不写入输入框', () async {
      engine.result = '   ';
      await service.initialize();
      await service.startRecording();
      recordPlatform.emit(List<int>.filled(32000, 0));
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(await service.stopAndRecognize(), isNull);
      expect(service.state, VoiceInputState.idle);
    });

    test('识别抛异常时状态收敛到 error 而不是卡在 recording/recognizing', () async {
      final failing = _FakeEngine(initError: const VoiceRecognitionException('boom'));
      final broken = LocalSpeechRecognitionService(
        engine: failing,
        modelStore: SenseVoiceModelStore(
          downloader: _InstantDownloader(const [1, 2, 3, 4]),
          directory: tempDir,
        ),
      );
      await broken.startRecording();
      recordPlatform.emit(List<int>.filled(32000, 0));
      await Future<void>.delayed(const Duration(milliseconds: 350));

      // 模型未加载成功，识别阶段会抛错。
      await expectLater(
        broken.stopAndRecognize(),
        throwsA(isA<VoiceRecognitionException>()),
      );
      expect(broken.state, isNot(VoiceInputState.recording));
      expect(broken.state, isNot(VoiceInputState.recognizing));
      expect(broken.isRecording, isFalse);
      await broken.dispose();
    });

    test('录音时长过短时按误触忽略，不调用识别', () async {
      await service.initialize();
      await service.startRecording();
      // 只推入 100 个样本，远低于最少样本量。
      recordPlatform.emit(List<int>.filled(200, 0));
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(await service.stopAndRecognize(), isNull);
      expect(engine.recognizeCalls, 0);
      expect(service.state, VoiceInputState.idle);
    });

    test('cancel 会丢弃本次录音且不触发识别', () async {
      await service.initialize();
      await service.startRecording();
      recordPlatform.emit(List<int>.filled(32000, 0));
      await Future<void>.delayed(const Duration(milliseconds: 350));

      await service.cancel();
      expect(service.state, VoiceInputState.idle);
      expect(engine.recognizeCalls, 0);
      expect(recordPlatform.disposeCalls, 0);
    });

    test('initialize 只加载一次模型，重复调用复用 recognizer', () async {
      await service.initialize();
      expect(engine.initCalls, 1);
      await service.initialize();
      await service.initialize();
      expect(engine.initCalls, 1);
    });

    test('initialize 并发调用也只会加载一次', () async {
      await Future.wait<void>([
        service.initialize(),
        service.initialize(),
        service.initialize(),
      ]);
      expect(engine.initCalls, 1);
    });

    test('模型加载失败时抛出可读异常', () async {
      final failing = LocalSpeechRecognitionService(
        engine: _FakeEngine(
          initError: const VoiceRecognitionException('语音识别初始化失败'),
        ),
        modelStore: SenseVoiceModelStore(
          downloader: _InstantDownloader(const [1]),
          directory: tempDir,
        ),
      );
      await expectLater(
        failing.initialize(),
        throwsA(isA<VoiceRecognitionException>()),
      );
      await failing.dispose();
    });

    test('模型下载失败被翻译成 VoiceRecognitionException', () async {
      final failing = LocalSpeechRecognitionService(
        engine: _FakeEngine(),
        modelStore: SenseVoiceModelStore(
          downloader: _InstantDownloader(const []),
          directory: tempDir,
        ),
      );
      await expectLater(
        failing.initialize(),
        throwsA(isA<VoiceRecognitionException>()),
      );
      await failing.dispose();
    });
  });

  group('释放语义', () {
    test('dispose 后状态复位为 idle 且释放引擎一次', () async {
      await service.dispose();
      expect(service.state, VoiceInputState.idle);
      expect(service.isRecording, isFalse);
      expect(engine.disposeCalls, 1);
    });

    test('重复 dispose 是安全的且不会重复释放引擎', () async {
      await service.dispose();
      await service.dispose();
      expect(engine.disposeCalls, 1);
    });

    test('dispose 后不能开始录音', () async {
      await service.dispose();
      await expectLater(
        service.startRecording(),
        throwsA(isA<VoiceRecognitionException>()),
      );
    });

    test('dispose 后 initialize 抛错且不再加载模型', () async {
      await service.dispose();
      await expectLater(
        service.initialize(),
        throwsA(isA<VoiceRecognitionException>()),
      );
      expect(engine.initCalls, 0);
    });

    test('dispose 后 stopAndRecognize 返回 null 而不是卡住', () async {
      await service.dispose();
      expect(await service.stopAndRecognize(), isNull);
    });
  });

  group('权限与平台', () {
    test('不支持语音的平台拒绝权限准备', () async {
      final unsupported = LocalSpeechRecognitionService(
        engine: _FakeEngine(),
        supportsPlatform: false,
      );
      expect(unsupported.isPlatformSupported, isFalse);
      expect(await unsupported.preparePermission(), isFalse);
      await unsupported.dispose();
    });

    test('授权后 preparePermission 返回 true，且只查一次平台', () async {
      recordPlatform.permissionGranted = true;
      expect(await service.preparePermission(), isTrue);
      // 命中授权后不再重复跨平台通道。
      expect(await service.preparePermission(), isTrue);
    });

    test('用户拒绝权限时返回 false 且不抛异常', () async {
      recordPlatform.permissionGranted = false;
      expect(await service.preparePermission(), isFalse);
      expect(await service.preparePermission(), isFalse);
    });

    test('权限查询抛异常时安全返回 false 而不是抛出', () async {
      final failing = _ThrowingPermissionPlatform();
      RecordPlatform.instance = failing;
      final tolerant = LocalSpeechRecognitionService(engine: _FakeEngine());
      expect(await tolerant.preparePermission(), isFalse);
      await tolerant.dispose();
      RecordPlatform.instance = recordPlatform;
    });

    test('实机平台默认识别为支持', () {
      final supported = LocalSpeechRecognitionService(engine: _FakeEngine());
      expect(supported.isPlatformSupported, isTrue);
      return supported.dispose();
    });
  });

  group('常量契约', () {
    test('采样率与录音上限符合 SenseVoice / 需求', () {
      expect(LocalSpeechRecognitionService.sampleRate, 16000);
      expect(
        LocalSpeechRecognitionService.maxRecordingDuration,
        const Duration(seconds: 60),
      );
      expect(
        LocalSpeechRecognitionService.minRecordingDuration,
        const Duration(milliseconds: 300),
      );
    });

    test('RecordConfig 使用 16kHz 单声道 PCM16', () {
      const config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: LocalSpeechRecognitionService.sampleRate,
        numChannels: 1,
      );
      expect(config.encoder, AudioEncoder.pcm16bits);
      expect(config.sampleRate, 16000);
      expect(config.numChannels, 1);
    });
  });

  group('结果与异常语义', () {
    test('RecognizedSpeech 只承载文本', () {
      const speech = RecognizedSpeech('今天东京天气');
      expect(speech.text, '今天东京天气');
    });

    test('VoiceRecognitionException 可标记权限被拒绝', () {
      const denied = VoiceRecognitionException('无权限', permissionDenied: true);
      expect(denied.permissionDenied, isTrue);
      expect(denied.toString(), '无权限');
      expect(const VoiceRecognitionException('其他').permissionDenied, isFalse);
    });

    test('state 与 isRecording 始终同步', () {
      expect(service.isRecording, service.state == VoiceInputState.recording);
    });
  });
}
