import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'local_speech_model_store.dart';

/// 语音输入状态机。用单一枚举取代多个互相冲突的 bool。
enum VoiceInputState {
  /// 空闲，可以接收新的长按。
  idle,

  /// 正在申请权限 / 下载模型 / 加载模型，尚未开始录音。
  preparing,

  /// 正在录音，松手即识别。
  recording,

  /// 正在本地识别。
  recognizing,

  /// 上一次语音输入失败，下一次长按可以重新开始。
  error,
}

/// 一次成功识别的结果。
@immutable
class RecognizedSpeech {
  const RecognizedSpeech(this.text);

  final String text;
}

class VoiceRecognitionException implements Exception {
  const VoiceRecognitionException(this.message, {this.permissionDenied = false});

  final String message;

  /// 麦克风权限被拒绝时为 true，UI 可据此提示"仍可继续文字输入"。
  final bool permissionDenied;

  @override
  String toString() => message;
}

/// 本地识别引擎抽象。把 sherpa-onnx 隔离在实现里，状态机可在无模型环境下单测。
abstract interface class LocalSpeechEngine {
  /// 幂等：加载一次模型并常驻复用，绝不每次识别都重新加载。
  Future<void> ensureInitialized();

  /// 同步执行一次本地识别。[samples] 为 [-1, 1] 的单声道浮点 PCM。
  Future<String> recognize(Float32List samples, int sampleRate);

  void dispose();
}

/// 基于 sherpa-onnx + SenseVoiceSmall(int8) 的本地离线识别引擎。
///
/// 完全离线：sherpa-onnx 只读取本机文件，不做任何网络请求。
class SherpaSenseVoiceEngine implements LocalSpeechEngine {
  SherpaSenseVoiceEngine({
    required SenseVoiceModelStore modelStore,
    int numThreads = 2,
  }) : _modelStore = modelStore,
       _numThreads = numThreads;

  final SenseVoiceModelStore _modelStore;
  final int _numThreads;

  sherpa_onnx.OfflineRecognizer? _recognizer;
  Future<void>? _initInFlight;
  bool _disposed = false;

  @override
  Future<void> ensureInitialized() {
    final ready = _recognizer;
    if (ready != null) return Future<void>.value();
    final existing = _initInFlight;
    if (existing != null) return existing;

    late final Future<void> request;
    request = _initialize().whenComplete(() {
      if (identical(_initInFlight, request)) _initInFlight = null;
    });
    _initInFlight = request;
    return request;
  }

  Future<void> _initialize() async {
    if (_disposed) throw const VoiceRecognitionException('语音识别已释放');

    // 每个 isolate 需要各自初始化一次 FFI 绑定，这里只在主 isolate 使用。
    await sherpa_onnx.initBindingsAsync();

    final senseVoice = sherpa_onnx.OfflineSenseVoiceModelConfig(
      model: _modelStore.modelPath,
      // 自动识别语种，不让用户每次手动选择。
      language: 'auto',
      // 打开后 SenseVoice 会输出标点（ITN）。
      useInverseTextNormalization: true,
    );
    final modelConfig = sherpa_onnx.OfflineModelConfig(
      senseVoice: senseVoice,
      tokens: _modelStore.tokensPath,
      // feat 默认 sampleRate = 16000、featureDim = 80，与 SenseVoiceSmall 匹配。
      numThreads: _numThreads,
      debug: false,
    );

    final recognizer = sherpa_onnx.OfflineRecognizer(
      sherpa_onnx.OfflineRecognizerConfig(model: modelConfig),
    );
    if (_disposed) {
      recognizer.free();
      throw const VoiceRecognitionException('语音识别已释放');
    }
    _recognizer = recognizer;
  }

  @override
  Future<String> recognize(Float32List samples, int sampleRate) async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw const VoiceRecognitionException('语音识别尚未初始化');
    }
    if (samples.isEmpty) return '';

    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      recognizer.decode(stream);
      // 推理期间 Dart isolate 仍会泵事件循环，UI 不会永久冻结；且官方推荐
      // 在同一个 isolate 内使用 recognizer，避免 native 句柄跨 isolate 出错。
      return recognizer.getResult(stream).text;
    } finally {
      stream.free();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _recognizer?.free();
    _recognizer = null;
  }
}

