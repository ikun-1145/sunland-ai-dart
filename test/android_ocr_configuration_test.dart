import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android bundles the Chinese ML Kit model used by local OCR', () {
    final coreSource = File('lib/sunland_ai_core.dart').readAsStringSync();
    final androidBuild = File(
      'android/app/build.gradle.kts',
    ).readAsStringSync();

    expect(
      coreSource,
      contains('TextRecognizer(script: TextRecognitionScript.chinese)'),
    );
    expect(
      androidBuild,
      contains(
        'implementation("com.google.mlkit:text-recognition-chinese:16.0.1")',
      ),
    );
  });

  test('OCR confirmation discloses and displays all outgoing text', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final coreSource = File('lib/sunland_ai_core.dart').readAsStringSync();

    expect(mainSource, isNot(contains('final preview = block.length > 120')));
    expect(mainSource, contains('Text(block, style:'));
    expect(coreSource, contains('识别出的文字会发送至 AI 服务，并随对话同步'));
  });
}
