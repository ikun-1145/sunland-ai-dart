import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sunland_ai_app/services/image_attachment_service.dart';

void main() {
  late Directory tempDirectory;

  setUp(() {
    tempDirectory = Directory.systemTemp.createTempSync(
      'sunland-image-attachments-',
    );
  });

  tearDown(() {
    tempDirectory.deleteSync(recursive: true);
  });

  test('accepts readable images and ignores duplicates', () async {
    final first = File('${tempDirectory.path}/first.jpg')
      ..writeAsBytesSync([1, 2]);
    final second = File('${tempDirectory.path}/second.png')
      ..writeAsBytesSync([3, 4]);

    final result = await validateImageAttachments(
      candidatePaths: [first.path, first.path, second.path],
      existingPaths: const [],
    );

    expect(result.acceptedPaths, [first.path, second.path]);
    expect(result.duplicateCount, 1);
    expect(result.hasRejectedFiles, isTrue);
  });

  test('rejects unreadable, oversized, and over-limit images', () async {
    final accepted = File('${tempDirectory.path}/accepted.jpg')
      ..writeAsBytesSync([1, 2]);
    final oversized = File('${tempDirectory.path}/oversized.jpg')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final overLimit = File('${tempDirectory.path}/over-limit.jpg')
      ..writeAsBytesSync([1]);

    final result = await validateImageAttachments(
      candidatePaths: [
        '${tempDirectory.path}/missing.jpg',
        oversized.path,
        accepted.path,
        overLimit.path,
      ],
      existingPaths: const [],
      maxCount: 1,
      maxBytes: 3,
    );

    expect(result.acceptedPaths, [accepted.path]);
    expect(result.unreadableCount, 1);
    expect(result.tooLargeCount, 1);
    expect(result.limitExceededCount, 1);
  });

  test(
    'stages picker files so previews survive source cache removal',
    () async {
      final pickerCache = Directory('${tempDirectory.path}/picker-cache')
        ..createSync();
      final attachmentDirectory = Directory(
        '${tempDirectory.path}/chat-attachments',
      );
      final sourceBytes = img.encodePng(img.Image(width: 2, height: 2));
      final source = File('${pickerCache.path}/selected.PNG')
        ..writeAsBytesSync(sourceBytes);

      final result = await stageImageAttachments(
        candidatePaths: [source.path],
        existingPaths: const [],
        destinationDirectory: attachmentDirectory,
      );

      expect(result.acceptedPaths, hasLength(1));
      expect(result.acceptedPaths.single, isNot(source.path));
      expect(result.acceptedPaths.single, endsWith('.png'));
      source.deleteSync();
      expect(
        await File(result.acceptedPaths.single).readAsBytes(),
        sourceBytes,
      );
      expect(
        await prepareDeepSeekVisionImages(imagePaths: result.acceptedPaths),
        hasLength(1),
      );
    },
  );

  test(
    'keeps staged previews when the app prepares the directory again',
    () async {
      final attachmentDirectory = await ensureImageAttachmentDirectory(
        tempDirectory,
      );
      final image = File('${attachmentDirectory.path}/sent-image.png')
        ..writeAsBytesSync([1, 2, 3]);

      await ensureImageAttachmentDirectory(tempDirectory);

      expect(await image.exists(), isTrue);
    },
  );
}
