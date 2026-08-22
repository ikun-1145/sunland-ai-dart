import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/background_execution_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('sunland.ai/background_execution');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('pairs native background task begin and end calls', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'begin') return 17;
      return null;
    });
    const service = BackgroundExecutionService(channel: channel);

    final taskId = await service.begin(name: 'test operation');
    await service.end(taskId);

    expect(taskId, 17);
    expect(calls.map((call) => call.method), ['begin', 'end']);
    expect(calls.first.arguments, {'name': 'test operation'});
    expect(calls.last.arguments, {'taskId': 17});
  });

  test('uses a safe no-op when the platform has no implementation', () async {
    const service = BackgroundExecutionService(channel: channel);

    expect(await service.begin(name: 'unsupported platform'), isNull);
    await expectLater(service.end(null), completes);
  });
}