/// 本地离线语音识别 Service：负责 sherpa 初始化、模型加载、麦克风录音、
/// PCM 处理、调用 SenseVoice、返回最终文本，以及生命周期与异常处理。
///
/// 不保存语音数据、不做任何网络上传；录音仅在内存中留存到本次识别结束。
class LocalSpeechRecognitionService {
  LocalSpeechRecognitionService({
    LocalSpeechEngine? engine,
    AudioRecorder? recorder,
    AudioRecorder Function()? recorderFactory,
    SenseVoiceModelStore? modelStore,
    bool supportsPlatform = true,
  }) : _recorderFactory = recorderFactory,
       _recorderOverride = recorder,
       _engineOverride = engine,
       _modelStoreOverride = modelStore,
       _supportsPlatform = supportsPlatform;

  /// sherpa-onnx FeatureConfig 的默认采样率，也是我们采集 PCM 的采样率。
  static const int sampleRate = 16000;

  /// 单次语音输入上限，覆盖"用户一直按着导致内存无限增长"的场景。
  static const Duration maxRecordingDuration = Duration(seconds: 60);

  /// 低于该时长视为误触，直接丢弃，不做识别。
  static const Duration minRecordingDuration = Duration(milliseconds: 300);

  static const int _bytesPerSample = 2;
  static const int _maxPcmBytes =
      sampleRate * _bytesPerSample * 60; // 60 秒上限，约 1.8 MB

  final LocalSpeechEngine? _engineOverride;
  final SenseVoiceModelStore? _modelStoreOverride;
  final AudioRecorder? _recorderOverride;
  final AudioRecorder Function()? _recorderFactory;
  final bool _supportsPlatform;

  /// 录音器懒创建：`AudioRecorder` 构造时会立即与平台通道握手，测试环境没有
  /// 该插件，因此探针与单测应通过 [AudioRecorder] / [AudioRecorder Function]
  /// 注入，或设置 `supportsPlatform: false` 避免触碰平台通道。
  AudioRecorder? _recorder;

  AudioRecorder get _recorderInstance {
    final injected = _recorderOverride;
    if (injected != null) return injected;
    return _recorder ??= (_recorderFactory ?? AudioRecorder.new)();
  }

  /// 懒创建：只有真正要用语音时才碰 path_provider 与网络。
  LocalSpeechEngine? _engine;
  SenseVoiceModelStore? _store;

  VoiceInputState _state = VoiceInputState.idle;
  bool _disposed = false;
  bool _permissionGranted = false;
  bool _nativeRecording = false;
  bool _modelReady = false;
  Future<void>? _initInFlight;

  StreamSubscription<Uint8List>? _subscription;
  final BytesBuilder _pcm = BytesBuilder(copy: false);
  int _pcmBytes = 0;
  DateTime? _recordingStartedAt;
  bool _finalizing = false;
  int _generation = 0;

  VoiceInputState get state => _state;

  @override
  String toString() => 'LocalSpeechRecognitionService(state: $_state)';

  bool get isRecording => _state == VoiceInputState.recording;

  /// 当前平台是否支持本地语音输入。桌面端返回 false，长按行为保持透传。
  bool get isPlatformSupported => _supportsPlatform;

  /// 长按刚触发时调用。
  ///
  /// 命中授权后不再重复调用平台接口，避免每次点按输入框都跨一次 channel。
  /// 返回 false 表示用户拒绝了麦克风权限：不录音、不崩溃，文字输入照常可用。
  Future<bool> preparePermission() async {
    if (_disposed || !_supportsPlatform) return false;
    if (_permissionGranted) return true;
    try {
      final granted = await _recorderInstance.hasPermission();
      if (granted) _permissionGranted = true;
      return granted;
    } catch (error) {
      debugPrint('麦克风权限检查失败：$error');
      return false;
    }
  }

  /// 确保模型已加载（首次包含一次性下载）。幂等，可重复调用；
  /// 并发调用复用同一个加载任务，避免重复下载或重复创建 recognizer。
  Future<void> initialize({
    void Function(ModelDownloadProgress progress)? onProgress,
  }) {
    if (_disposed) {
      return Future<void>.error(const VoiceRecognitionException('语音识别已释放'));
    }
    if (_modelReady) return Future<void>.value();
    final existing = _initInFlight;
    if (existing != null) return existing;

    late final Future<void> request;
    request = _initialize(onProgress: onProgress).whenComplete(() {
      if (identical(_initInFlight, request)) _initInFlight = null;
    });
    _initInFlight = request;
    return request;
  }

