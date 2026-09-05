import 'package:flutter/material.dart';

import '../theme/sunland_theme.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = widget.isStreaming
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.control),
          child: InkWell(
            key: const ValueKey('assistant-reasoning-toggle'),
            onTap: widget.onToggle,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
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
                    duration: AppMotion.micro,
                    curve: AppMotion.curve,
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
          duration: AppMotion.micro,
          curve: AppMotion.curve,
          alignment: Alignment.topLeft,
          child: widget.expanded && reasoning.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.xxs,
                    left: AppSpacing.xxs,
                    right: AppSpacing.xxs,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      child: Text(
                        reasoning,
                        key: const ValueKey('assistant-reasoning-content'),
                        style: TextStyle(
                          fontSize: AppTypography.captionSize,
                          height: 1.45,
                          color: colorScheme.onSurfaceVariant,
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
