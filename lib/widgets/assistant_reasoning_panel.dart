import 'package:flutter/material.dart';

class AssistantReasoningPanel extends StatefulWidget {
  const AssistantReasoningPanel({
    required this.reasoning,
    required this.expanded,
    required this.isStreaming,
    required this.isDark,
    required this.onToggle,
    super.key,
  });

  final String reasoning;
  final bool expanded;
  final bool isStreaming;
  final bool isDark;
  final VoidCallback onToggle;

  @override
  State<AssistantReasoningPanel> createState() =>
      _AssistantReasoningPanelState();
}

class _AssistantReasoningPanelState extends State<AssistantReasoningPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;
  late final Animation<double> _blinkOpacity;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );
    _blinkOpacity = Tween<double>(begin: 0.35, end: 1).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AssistantReasoningPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isStreaming != widget.isStreaming) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.isStreaming) {
      _blinkController.repeat(reverse: true);
    } else {
      _blinkController
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reasoning = widget.reasoning.trim();
    final foreground = widget.isStreaming
        ? const Color(0xFF22D3EE)
        : (widget.isDark ? Colors.white60 : Colors.black54);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: widget.isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            key: const ValueKey('assistant-reasoning-toggle'),
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isStreaming)
                    FadeTransition(
                      opacity: _blinkOpacity,
                      child: Text(
                        '正在思考',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: foreground,
                        ),
                      ),
                    )
                  else
                    Text(
                      '思考过程',
                      style: TextStyle(fontSize: 13, color: foreground),
                    ),
                  const SizedBox(width: 3),
                  AnimatedRotation(
                    turns: widget.expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Icon(
                      Icons.chevron_right,
                      size: 17,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          alignment: Alignment.topLeft,
          child: widget.expanded && reasoning.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 4, left: 2, right: 4),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        reasoning,
                        key: const ValueKey('assistant-reasoning-content'),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.25,
                          color: widget.isDark
                              ? Colors.white54
                              : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}
