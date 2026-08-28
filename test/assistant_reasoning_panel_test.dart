import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/widgets/assistant_reasoning_panel.dart';

void main() {
  testWidgets(
    'deep reasoning is collapsed by default and remains expandable when done',
    (tester) async {
      var expanded = false;
      var isStreaming = true;
      late StateSetter updatePanel;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                updatePanel = setState;
                return AssistantReasoningPanel(
                  reasoning: '先识别图片，再核对细节。',
                  expanded: expanded,
                  isStreaming: isStreaming,
                  isDark: false,
                  onToggle: () {
                    setState(() => expanded = !expanded);
                  },
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('正在思考'), findsOneWidget);
      expect(find.text('先识别图片，再核对细节。'), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey('assistant-reasoning-toggle')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('先识别图片，再核对细节。'), findsOneWidget);

      updatePanel(() => isStreaming = false);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('正在思考'), findsNothing);
      expect(find.text('思考过程'), findsOneWidget);
      expect(find.text('先识别图片，再核对细节。'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('assistant-reasoning-toggle')),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('先识别图片，再核对细节。'), findsNothing);
    },
  );
}
