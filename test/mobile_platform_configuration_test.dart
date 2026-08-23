import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares camera and photo-library privacy reasons', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(infoPlist, contains('<key>NSCameraUsageDescription</key>'));
    expect(infoPlist, contains('<key>NSPhotoLibraryUsageDescription</key>'));
    expect(infoPlist, contains('用于拍摄图片，并在你确认后发送给 DeepSeek 进行视觉理解'));
    expect(infoPlist, contains('用于选择图片，并在你确认后发送给 DeepSeek 进行视觉理解'));
  });

  test('Android uses system pickers without broad media permissions', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, isNot(contains('android.permission.CAMERA')));
    expect(manifest, isNot(contains('android.permission.VIBRATE')));
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
  });

  test('mobile image flow supports camera, files, and Android recovery', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains('source: ImageSource.camera'));
    expect(mainSource, contains('FilePicker.platform.pickFiles'));
    expect(mainSource, contains('retrieveLostData()'));
    expect(mainSource, contains('requestFullMetadata: false'));
    expect(mainSource, contains('prepareDeepSeekVisionImages'));
    expect(mainSource, isNot(contains('当前平台不支持仅发图片')));
  });

  test('iOS background tasks are registered and always endable', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();

    expect(appDelegate, contains('sunland.ai/background_execution'));
    expect(appDelegate, contains('beginBackgroundTask(withName:'));
    expect(appDelegate, contains('endBackgroundTask(identifier)'));
    expect(
      appDelegate,
      contains('engineBridge.applicationRegistrar.messenger()'),
    );
  });

  test('AI haptics are isolated to the iOS Core Haptics bridge', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    final hapticManager = File(
      'ios/Runner/AIHapticManager.swift',
    ).readAsStringSync();
    final hapticService = File(
      'lib/services/ai_haptic_service.dart',
    ).readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(appDelegate, contains('sunland.ai/ai_haptics'));
    expect(hapticManager, contains('import CoreHaptics'));
    expect(hapticManager, contains('eventType: .hapticTransient'));
    expect(hapticManager, contains('stoppedHandler'));
    expect(hapticManager, contains('resetHandler'));
    expect(hapticService, contains('Platform.isIOS'));
    expect(hapticService, isNot(contains('HapticFeedback')));
    expect(androidManifest, isNot(contains('android.permission.VIBRATE')));
  });
}
