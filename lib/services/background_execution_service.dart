import 'package:flutter/services.dart';

class BackgroundExecutionService {
  const BackgroundExecutionService({
    MethodChannel channel = const MethodChannel(
      'sunland.ai/background_execution',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<int?> begin({required String name}) async {
    try {
      return await _channel.invokeMethod<int>('begin', {'name': name});
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> end(int? taskId) async {
    if (taskId == null) return;
    try {
      await _channel.invokeMethod<void>('end', {'taskId': taskId});
    } on MissingPluginException {
      // Android and desktop intentionally use a no-op fallback.
    } on PlatformException {
      // The OS may already have expired and ended the task.
    }
  }
}
