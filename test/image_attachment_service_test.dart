import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
}
