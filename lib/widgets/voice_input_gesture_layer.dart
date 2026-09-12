import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 长按阈值比 Flutter `TextField` 内部的长按识别器早 [longPressSafetyMargin]。
///
/// `TextField` / `EditableText` 的长按识别器由 `TextSelectionGestureDetectorBuilder`
/// 创建（`packages/flutter/lib/src/widgets/text_selection.dart`），使用默认
/// `kLongPressTimeout`（500ms）。它一旦在竞技场中胜出就会执行
/// `renderEditable.selectWord(...)` 并触发 `Feedback.forLongPress`，也就是长按
/// 出现选择手柄与复制/粘贴菜单。
///
/// 我们的识别器位于更浅的 widget 层（因此更晚加入竞技场），无法靠加入顺序取胜，
/// 于是改用"更早达到 deadline"来先声明 accepted：竞技场一旦判定本识别器胜出，
/// `TextField` 的长按识别器会被其余成员否决，它的计时器随即失效，选择手柄、
/// 菜单与 iOS 悬浮光标都不会出现。
const Duration longPressSafetyMargin = Duration(milliseconds: 50);

/// 只响应触摸的长按识别器。
///
/// 与 `TextField` 移动端识别器保持一致的设备过滤（触摸）与按键过滤（沿用
/// `LongPressGestureRecognizer` 的默认行为），因此鼠标、触控笔、右键都不受影响。
class _TouchOnlyLongPressGestureRecognizer extends LongPressGestureRecognizer {
  /// 录音中放宽移动容差：按住后手指滑出输入框不应中断录音。
  _TouchOnlyLongPressGestureRecognizer({
    super.duration,
    required double postAcceptSlopTolerance,
    super.debugOwner,
  }) : super(
         supportedDevices: const <PointerDeviceKind>{PointerDeviceKind.touch},
         postAcceptSlopTolerance: postAcceptSlopTolerance,
       );
}

/// 把"长按输入框开始说话"接到现有输入框上，同时完整保留它的点击与编辑行为。
///
/// 关键设计（也是 Tap / LongPress 不互相污染的原因）：
/// - 只注册**长按**识别器，不注册 `TapGestureRecognizer`。普通点击继续由
///   `TextField` 自己的识别器在抬手时的 arena sweep 中胜出，所以聚焦、弹键盘、
///   "点哪光标落哪"、拖动选择手柄、双击选词全部保持原样。
/// - `HitTestBehavior.translucent` 让指针同时投递给本层与下层 `TextField`，
///   不使用 `AbsorbPointer` / `IgnorePointer`，命中测试链路不被破坏。
/// - 在 [longPressSafetyMargin] 内先胜出，从根上阻止 `TextField` 的长按副作用。
/// - [enabled] 为 false 时直接返回 child，渲染树与未接入语音时完全一致。
class VoiceInputGestureLayer extends StatefulWidget {
  const VoiceInputGestureLayer({
    required this.enabled,
    required this.onRecordingStart,
    required this.onRecordingEnd,
    required this.onRecordingCancel,
    required this.child,
    this.recording = false,
    super.key,
  });

  /// 是否接管长按。false 时本组件完全不参与手势，行为退化为普通 `TextField`。
  final bool enabled;

  /// 长按达到阈值，应该开始录音。
  final VoidCallback onRecordingStart;

  /// 松手，应该结束录音并识别。
  final VoidCallback onRecordingEnd;

  /// 手势在长按获准后被系统取消（例如被上层手势夺走）。
  ///
  /// 注意：普通点击时本识别器会输给 `TextField` 的点击识别器，`Flutter` 也会
  /// 回调这个cancel。调用方必须按自身状态决定是否忽略，避免"松手后意外触发一次 Tap"。
  final VoidCallback onRecordingCancel;

  /// 是否正处于录音状态。仅用于在录音期间放宽移动容差，让"按住后滑出输入框"
  /// 依然继续录音。
  final bool recording;

  final Widget child;

  @override
  State<VoiceInputGestureLayer> createState() => _VoiceInputGestureLayerState();
}

class _VoiceInputGestureLayerState extends State<VoiceInputGestureLayer> {
  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    // 比 TextField 内部的 kLongPressTimeout 更早。用户可感知的阈值仍在
    // 400~500ms 区间内，符合系统长按习惯，不会"刚按下就进录音"。
    final deadline = kLongPressTimeout - longPressSafetyMargin;
    // 录音中放宽移动容差，让"按住后滑出输入框"依然继续录音。
    final slopTolerance = widget.recording ? kTouchSlop * 4 : kTouchSlop * 2;

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: <Type, GestureRecognizerFactory>{
        _TouchOnlyLongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _TouchOnlyLongPressGestureRecognizer
            >(
              () => _TouchOnlyLongPressGestureRecognizer(
                duration: deadline,
                postAcceptSlopTolerance: slopTolerance,
                debugOwner: this,
              ),
              (recognizer) {
                recognizer.onLongPressStart = (_) => widget.onRecordingStart();
                recognizer.onLongPressEnd = (_) => widget.onRecordingEnd();
                recognizer.onLongPressCancel = widget.onRecordingCancel;
              },
            ),
      },
      child: widget.child,
    );
  }
}
