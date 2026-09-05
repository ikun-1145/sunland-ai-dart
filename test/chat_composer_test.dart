import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}

Widget _app(Widget child) => MaterialApp(
  theme: SunlandTheme.light,
  home: Scaffold(body: child),
);
