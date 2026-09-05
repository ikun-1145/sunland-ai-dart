import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int maxImageAttachmentCount = 4;
const int maxImageAttachmentBytes = 20 * 1024 * 1024;
const int maxPreparedVisionImageBytes = 3 * 1024 * 1024;
const int maxPreparedVisionTotalBytes = 10 * 1024 * 1024;
const int maxVisionImageSide = 2048;

Future<Directory> ensureImageAttachmentDirectory(
  Directory supportDirectory,
) async {
  final directory = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}chat_image_attachments',
  );
  await directory.create(recursive: true);
  return directory;
}

class ImagePreparationException implements Exception {
  const ImagePreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class ImageAttachmentValidationResult {
  const ImageAttachmentValidationResult({
    required this.acceptedPaths,
    required this.duplicateCount,
    required this.limitExceededCount,
    required this.tooLargeCount,
    required this.unreadableCount,
  });

  final List<String> acceptedPaths;
  final int duplicateCount;
  final int limitExceededCount;
  final int tooLargeCount;
  final int unreadableCount;

  bool get hasRejectedFiles =>
      duplicateCount > 0 ||
      limitExceededCount > 0 ||
      tooLargeCount > 0 ||
      unreadableCount > 0;
}

Future<ImageAttachmentValidationResult> validateImageAttachments({
  required Iterable<String> candidatePaths,
  required Iterable<String> existingPaths,
  int maxCount = maxImageAttachmentCount,
  int maxBytes = maxImageAttachmentBytes,
}) async {
  final acceptedPaths = <String>[];
  final knownPaths = existingPaths.where((path) => path.isNotEmpty).toSet();
  var duplicateCount = 0;
  var limitExceededCount = 0;
  var tooLargeCount = 0;
  var unreadableCount = 0;

  for (final rawPath in candidatePaths) {
    final path = rawPath.trim();
    if (path.isEmpty) {
      unreadableCount++;
      continue;
    }
    if (knownPaths.contains(path)) {
      duplicateCount++;
      continue;
    }
    if (knownPaths.length >= maxCount) {
      limitExceededCount++;
      continue;
    }

    final file = File(path);
    try {
      if (!await file.exists()) {
        unreadableCount++;
        continue;
      }
      final length = await file.length();
      if (length <= 0) {
        unreadableCount++;
        continue;
      }
      if (length > maxBytes) {
        tooLargeCount++;
        continue;
      }
    } on FileSystemException {
      unreadableCount++;
      continue;
    }

    knownPaths.add(path);
    acceptedPaths.add(path);
  }

  return ImageAttachmentValidationResult(
    acceptedPaths: List.unmodifiable(acceptedPaths),
    duplicateCount: duplicateCount,
    limitExceededCount: limitExceededCount,
    tooLargeCount: tooLargeCount,
    unreadableCount: unreadableCount,
  );
}

/// Copies validated picker results into an app-owned directory before the UI
/// starts depending on them. Picker paths can point at files managed by the
/// platform or plugin cache, so keeping those paths directly can leave both
/// the composer preview and the sent-message thumbnail without a readable
/// file.
Future<ImageAttachmentValidationResult> stageImageAttachments({
  required Iterable<String> candidatePaths,
  required Iterable<String> existingPaths,
  required Directory destinationDirectory,
  int maxCount = maxImageAttachmentCount,
  int maxBytes = maxImageAttachmentBytes,
}) async {
  final validation = await validateImageAttachments(
    candidatePaths: candidatePaths,
    existingPaths: existingPaths,
    maxCount: maxCount,
    maxBytes: maxBytes,
  );
  if (validation.acceptedPaths.isEmpty) return validation;

  try {
    await destinationDirectory.create(recursive: true);
  } on FileSystemException {
    return ImageAttachmentValidationResult(
      acceptedPaths: const [],
      duplicateCount: validation.duplicateCount,
      limitExceededCount: validation.limitExceededCount,
      tooLargeCount: validation.tooLargeCount,
      unreadableCount:
          validation.unreadableCount + validation.acceptedPaths.length,
    );
  }

  final stagedPaths = <String>[];
  var unreadableCount = validation.unreadableCount;
  for (var index = 0; index < validation.acceptedPaths.length; index++) {
    final sourcePath = validation.acceptedPaths[index];
    final source = File(sourcePath);
    final extension = _safeImageExtension(sourcePath);
    final uniquePart = DateTime.now().microsecondsSinceEpoch;
    final destination = File(
      '${destinationDirectory.path}${Platform.pathSeparator}'
      '$uniquePart-$index$extension',
    );
    try {
      final copied = await source.copy(destination.path);
      if (await copied.length() <= 0) {
        await copied.delete();
        unreadableCount++;
        continue;
      }
      stagedPaths.add(copied.path);
    } on FileSystemException {
      unreadableCount++;
    }
  }

  return ImageAttachmentValidationResult(
    acceptedPaths: List.unmodifiable(stagedPaths),
    duplicateCount: validation.duplicateCount,
    limitExceededCount: validation.limitExceededCount,
    tooLargeCount: validation.tooLargeCount,
    unreadableCount: unreadableCount,
  );
}

String _safeImageExtension(String path) {
  final fileName = path.split(RegExp(r'[/\\]')).last;
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0) return '.image';
  final extension = fileName.substring(dotIndex).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,10}$').hasMatch(extension)
      ? extension
      : '.image';
}

