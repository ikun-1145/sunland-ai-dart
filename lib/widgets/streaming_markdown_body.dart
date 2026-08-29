import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Keeps Markdown formatting intact while newly streamed glyphs settle from a
/// soft, translucent state to their final contrast.
class StreamingMarkdownBody extends StatefulWidget {
  const StreamingMarkdownBody({
    required this.data,
    required this.styleSheet,
    required this.isStreaming,
    super.key,
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final bool isStreaming;

  @override
  State<StreamingMarkdownBody> createState() => _StreamingMarkdownBodyState();
}

class _StreamingMarkdownBodyState extends State<StreamingMarkdownBody>
    with SingleTickerProviderStateMixin {
  static const _revealDuration = Duration(milliseconds: 240);
  late final AnimationController _revealController;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      duration: _revealDuration,
      value: widget.isStreaming && widget.data.isNotEmpty ? 0 : 1,
      vsync: this,
    );
    if (widget.isStreaming && widget.data.isNotEmpty) {
      _revealController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant StreamingMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    final appendedText =
        widget.data.length > oldWidget.data.length &&
        widget.data.startsWith(oldWidget.data);
    if (widget.isStreaming && appendedText) {
      _revealController.forward(from: 0);
    } else if (!widget.isStreaming && oldWidget.isStreaming) {
      _revealController.value = 1;
    }
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final markdown = MarkdownBody(
      data: widget.data,
      styleSheet: widget.styleSheet,
    );
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations == true;
    if (!widget.isStreaming || reduceMotion || widget.data.isEmpty) {
      return markdown;
    }

    return AnimatedBuilder(
      animation: _revealController,
      child: markdown,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(_revealController.value);
        final tailOpacity = 0.32 + (0.68 * progress);
        return ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            final tailHeight = bounds.height.clamp(0, 30).toDouble();
            final tailStart = bounds.height == 0
                ? 0.0
                : ((bounds.height - tailHeight) / bounds.height).clamp(
                    0.0,
                    1.0,
                  );
            final transitionStart = (tailStart - 0.025).clamp(0.0, 1.0);
            return LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white,
                Colors.white,
                Colors.white.withValues(alpha: tailOpacity),
                Colors.white.withValues(alpha: tailOpacity),
              ],
              stops: [0, transitionStart, tailStart, 1],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}
