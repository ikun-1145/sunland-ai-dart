import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/network_unavailable_page.dart';
import 'package:sunland_ai_app/theme/sunland_theme.dart';
import 'package:sunland_ai_app/widgets/streaming_markdown_body.dart';

void main() {
  group('SunlandTheme', () {
    test('keeps primary dark surfaces and text at accessible contrast', () {
      final scheme = SunlandTheme.dark.colorScheme;

      expect(_contrastRatio(scheme.onSurface, scheme.surface), greaterThan(7));
      expect(
        _contrastRatio(scheme.onSurfaceVariant, scheme.surfaceContainer),
        greaterThan(4.5),
      );
    });

    test('styles transient Android surfaces consistently', () {
      final theme = SunlandTheme.dark;

      expect(theme.useMaterial3, isTrue);
      expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(theme.snackBarTheme.shape, isA<RoundedRectangleBorder>());
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(theme.bottomSheetTheme.showDragHandle, isTrue);
      expect(theme.popupMenuTheme.elevation, 0);
    });
  });

  group('StreamingMarkdownBody', () {
    testWidgets('applies a soft reveal only while content is streaming', (
      tester,
    ) async {
      await tester.pumpWidget(
        _testApp(
          child: StreamingMarkdownBody(
            data: '第一段回答',
            styleSheet: MarkdownStyleSheet(),
            isStreaming: true,
          ),
        ),
      );

      expect(find.byType(ShaderMask), findsOneWidget);

      await tester.pumpWidget(
        _testApp(
          child: StreamingMarkdownBody(
            data: '第一段回答，继续补充。',
            styleSheet: MarkdownStyleSheet(),
            isStreaming: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      expect(find.byType(ShaderMask), findsOneWidget);

      await tester.pumpWidget(
        _testApp(
          child: StreamingMarkdownBody(
            data: '第一段回答，继续补充。',
            styleSheet: MarkdownStyleSheet(),
            isStreaming: false,
          ),
        ),
      );

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('disables reveal when the platform requests reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _testApp(
          mediaQuery: const MediaQueryData(disableAnimations: true),
          child: StreamingMarkdownBody(
            data: '减少动态效果',
            styleSheet: MarkdownStyleSheet(),
            isStreaming: true,
          ),
        ),
      );

      expect(find.byType(ShaderMask), findsNothing);
      expect(find.text('减少动态效果'), findsOneWidget);
    });
  });

  testWidgets('offline state follows the dark surface and text palette', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SunlandTheme.dark,
        home: NetworkUnavailablePage(isChecking: false, onRetry: () async {}),
      ),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    final title = tester.widget<Text>(find.text('网络连接异常'));
    final description = tester.widget<Text>(find.text('请检查网络设置，连接正常后再刷新。'));

    expect(scaffold.backgroundColor, SunlandTheme.dark.colorScheme.surface);
    expect(title.style?.color, SunlandTheme.dark.colorScheme.onSurface);
    expect(
      description.style?.color,
      SunlandTheme.dark.colorScheme.onSurfaceVariant,
    );
  });
}

Widget _testApp({required Widget child, MediaQueryData? mediaQuery}) {
  return MaterialApp(
    theme: SunlandTheme.light,
    home: Scaffold(
      body: MediaQuery(
        data: mediaQuery ?? const MediaQueryData(),
        child: child,
      ),
    ),
  );
}

double _contrastRatio(Color foreground, Color background) {
  final lighter = foreground.computeLuminance() > background.computeLuminance()
      ? foreground
      : background;
  final darker = lighter == foreground ? background : foreground;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}