/// 将本地图片转换为 DeepSeek 视觉接口接受的内联 JPEG Data URL。
///
/// DeepSeek 会在推理前缩放图片，因此先在设备端限制尺寸和体积，可以避免
/// Base64 请求超过 Worker 的内存与请求体上限，同时保留足够的视觉细节。
Future<List<String>> prepareDeepSeekVisionImages({
  required Iterable<String> imagePaths,
  int maxCount = maxImageAttachmentCount,
  int maxBytesPerImage = maxPreparedVisionImageBytes,
  int maxTotalBytes = maxPreparedVisionTotalBytes,
  int maxSide = maxVisionImageSide,
}) async {
  final paths = imagePaths.where((path) => path.trim().isNotEmpty).toList();
  if (paths.isEmpty) return const <String>[];
  if (paths.length > maxCount) {
    throw ImagePreparationException('最多只能发送 $maxCount 张图片');
  }

  final dataUrls = <String>[];
  var totalBytes = 0;

  for (final path in paths) {
    final file = File(path);
    Uint8List sourceBytes;
    try {
      sourceBytes = await file.readAsBytes();
    } on FileSystemException {
      throw const ImagePreparationException('部分图片无法读取，请重新选择');
    }

    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const ImagePreparationException('图片格式不受支持，请使用 JPEG、PNG、GIF 或 WebP');
    }

    final oriented = img.bakeOrientation(decoded);
    var processed = _resizeToMaxSide(oriented, maxSide);
    var encoded = img.encodeJpg(processed, quality: 88);

    const fallbackSides = <int>[1600, 1280, 960];
    const fallbackQualities = <int>[84, 78, 72];
    for (var i = 0; i < fallbackSides.length; i++) {
      if (encoded.length <= maxBytesPerImage) break;
      final side = fallbackSides[i] < maxSide ? fallbackSides[i] : maxSide;
      processed = _resizeToMaxSide(oriented, side);
      encoded = img.encodeJpg(processed, quality: fallbackQualities[i]);
    }

    if (encoded.length > maxBytesPerImage) {
      throw const ImagePreparationException('图片处理后仍然过大，请裁剪后重试');
    }

    totalBytes += encoded.length;
    if (totalBytes > maxTotalBytes) {
      throw const ImagePreparationException('图片总大小过大，请减少图片数量后重试');
    }

    dataUrls.add('data:image/jpeg;base64,${base64Encode(encoded)}');
  }

  return List<String>.unmodifiable(dataUrls);
}

img.Image _resizeToMaxSide(img.Image source, int maxSide) {
  if (source.width <= maxSide && source.height <= maxSide) return source;

  return img.copyResize(
    source,
    width: source.width >= source.height ? maxSide : null,
    height: source.height > source.width ? maxSide : null,
    interpolation: img.Interpolation.average,
  );
}