  Future<void> _initialize({
    void Function(ModelDownloadProgress progress)? onProgress,
  }) async {
    try {
      await _storeInstance.ensureReady(onProgress: onProgress);
    } on ModelDownloadCancelledException {
      rethrow;
    } on ModelDownloadException catch (error) {
      throw VoiceRecognitionException(error.message);
    }
    await _engineInstance.ensureInitialized();
    _modelReady = true;
  }

  /// 开始录音。状态不是 idle/error 时抛出 [VoiceRecognitionException]，
  /// 由调用方忽略本次长按。
  Future<void> startRecording() async {
    if (_disposed) throw const VoiceRecognitionException('语音识别已释放');
    if (_state == VoiceInputState.recording ||
        _state == VoiceInputState.recognizing ||
        _state == VoiceInputState.preparing) {
      throw const VoiceRecognitionException('正在处理上一次语音输入，请稍候');
    }
    if (_nativeRecording) {
      // 兜底：原生侧仍认为在录音，先彻底收尾，避免 recorder 卡死。
      await _teardownNativeRecording();
    }

    _pcm.clear();
    _pcmBytes = 0;
    final generation = ++_generation;
    _state = VoiceInputState.recording;
    _recordingStartedAt = DateTime.now();

    try {
      final stream = await _recorderInstance.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
          autoGain: true,
          echoCancel: false,
          noiseSuppress: false,
        ),
      );
      if (_disposed || generation != _generation) {
        await _teardownNativeRecording();
        return;
      }
      _nativeRecording = true;
      _subscription = stream.listen(
        _onPcmChunk,
        onError: (Object error) {
          debugPrint('麦克风采集出错：$error');
          if (generation == _generation) {
            unawaited(_abortToError('麦克风被系统中断，请重试'));
          }
        },
        cancelOnError: false,
      );
    } catch (error) {
      await _teardownNativeRecording();
      _state = VoiceInputState.error;
      throw VoiceRecognitionException('无法开始录音：$error');
    }
  }

  void _onPcmChunk(Uint8List chunk) {
    if (chunk.isEmpty) return;
    if (_pcmBytes >= _maxPcmBytes) return;
    final remaining = _maxPcmBytes - _pcmBytes;
    final accepted = chunk.length <= remaining
        ? chunk
        : Uint8List.sublistView(chunk, 0, remaining);
    _pcm.add(accepted);
    _pcmBytes += accepted.length;
  }

  /// 是否已达到单次录音时长上限。
  bool get reachedMaxDuration {
    final startedAt = _recordingStartedAt;
    if (startedAt == null) return false;
    return DateTime.now().difference(startedAt) >= maxRecordingDuration;
  }

  /// 松手：停止录音并执行本地识别。
  ///
  /// 返回 null 表示本次输入被安全忽略（时长过短、识别为空、已在识别中）。
  Future<RecognizedSpeech?> stopAndRecognize() async {
    if (_disposed) return null;
    if (_finalizing) return null;
    if (_state != VoiceInputState.recording) return null;

    _finalizing = true;
    final generation = _generation;
    var failed = false;
    final elapsed = _recordingStartedAt == null
        ? Duration.zero
        : DateTime.now().difference(_recordingStartedAt!);

    try {
      await _teardownNativeRecording();

      if (elapsed < minRecordingDuration || _pcmBytes < sampleRate) {
        // 时长过短或几乎没有有效音频，按误触处理。
        _state = VoiceInputState.idle;
        return null;
      }

      _state = VoiceInputState.recognizing;
      final samples = _toFloatSamples(_pcm.takeBytes());
      _pcmBytes = 0;
      if (samples.isEmpty) {
        _state = VoiceInputState.idle;
        return null;
      }

      await _engineInstance.ensureInitialized();
      final text = (await _engineInstance.recognize(samples, sampleRate)).trim();
      if (_disposed || generation != _generation) return null;
      if (text.isEmpty) {
        // 没有检测到有效语音或识别返回空字符串：不改动输入框。
        _state = VoiceInputState.idle;
        return null;
      }

      _state = VoiceInputState.idle;
      return RecognizedSpeech(text);
    } on VoiceRecognitionException {
      failed = true;
      _state = VoiceInputState.error;
      rethrow;
    } catch (error) {
      failed = true;
      debugPrint('本地语音识别失败：$error');
      _state = VoiceInputState.error;
      throw const VoiceRecognitionException('识别失败，请重试');
    } finally {
      _finalizing = false;
      _recordingStartedAt = null;
      _pcm.clear();
      _pcmBytes = 0;
      // 异常路径已经在上面把状态置为 error，不能在这里覆盖掉；
      // 这里只负责保证正常路径不会停在 recording/recognizing/preparing。
      if (!failed &&
          (_state == VoiceInputState.recording ||
              _state == VoiceInputState.recognizing ||
              _state == VoiceInputState.preparing)) {
        _state = VoiceInputState.idle;
      }
      if (generation != _generation) _state = VoiceInputState.idle;
    }
  }

  /// 取消本次语音输入：丢弃音频、不改动输入框。
  Future<void> cancel() async {
    if (_disposed) return;
    _generation++;
    try {
      await _teardownNativeRecording();
    } catch (error) {
      debugPrint('取消语音输入时出错：$error');
    } finally {
      _recordingStartedAt = null;
      _pcm.clear();
      _pcmBytes = 0;
      _finalizing = false;
      _state = VoiceInputState.idle;
    }
  }

  /// 释放全部资源。重复调用安全。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    try {
      await _teardownNativeRecording();
      await _recorderInstance.dispose();
    } catch (error) {
      debugPrint('释放录音资源时出错：$error');
    } finally {
      _subscription = null;
      _engineOverride?.dispose();
      _engine = null;
      _store?.dispose();
      _store = null;
      _recordingStartedAt = null;
      _pcm.clear();
      _pcmBytes = 0;
      _finalizing = false;
      _state = VoiceInputState.idle;
    }
  }

  /// 停掉原生录音并退订数据流。成功返回后 [_nativeRecording] 一定为 false，
  /// 保证不会出现"recorder 卡死"或重复创建多个 recorder。
  Future<void> _teardownNativeRecording() async {
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {
        // 退订失败不影响后面的原生停止。
      }
    }

    if (_nativeRecording) {
      _nativeRecording = false;
      try {
        await _recorderInstance.stop();
        return;
      } catch (error) {
        debugPrint('停止录音失败，回退到 cancel：$error');
      }
      try {
        await _recorderInstance.cancel();
      } catch (error) {
        debugPrint('取消录音同样失败，将尝试复用录音器：$error');
      }
    }
  }

  Future<void> _abortToError(String message) async {
    await cancel();
    _state = VoiceInputState.error;
    debugPrint('语音输入中止：$message');
  }

  /// PCM16 小端 → [-1, 1] 单声道 Float32。只在松手后做一次，避免流式拷贝。
  static Float32List _toFloatSamples(Uint8List bytes) {
    final usable = bytes.lengthInBytes & ~1; // 丢弃可能存在的半个样本
    if (usable <= 0) return Float32List(0);

    final view = ByteData.sublistView(bytes, 0, usable);
    final count = usable ~/ _bytesPerSample;
    final samples = Float32List(count);
    for (var i = 0; i < count; i++) {
      final value = view.getInt16(i * _bytesPerSample, Endian.little);
      samples[i] = value < 0 ? value / 32768.0 : value / 32767.0;
    }
    return samples;
  }

  /// 模型仓储。注入过的实例优先，否则首次使用时创建。
  SenseVoiceModelStore get _storeInstance {
    final injected = _modelStoreOverride;
    if (injected != null) return injected;
    return _store ??= SenseVoiceModelStore();
  }

  /// 识别引擎。测试可注入假引擎；生产环境用 sherpa-onnx + SenseVoiceSmall。
  LocalSpeechEngine get _engineInstance {
    final injected = _engineOverride;
    if (injected != null) return injected;
    return _engine ??= SherpaSenseVoiceEngine(modelStore: _storeInstance);
  }
}
