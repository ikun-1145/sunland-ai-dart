import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 长按触发语音输入的阈值。
///
/// 取值 450ms：符合系统长按习惯（不早于用户预期的长按），同时略早于
/// `TextField` 内部 `kLongPressTimeout`（500ms）。注意这里**不依赖**这个 50ms
/// 差值去"抢 gesture arena"——见 [VoiceInputPointerLayer] 的说明。
const Duration voiceLongPressThreshold = Duration(milliseconds: 450);

/// 长按输入框开始说话 —— 纯旁路 pointer 跟踪实现。
///
/// ## 为什么不竞争 gesture arena
///
/// 早期实现用 `RawGestureDetector` + `LongPressGestureRecognizer(450ms)`，指望靠
/// "比 `TextField` 内部 500ms 更早达到 deadline"取胜。这在真机上不可靠，原因是
/// `LongPressGestureRecognizer` 覆写了 `acceptGesture`（`gestures/long_press.dart`）
/// 且 **不关心自己是否赢得竞技场**：
///
/// ```dart
/// void didExceedDeadline() {
///   resolve(GestureDisposition.accepted);
///   _longPressAccepted = true;
///   super.acceptGesture(primaryPointer!);
///   _checkLongPressStart();   // ← 无论输赢都会触发
/// }
/// ```
///
/// 也就是说：只要双方 timer 都跑到了，`TextField` 的选词流程照样会执行；谁先到达
/// 只取决于 `Timer` 调度与竞技场成员顺序，属于竞态而非保证。真机上该竞态经常
/// 让本层的回调根本没机会生效，表现为"长按完全没反应/弹选词菜单"。
///
/// ## 本实现的做法
///
/// 用 [Listener] **只观察**原始 `PointerEvent`，完全不注册任何 `GestureRecognizer`，
/// 因此不进入 gesture arena、不与 `TextField` 争抢，也就没有竞态：
///
/// - `onPointerDown`：只认 [PointerDeviceKind.touch]；记下 pointer id 与起点；
///   启动 [voiceLongPressThreshold] 计时；**不拦截事件**，`TextField` 照常收到
///   按下、聚焦、定位光标。
/// - 阈值前松手 / 超出手指容差：取消计时，什么都不做 —— 行为等同普通 `TextField`。
/// - 到达阈值：置 `activated = true`，通过 [onVoiceActiveChanged] 通知外层
///   （外层据此临时关闭该 `TextField` 的 interactive selection 与选择菜单，
///   从根上避免选词手柄 / 复制粘贴菜单），然后回调 [onRecordingStart]。
/// - `onPointerUp`：若已激活 → [onRecordingEnd]；否则什么都不做（普通点击）。
/// - `onPointerCancel`：已激活 → [onRecordingCancel]；否则仅取消计时。
/// - 移动：激活前超过 touch slop 视为滚动/拖动，取消计时；**激活后不再因移动取消**，
///   手指滑出输入框也继续录音直到松开。
///
/// ## 布局中立
///
/// [Listener] 是单子 `SingleChildRenderObjectWidget`，只把约束原样下传，不改变
/// 尺寸、padding、margin 或 Column/Row 关系；也不使用 `AbsorbPointer` /
/// `IgnorePointer`，普通点击始终完全由原 `TextField` 处理。
class VoiceInputPointerLayer extends StatefulWidget {
  const VoiceInputPointerLayer({
    required this.enabled,
    required this.onRecordingStart,
    required this.onRecordingEnd,
    required this.onRecordingCancel,
    required this.onVoiceActiveChanged,
    required this.child,
    this.threshold = voiceLongPressThreshold,
    this.touchSlop,
    super.key,
  });

  /// 是否接管长按。为 false 时不注册任何指针回调，渲染树与未接入语音时完全一致。
  final bool enabled;

  /// 按住达到阈值：开始录音。
  final VoidCallback onRecordingStart;

  /// 录音中松手：结束录音并识别。
  final VoidCallback onRecordingEnd;

