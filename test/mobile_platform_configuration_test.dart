import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS declares camera and photo-library privacy reasons', () {
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(infoPlist, contains('<key>NSCameraUsageDescription</key>'));
    expect(infoPlist, contains('<key>NSPhotoLibraryUsageDescription</key>'));
    expect(infoPlist, contains('用于拍摄图片并在发送前于设备上识别其中的文字'));
    expect(infoPlist, contains('用于选择图片并在发送前于设备上识别其中的文字'));
  });

  test('Android uses system pickers without broad media permissions', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, isNot(contains('android.permission.CAMERA')));
    expect(manifest, isNot(contains('READ_EXTERNAL_STORAGE')));
    expect(manifest, isNot(contains('WRITE_EXTERNAL_STORAGE')));
  });

  test('mobile image flow supports camera, files, and Android recovery', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains('source: ImageSource.camera'));
    expect(mainSource, contains('FilePicker.platform.pickFiles'));
    expect(mainSource, contains('retrieveLostData()'));
    expect(mainSource, contains('requestFullMetadata: false'));
  });

  test('iOS background tasks are registered and always endable', () {
    final appDelegate = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();

    expect(appDelegate, contains('sunland.ai/background_execution'));
    expect(appDelegate, contains('beginBackgroundTask(withName:'));
    expect(appDelegate, contains('endBackgroundTask(identifier)'));
    expect(
      appDelegate,
      contains('engineBridge.applicationRegistrar.messenger()'),
    );
  });
}
