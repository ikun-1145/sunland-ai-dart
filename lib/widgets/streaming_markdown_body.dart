import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Renders streaming Markdown without introducing an extra compositing layer.
class StreamingMarkdownBody extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MarkdownBody(data: data, styleSheet: styleSheet);
  }
}