  /// 系统取消（被上层抢走、来电等）：放弃本次录音。
  final VoidCallback onRecordingCancel;

  /// 语音按下状态变化。
  ///
  /// 外层据此临时关闭该 `TextField` 的 interactive selection 与选择菜单，
  /// 避免按住满 500ms 后 `TextField` 弹出选词手柄 / 复制粘贴菜单。
  final ValueChanged<bool> onVoiceActiveChanged;

  final Widget child;

  /// 长按阈值，测试可覆盖以缩短用时。
  final Duration threshold;

  /// 手指容差，默认取 `kTouchSlop`。测试可覆盖。
  final double? touchSlop;

  @override
  State<VoiceInputPointerLayer> createState() => _VoiceInputPointerLayerState();
}

class _VoiceInputPointerLayerState extends State<VoiceInputPointerLayer> {
  /// 当前正在跟踪的触摸 pointer。
  int? _pointerId;
  Offset? _origin;

  /// 已经越过阈值并进入语音状态。
  bool _activated = false;

  Timer? _timer;

  @override
  void didUpdateWidget(covariant VoiceInputPointerLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 语音被关闭（例如页面切走）时立即收尾，避免残留激活状态。
    if (!widget.enabled && oldWidget.enabled) {
      _abort(notify: true);
    }
  }

  @override
  void dispose() {
    _abort(notify: false);
    super.dispose();
  }

  double get _slop => widget.touchSlop ?? kTouchSlop;

  void _abort({required bool notify}) {
    _timer?.cancel();
    _timer = null;
    _pointerId = null;
    _origin = null;
    if (_activated) {
      _activated = false;
      if (notify && mounted) widget.onVoiceActiveChanged(false);
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    // 只处理手指触摸：鼠标、触控笔、右键都不触发语音。
    if (event.kind != PointerDeviceKind.touch) return;
    // 已经有一根手指在跟踪时不接受第二根，避免多指互相干扰。
    if (_pointerId != null) return;

    _pointerId = event.pointer;
    _origin = event.position;
    _activated = false;
    _timer?.cancel();
    _timer = Timer(widget.threshold, _onThresholdReached);
  }

  void _onThresholdReached() {
    _timer = null;
    if (!mounted || !widget.enabled) return;
    if (_pointerId == null) return;

    _activated = true;
    setState(() {});
    // 先让外层关掉该 TextField 的交互式选择，再开始录音：
    // 这样即使 TextField 内部的 500ms 长按计时器随后触发，也会在
    // `TextSelectionGestureDetectorBuilder.onSingleLongTapStart` 的
    // `delegate.selectionEnabled` 守卫处提前返回，不产生选词与菜单。
    widget.onVoiceActiveChanged(true);
    widget.onRecordingStart();
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointerId) return;
    // 激活后允许手指滑出输入框，继续录音直到松开。
    if (_activated) return;
    final origin = _origin;
    if (origin == null) return;
    // 激活前超出容差视为滚动/拖动，放弃长按判定，交回 TextField 原生行为。
    if ((event.position - origin).distance > _slop) {
      _abort(notify: false);
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.pointer != _pointerId) return;
    final wasActivated = _activated;
    _timer?.cancel();
    _timer = null;
    _pointerId = null;
    _origin = null;

    if (!wasActivated) {
      // 阈值前松手：等同普通点击，不做任何事（TextField 已自行处理）。
      return;
    }
    _activated = false;
    setState(() {});
    widget.onVoiceActiveChanged(false);
    widget.onRecordingEnd();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointerId) return;
    final wasActivated = _activated;
    _abort(notify: true);
    if (wasActivated) widget.onRecordingCancel();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return Listener(
      // deferToChild：只在 TextField 实际命中的区域接收指针事件，
      // 因此长按图片 / 深度思考 / 模型选择 / 发送按钮不会触发语音。
      behavior: HitTestBehavior.deferToChild,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
