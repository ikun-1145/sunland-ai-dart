import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/local_speech_recognition_service.dart';
import 'package:sunland_ai_app/theme/sunland_theme.dart';
import 'package:sunland_ai_app/widgets/chat_composer.dart';

void main() {
  testWidgets(
    'enables send only when there is message content and keeps stop available',
    (tester) async {
      final controller = TextEditingController();
      var sends = 0;
      var stops = 0;

      await tester.pumpWidget(
        _app(
          ChatComposer(
            controller: controller,
            attachments: const [],
            isGenerating: false,
            attachmentsEnabled: true,
            deepThinkingEnabled: false,
            deepThinkingAvailable: true,
            modelLabel: 'Flash',
            onPickImage: () {},
            onRemoveAttachment: (_) {},
            onToggleDeepThinking: () {},
            onSelectModel: () {},
            onSend: () => sends += 1,
            onStop: () => stops += 1,
          ),
        ),
      );

      final sendButton = find.byKey(const ValueKey('chat-composer-action'));
      expect(tester.widget<IconButton>(sendButton).onPressed, isNull);

      controller.text = '测试消息';
      await tester.pump();
      await tester.tap(sendButton);
      expect(sends, 1);

      await tester.pumpWidget(
        _app(
          ChatComposer(
            controller: controller,
            attachments: const [],
            isGenerating: true,
            attachmentsEnabled: true,
            deepThinkingEnabled: false,
            deepThinkingAvailable: true,
            modelLabel: 'Flash',
            onPickImage: () {},
            onRemoveAttachment: (_) {},
            onToggleDeepThinking: () {},
            onSelectModel: () {},
            onSend: () => sends += 1,
            onStop: () => stops += 1,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('chat-composer-action')));
      expect(stops, 1);
      controller.dispose();
    },
  );

  testWidgets('wraps controls on a narrow screen with enlarged text', (
    tester,
  ) async {
    final controller = TextEditingController(text: '一段用于检查多行输入布局的测试文字。');

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 640),
          textScaler: TextScaler.linear(2),
        ),
        child: _app(
          SizedBox(
            width: 320,
            child: ChatComposer(
              controller: controller,
              attachments: const [],
              isGenerating: false,
              attachmentsEnabled: true,
              deepThinkingEnabled: false,
              deepThinkingAvailable: true,
              modelLabel: 'Sunland AI Flash 长模型名称',
              onPickImage: () {},
              onRemoveAttachment: (_) {},
              onToggleDeepThinking: () {},
              onSelectModel: () {},
              onSend: () {},
              onStop: () {},
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  group('语音接入回归', voiceRegressionTests);
}

Widget _app(Widget child) => MaterialApp(
  theme: SunlandTheme.light,
  home: Scaffold(body: child),
);

// ===== 语音接入后的回归测试 =====

ChatComposer _voiceComposer({
  required TextEditingController controller,
  required VoiceInputState state,
  bool enabled = true,
  VoidCallback? onVoiceStart,
  VoidCallback? onVoiceStop,
  VoidCallback? onVoiceCancel,
}) {
  return ChatComposer(
    controller: controller,
    attachments: const [],
    isGenerating: false,
    attachmentsEnabled: true,
    deepThinkingEnabled: false,
    deepThinkingAvailable: true,
    modelLabel: 'Flash',
    onPickImage: () {},
    onRemoveAttachment: (_) {},
    onToggleDeepThinking: () {},
    onSelectModel: () {},
    onSend: () {},
    onStop: () {},
    voiceInputEnabled: enabled,
    voiceState: state,
    onVoiceStart: onVoiceStart,
    onVoiceStop: onVoiceStop,
    onVoiceCancel: onVoiceCancel,
  );
}

void voiceRegressionTests() {
  testWidgets('开启语音不改变任何布局尺寸（像素级）', (tester) async {
    final controller = TextEditingController();
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Future<Map<String, Rect>> measure(bool voiceEnabled) async {
      await tester.pumpWidget(
        _app(
          _voiceComposer(
            controller: TextEditingController(),
            state: VoiceInputState.idle,
            enabled: voiceEnabled,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return <String, Rect>{
        'composer': tester.getRect(find.byType(ChatComposer)),
        'textField': tester.getRect(find.byType(TextField)),
        'material': tester.getRect(find.byType(Material).first),
        'wrap': tester.getRect(find.byType(Wrap)),
        'sendButton': tester.getRect(
          find.byKey(const ValueKey('chat-composer-action')),
        ),
      };
    }

    final off = await measure(false);
    final on = await measure(true);

    for (final key in off.keys) {
      expect(
        on[key],
        off[key],
        reason: '$key 在开启语音后尺寸/位置发生了变化',
      );
    }
    controller.dispose();
  });

  testWidgets('各语音状态都不改变布局，只替换 hint 文案', (tester) async {
    final controller = TextEditingController();

    Rect textFieldRect(VoiceInputState state) {
      return tester.getRect(find.byType(TextField));
    }

    await tester.pumpWidget(
      _app(
        _voiceComposer(
          controller: controller,
          state: VoiceInputState.idle,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final idleRect = textFieldRect(VoiceInputState.idle);
    expect(find.text('输入消息…'), findsOneWidget);

    for (final state in <VoiceInputState>[
      VoiceInputState.preparing,
      VoiceInputState.recording,
      VoiceInputState.recognizing,
      VoiceInputState.error,
      VoiceInputState.idle,
    ]) {
      await tester.pumpWidget(
        _app(_voiceComposer(controller: controller, state: state)),
      );
      await tester.pumpAndSettle();
      expect(
        textFieldRect(state),
        idleRect,
        reason: '状态 $state 改变了 TextField 尺寸/位置',
      );
      expect(tester.takeException(), isNull);
    }
    controller.dispose();
  });

  testWidgets('录音状态只替换为聆听文案', (tester) async {
    final controller = TextEditingController();
    final events = <String>[];
    await tester.pumpWidget(
      _app(
        _voiceComposer(
          controller: controller,
          state: VoiceInputState.recording,
          onVoiceStop: () => events.add('stop'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('🎙 正在聆听… 松开发送到输入框'), findsOneWidget);
    expect(controller.text, isEmpty);
    controller.dispose();
  });

  testWidgets('已有文字在语音状态下不被改动', (tester) async {
    final controller = TextEditingController(text: '已有内容');
    for (final state in <VoiceInputState>[
      VoiceInputState.idle,
      VoiceInputState.preparing,
      VoiceInputState.recording,
      VoiceInputState.recognizing,
      VoiceInputState.idle,
    ]) {
      await tester.pumpWidget(
        _app(_voiceComposer(controller: controller, state: state)),
      );
      await tester.pumpAndSettle();
      expect(controller.text, '已有内容', reason: '状态 $state 改动了输入框内容');
    }
    controller.dispose();
  });

  testWidgets('长按输入框触发语音开始，短按不触发', (tester) async {
    final controller = TextEditingController();
    final events = <String>[];
    await tester.pumpWidget(
      _app(
        _voiceComposer(
          controller: controller,
          state: VoiceInputState.idle,
          onVoiceStart: () => events.add('start'),
          onVoiceStop: () => events.add('stop'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 短按：不触发
    final center = tester.getCenter(find.byType(TextField));
    final shortPress = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 80));
    await shortPress.up();
    await tester.pumpAndSettle();
    expect(events, isEmpty);

    // 长按：触发
    final longPress = await tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 600));
    expect(events, <String>['start']);
    await longPress.up();
    await tester.pumpAndSettle();
    expect(events, <String>['start', 'stop']);
    controller.dispose();
  });

  testWidgets('普通点击仍然聚焦输入框（语音不改变点击行为）', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    await tester.pumpWidget(
      _app(
        ChatComposer(
          controller: controller,
          attachments: const [],
          isGenerating: false,
          attachmentsEnabled: true,
          deepThinkingEnabled: false,
          deepThinkingAvailable: true,
          modelLabel: 'Flash',
          onPickImage: () {},
          onRemoveAttachment: (_) {},
          onToggleDeepThinking: () {},
          onSelectModel: () {},
          onSend: () {},
          onStop: () {},
          voiceInputEnabled: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    // TextField 未显式传入 focusNode，这里用 EditableText 的焦点状态验证。
    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
    controller.dispose();
    focusNode.dispose();
  });
}
