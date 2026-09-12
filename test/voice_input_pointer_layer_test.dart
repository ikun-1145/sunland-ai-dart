import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/theme/sunland_theme.dart';
import 'package:sunland_ai_app/widgets/voice_input_pointer_layer.dart';

/// 记录语音层事件顺序的测试桩。
class _Recorder {
  final List<String> events = <String>[];
  final List<bool> activeChanges = <bool>[];

  void start() => events.add('start');
  void end() => events.add('end');
  void cancel() => events.add('cancel');
  void activeChanged(bool value) => activeChanges.add(value);
}

const _threshold = Duration(milliseconds: 200);

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  required _Recorder recorder,
  FocusNode? focusNode,
  bool enabled = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SunlandTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: VoiceInputPointerLayer(
              enabled: enabled,
              threshold: _threshold,
              onRecordingStart: recorder.start,
              onRecordingEnd: recorder.end,
              onRecordingCancel: recorder.cancel,
              onVoiceActiveChanged: recorder.activeChanged,
              child: TextField(controller: controller, focusNode: focusNode),
            ),
          ),
        ),
      ),
    ),
  );
}

/// 按住 [hold] 之久后松手。
Future<void> _press(
  WidgetTester tester,
  Duration hold, {
  Offset? moveBy,
}) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(TextField)),
    kind: PointerDeviceKind.touch,
  );
  if (moveBy != null) {
    await tester.pump(const Duration(milliseconds: 40));
    await gesture.moveBy(moveBy);
  }
  await tester.pump(hold);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('长按触发语音', () {
    testWidgets('按住超过阈值触发开始，松手触发结束', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(_threshold + const Duration(milliseconds: 60));

      expect(recorder.events, <String>['start']);
      // 激活时通知外层关闭交互式选择（用于抑制选词菜单）。
      expect(recorder.activeChanges, <bool>[true]);

      await gesture.up();
      await tester.pumpAndSettle();

      expect(recorder.events, <String>['start', 'end']);
      expect(recorder.activeChanges, <bool>[true, false]);
      controller.dispose();
    });

    testWidgets('阈值内松手完全不触发语音（普通点击）', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      await _press(tester, const Duration(milliseconds: 60));

      expect(recorder.events, isEmpty);
      expect(recorder.activeChanges, isEmpty);
      controller.dispose();
    });

    testWidgets('恰好等于阈值时松手不触发（边界）', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      await _press(tester, _threshold - const Duration(milliseconds: 10));

      expect(recorder.events, isEmpty);
      controller.dispose();
    });

    testWidgets('鼠标按住不触发语音（只处理 touch）', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(_threshold + const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(recorder.events, isEmpty);
      controller.dispose();
    });

    testWidgets('激活前超出容差移动会取消长按判定', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.moveBy(const Offset(0, 80)); // 远超 kTouchSlop
      await tester.pump(_threshold + const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(recorder.events, isEmpty);
      controller.dispose();
    });

    testWidgets('激活后手指滑出输入框仍继续录音，直到松手', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(_threshold + const Duration(milliseconds: 60));
      expect(recorder.events, <String>['start']);

      await gesture.moveBy(const Offset(0, 200)); // 滑出很远
      await tester.pump(const Duration(milliseconds: 80));
      expect(recorder.events, <String>['start']);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(recorder.events, <String>['start', 'end']);
      controller.dispose();
    });

    testWidgets('系统取消已激活的语音时回调 cancel', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(_threshold + const Duration(milliseconds: 60));
      expect(recorder.events, <String>['start']);

      await gesture.cancel();
      await tester.pumpAndSettle();

      expect(recorder.events, <String>['start', 'cancel']);
      expect(recorder.activeChanges, <bool>[true, false]);
      controller.dispose();
    });

    testWidgets('连续 10 次长按稳定触发，无状态残留', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      for (var i = 0; i < 10; i++) {
        await _press(tester, _threshold + const Duration(milliseconds: 60));
      }

      expect(recorder.events.where((e) => e == 'start').length, 10);
      expect(recorder.events.where((e) => e == 'end').length, 10);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });

    testWidgets('enabled=false 时不注册任何指针回调', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(
        tester,
        controller: controller,
        recorder: recorder,
        enabled: false,
      );

      await _press(tester, _threshold + const Duration(milliseconds: 200));

      expect(recorder.events, isEmpty);
      controller.dispose();
    });
  });

  group('不破坏 TextField 原生行为', () {
    testWidgets('普通点击仍然聚焦并弹出键盘', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();
      final recorder = _Recorder();
      await _pump(
        tester,
        controller: controller,
        recorder: recorder,
        focusNode: focusNode,
      );

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      expect(focusNode.hasFocus, isTrue);
      expect(recorder.events, isEmpty);
      controller.dispose();
      focusNode.dispose();
    });

    testWidgets('点击后可以正常输入文字', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '正常文字输入');
      await tester.pump();

      expect(controller.text, '正常文字输入');
      expect(recorder.events, isEmpty);
      controller.dispose();
    });

    testWidgets('长按流程不会清空已有文字', (tester) async {
      final controller = TextEditingController(text: '原有内容');
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      await _press(tester, _threshold + const Duration(milliseconds: 60));

      expect(controller.text, '原有内容');
      controller.dispose();
    });

    testWidgets('长按不会让 TextField 产生选词（选区保持折叠）', (tester) async {
      final controller = TextEditingController(text: '帮我查一下');
      final recorder = _Recorder();
      await _pump(tester, controller: controller, recorder: recorder);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 900)); // 越过 500ms
      final duringHold = controller.selection.isCollapsed;

      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        duringHold,
        isTrue,
        reason: '语音激活后应关闭交互式选择，不产生选词',
      );
      expect(controller.selection.isCollapsed, isTrue);
      controller.dispose();
    });
  });

  group('布局中立', () {
    testWidgets('长按区域只覆盖 TextField，不波及下方按钮', (tester) async {
      final controller = TextEditingController();
      final recorder = _Recorder();
      final focusNode = FocusNode();
      var buttonTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: SunlandTheme.light,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VoiceInputPointerLayer(
                      enabled: true,
                      threshold: _threshold,
                      onRecordingStart: recorder.start,
                      onRecordingEnd: recorder.end,
                      onRecordingCancel: recorder.cancel,
                      onVoiceActiveChanged: recorder.activeChanged,
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                      ),
                    ),
                    FilledButton(
                      onPressed: () => buttonTaps += 1,
                      child: const Text('发送'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // 长按下方按钮：不应触发语音（Listener 只在 TextField 区域命中）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('发送')),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(_threshold + const Duration(milliseconds: 150));
      expect(recorder.events, isEmpty, reason: '按钮区域不应触发语音');
      expect(recorder.activeChanges, isEmpty);
      await gesture.up();
      await tester.pumpAndSettle();
      // 该次抬起本身就是一次正常点击，按钮必须照常响应。
      expect(buttonTaps, 1, reason: '按钮未被语音层拦截');
      controller.dispose();
      focusNode.dispose();
    });
  });
}
