import 'dart:io';

const int maxImageAttachmentCount = 4;
const int maxImageAttachmentBytes = 20 * 1024 * 1024;

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
