// 发布前校验工具：确认下载到的 SenseVoice 模型确实是一个能被 sherpa-onnx
// 打开的 ONNX 文件，并用官方测试音频跑一次真实识别。
//
// 用法：
//   dart run tool/verify_sensevoice_model.dart <model.onnx> <tokens.txt> [wav ...]
//
// 该工具不参与 App 运行时，也不被 App 代码引用，仅用于发布前人工确认：
//   1. 文件不是 HTML / JSON 错误页（检查 ONNX ModelProto 头）
//   2. sherpa-onnx 能成功创建 recognizer
//   3. 对给定 wav 能跑出识别结果
import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// ONNX 的 `ModelProto` 是 protobuf 编码，规范要求 `ir_version` 是第一个字段，
/// 因此合法文件必须以 field-1 varint 开头，即首字节为 `0x08`。
///
/// 这个判据可以一眼识破"服务器返回 200 + HTML 错误页"或"返回 JSON 错误体"
/// 这类静默损坏，比只看字节数可靠得多。
bool looksLikeOnnxModel(List<int> head) =>
    head.isNotEmpty && head[0] == 0x08 && head.length > 1 && head[1] > 0;

/// 读取 protobuf varint，返回解析值与下一个偏移。
({int value, int next}) _readVarint(List<int> bytes, int offset) {
  var result = 0;
  var shift = 0;
  var index = offset;
  while (index < bytes.length) {
    final byte = bytes[index++];
    result |= (byte & 0x7F) << shift;
    if (byte & 0x80 == 0) break;
    shift += 7;
    if (shift > 63) break;
  }
  return (value: result, next: index);
}

/// 解析 ModelProto 头部，取出 irVersion / producerName 供人工核对。
Map<String, Object?> describeOnnxHeader(List<int> bytes) {
  final info = <String, Object?>{'irVersion': null, 'producerName': null};
  var index = 0;
  while (index < bytes.length) {
    final key = _readVarint(bytes, index);
    index = key.next;
    final fieldNumber = key.value >> 3;
    switch (key.value & 0x07) {
      case 0:
        final value = _readVarint(bytes, index);
        index = value.next;
        if (fieldNumber == 1) info['irVersion'] = value.value;
      case 2:
        final length = _readVarint(bytes, index);
        index = length.next;
        final end = index + length.value;
        if (end > bytes.length) return info;
        if (fieldNumber == 2) {
          info['producerName'] = String.fromCharCodes(
            bytes.sublist(index, end),
          );
        }
        index = end;
      case 5:
        index += 4;
      case 1:
        index += 8;
      default:
        return info;
    }
    if (info['producerName'] != null) break;
  }
  return info;
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: verify_sensevoice_model.dart <model.onnx> <tokens.txt> [wav ...]',
    );
    exit(64);
  }
  final modelPath = args[0];
  final tokensPath = args[1];

  final modelFile = File(modelPath);
  final tokensFile = File(tokensPath);
  if (!modelFile.existsSync()) {
    stderr.writeln('FAIL: model not found: $modelPath');
    exit(66);
  }
  if (!tokensFile.existsSync()) {
    stderr.writeln('FAIL: tokens not found: $tokensPath');
    exit(66);
  }

  final modelBytes = modelFile.lengthSync();
  stdout.writeln('model  : $modelPath');
  stdout.writeln('  bytes        : $modelBytes');
  stdout.writeln('tokens : $tokensPath');
  stdout.writeln('  bytes        : ${tokensFile.lengthSync()}');

  // ---- 1. 不是 HTML / JSON / 空文件 ----
  final handle = modelFile.openSync();
  final head = handle.readSync(64);
  handle.closeSync();
  if (modelBytes < 1024) {
    stderr.writeln('FAIL: file too small to be a model ($modelBytes bytes)');
    exit(65);
  }
  if (!looksLikeOnnxModel(head)) {
    final preview = String.fromCharCodes(
      head.take(64).map((b) => b >= 32 && b < 127 ? b : 0x2E),
    );
    final first = head.isEmpty ? 'n/a' : '0x${head.first.toRadixString(16)}';
    stderr.writeln(
      'FAIL: not an ONNX ModelProto header. firstByte=$first preview="$preview"',
    );
    exit(65);
  }
  final info = describeOnnxHeader(head);
  stdout.writeln('  onnx ir      : ${info['irVersion']}');
  stdout.writeln('  producer     : ${info['producerName']}');
  stdout.writeln('  header check : PASS (not HTML/JSON error page)');

  // ---- 2. sherpa-onnx 能否真正打开这个模型 ----
  final loadWatch = Stopwatch()..start();
  await sherpa_onnx.initBindingsAsync();
  final modelConfig = sherpa_onnx.OfflineModelConfig(
    senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
      model: modelPath,
      language: 'auto',
      useInverseTextNormalization: true,
    ),
    tokens: tokensPath,
    numThreads: 2,
    debug: false,
  );
  final recognizer = sherpa_onnx.OfflineRecognizer(
    sherpa_onnx.OfflineRecognizerConfig(model: modelConfig),
  );
  stdout.writeln(
    '  recognizer   : OPENED OK in ${loadWatch.elapsedMilliseconds} ms',
  );

  // ---- 3. 真实识别 ----
  for (final wavPath in args.skip(2)) {
    final wavFile = File(wavPath);
    if (!wavFile.existsSync()) {
      stdout.writeln('  [skip] $wavPath not found');
      continue;
    }
    final wave = sherpa_onnx.readWave(wavPath);
    final stream = recognizer.createStream();
    final decodeWatch = Stopwatch()..start();
    try {
      stream.acceptWaveform(
        samples: wave.samples,
        sampleRate: wave.sampleRate,
      );
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      final elapsed = decodeWatch.elapsedMilliseconds;
      final seconds = wave.samples.length / wave.sampleRate;
      final rtf = (elapsed / 1000 / seconds).toStringAsFixed(3);
      stdout.writeln(
        '  ${wavFile.uri.pathSegments.last}: "${result.text}"'
        '  (${elapsed}ms, RTF $rtf)',
      );
      stdout.writeln(
        '    lang=${result.lang} emotion=${result.emotion} '
        'event=${result.event}',
      );
    } finally {
      stream.free();
    }
  }

  recognizer.free();
  stdout.writeln('RESULT: VERIFY OK');
  exit(0);
}
