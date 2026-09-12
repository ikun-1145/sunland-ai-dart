import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/theme/sunland_theme.dart';
import 'package:sunland_ai_app/widgets/voice_input_gesture_layer.dart';

/// 记录语音层事件顺序的测试桩。
class _Recorder {
  final List<String> events = <String>[];

  void start() => events.add('start');
  void end() => events.add('end');
  void cancel() => events.add('cancel');
}

Future<void> _pump(
  WidgetTester tester, {
  required TextEditingController controller,
  required _Recorder recorder,
  FocusNode? focusNode,
  bool enabled = true,
  bool recording = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: SunlandTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            child: VoiceInputGestureLayer(
              enabled: enabled,
              recording: recording,
              onRecordingStart: recorder.start,
              onRecordingEnd: recorder.end,
              onRecordingCancel: recorder.cancel,
              child: TextField(controller: controller, focusNode: focusNode),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('长按超过阈值会触发开始录音，松手触发结束', (tester) async {
    final controller = TextEditingController();
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(recorder.events, <String>['start']);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(recorder.events, <String>['start', 'end']);
    controller.dispose();
  });

  testWidgets('短按在阈值内松手不会触发录音', (tester) async {
    final controller = TextEditingController();
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(recorder.events, isNot(contains('start')));
    controller.dispose();
  });

  testWidgets('普通点击仍然正常聚焦输入框（不破坏文字输入）', (tester) async {
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
    expect(recorder.events, isNot(contains('start')));
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('点击后可以正常输入文字并把内容写进 controller', (tester) async {
    final controller = TextEditingController();
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '正常文字输入');
    await tester.pump();

    expect(controller.text, '正常文字输入');
    expect(recorder.events, isNot(contains('start')));
    controller.dispose();
  });

  testWidgets('已有文字不会被长按语音流程清空', (tester) async {
    final controller = TextEditingController(text: '原有内容');
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.text, '原有内容');
    expect(recorder.events, contains('start'));
    expect(recorder.events, contains('end'));
    controller.dispose();
  });

  testWidgets('enabled 为 false 时长按完全不介入', (tester) async {
    final controller = TextEditingController();
    final recorder = _Recorder();

    await _pump(
      tester,
      controller: controller,
      recorder: recorder,
      enabled: false,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 800));
    await gesture.up();
    await tester.pumpAndSettle();

    // 语音层未启用时不注册长按识别器，长按只走 TextField 自身流程。
    expect(recorder.events, isEmpty);
    controller.dispose();
  });

  testWidgets('长按后小幅拖动仍然保持录音（默认移动容差）', (tester) async {
    final controller = TextEditingController();
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    final rect = tester.getRect(find.byType(TextField));
    final gesture = await tester.startGesture(tester.getCenter(find.byType(TextField)));
    await tester.pump(const Duration(milliseconds: 600));
    expect(recorder.events, <String>['start']);

    // 在默认 2x 触摸容差（36px）内移动，不应中断长按。
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(recorder.events.first, 'start');
    expect(recorder.events, contains('end'));
    // 仍留在输入框范围内，避免落到组件外触发 pointer cancel。
    expect(rect.width, greaterThan(40));
    controller.dispose();
  });

  testWidgets('录音状态放宽移动容差后可以拖得更远仍保持录音', (tester) async {
    final controller = TextEditingController();
    final recorder = _Recorder();

    await _pump(
      tester,
      controller: controller,
      recorder: recorder,
      recording: true,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(recorder.events, contains('start'));

    // 录音中容差为 4x 触摸容差（72px），60px 的移动不应中断录音。
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(recorder.events, contains('start'));
    expect(recorder.events, contains('end'));
    controller.dispose();
  });

  testWidgets('多次长按可以稳定重复触发（无状态残留）', (tester) async {
    final controller = TextEditingController();
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    for (var i = 0; i < 10; i++) {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(TextField)),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    expect(recorder.events.where((e) => e == 'start').length, 10);
    expect(recorder.events.where((e) => e == 'end').length, 10);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('长按过程中不会在输入框里产生文字选择', (tester) async {
    final controller = TextEditingController(text: '帮我查一下');
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 600));

    // 关键判据：TextField 的长按流程会执行 renderEditable.selectWord，
    // 把选区扩展成"一个词"。选区保持折叠即证明它没有抢到这次手势。
    expect(recorder.events, <String>['start']);
    expect(
      controller.selection.isCollapsed,
      isTrue,
      reason: '长按应被语音层接管，TextField 不应执行选词',
    );

    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      controller.selection.isCollapsed,
      isTrue,
      reason: '松手后也不应出现选择手柄对应的选区',
    );
    controller.dispose();
  });

  testWidgets('长按不会弹出复制/粘贴菜单', (tester) async {
    final controller = TextEditingController(text: '帮我查一下');
    final recorder = _Recorder();

    await _pump(tester, controller: controller, recorder: recorder);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    // 菜单与手柄都只在"存在非折叠选区"时才可能出现。
    expect(controller.selection.isCollapsed, isTrue);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w.runtimeType.toString().contains('TextSelectionToolbar') ||
            w.runtimeType.toString().contains('AdaptiveTextSelectionToolbar') ||
            w.runtimeType.toString().contains('CupertinoTextSelectionToolbar'),
      ),
      findsNothing,
      reason: '长按语音不应出现系统选择工具栏',
    );
    controller.dispose();
  });

  testWidgets('长按不会弹出键盘（TextField 未获得焦点）', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final recorder = _Recorder();

    await _pump(
      tester,
      controller: controller,
      recorder: recorder,
      focusNode: focusNode,
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(TextField)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();

    // 语音层不注册 Tap 识别器，因此长按不会让输入框获得焦点、不会拉起键盘。
    expect(focusNode.hasFocus, isFalse);
    expect(recorder.events, <String>['start', 'end']);
    controller.dispose();
    focusNode.dispose();
  });
}
