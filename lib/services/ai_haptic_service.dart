import 'dart:io';

import 'package:flutter/services.dart';

class AiHapticService {
  AiHapticService({
    MethodChannel channel = const MethodChannel('sunland.ai/ai_haptics'),
    bool? isIOS,
  }) : _channel = channel,
       _isIOS = isIOS ?? Platform.isIOS;

  final MethodChannel _channel;
  final bool _isIOS;

  AiHapticRequest beginRequest({required bool deepThinking}) {
    return AiHapticRequest._(
      service: this,
      enabled: _isIOS && !deepThinking,
    );
  }

  Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // Haptics are best effort and must never interrupt AI generation.
    }
  }
}

class AiHapticRequest {
  AiHapticRequest._({required AiHapticService service, required bool enabled})
    : _service = service,
      _enabled = enabled;

  final AiHapticService _service;
  final bool _enabled;

  bool _didTriggerAiStarted = false;
  bool _didTriggerAnswerStarted = false;
  bool _didTriggerAnswerCompleted = false;

  Future<void> aiStarted() {
    if (!_enabled || _didTriggerAiStarted) return Future<void>.value();
    _didTriggerAiStarted = true;
    return _service._invoke('aiStarted');
  }

  Future<void> answerStarted() {
    if (!_enabled || _didTriggerAnswerStarted) return Future<void>.value();
    _didTriggerAnswerStarted = true;
    return _service._invoke('answerStarted');
  }

  Future<void> answerCompleted() {
    if (!_enabled || _didTriggerAnswerCompleted) return Future<void>.value();
    _didTriggerAnswerCompleted = true;
    return _service._invoke('answerCompleted');
  }
}
