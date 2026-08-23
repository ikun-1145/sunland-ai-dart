import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/ai_haptic_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('sunland.ai/ai_haptics.test');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('normal iOS request sends each semantic event only once', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final service = AiHapticService(channel: channel, isIOS: true);
    final request = service.beginRequest(deepThinking: false);

    await request.aiStarted();
    await request.aiStarted();
    await request.answerStarted();
    await request.answerStarted();
    await request.answerCompleted();
    await request.answerCompleted();

    expect(calls.map((call) => call.method), [
      'aiStarted',
      'answerStarted',
      'answerCompleted',
    ]);
  });

  test('deep-thinking iOS request disables every haptic event', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final service = AiHapticService(channel: channel, isIOS: true);
    final request = service.beginRequest(deepThinking: true);

    await request.aiStarted();
    await request.answerStarted();
    await request.answerCompleted();

    expect(calls, isEmpty);
  });

  test('non-iOS request never invokes the native channel', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final service = AiHapticService(channel: channel, isIOS: false);
    final request = service.beginRequest(deepThinking: false);

    await request.aiStarted();
    await request.answerStarted();
    await request.answerCompleted();

    expect(calls, isEmpty);
  });

  test('native haptic failures are swallowed', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'haptics-unavailable');
    });
    final service = AiHapticService(channel: channel, isIOS: true);
    final request = service.beginRequest(deepThinking: false);

    await expectLater(request.aiStarted(), completes);
    await expectLater(request.answerStarted(), completes);
    await expectLater(request.answerCompleted(), completes);
  });
}
