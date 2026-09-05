import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/sunland_theme.dart';

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.controller,
    required this.attachments,
    required this.isGenerating,
    required this.attachmentsEnabled,
    required this.deepThinkingEnabled,
    required this.deepThinkingAvailable,
    required this.modelLabel,
    required this.onPickImage,
    required this.onRemoveAttachment,
    required this.onToggleDeepThinking,
    required this.onSelectModel,
    required this.onSend,
    required this.onStop,
    super.key,
  });

  final TextEditingController controller;
  final List<String> attachments;
  final bool isGenerating;
  final bool attachmentsEnabled;
  final bool deepThinkingEnabled;
  final bool deepThinkingAvailable;
  final String modelLabel;
  final VoidCallback onPickImage;
  final ValueChanged<int> onRemoveAttachment;
  final VoidCallback onToggleDeepThinking;
  final VoidCallback onSelectModel;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refreshSendState);
  }

  @override
  void didUpdateWidget(covariant ChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_refreshSendState);
      widget.controller.addListener(_refreshSendState);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshSendState);
    super.dispose();
  }

  void _refreshSendState() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final canSend =
        widget.controller.text.trim().isNotEmpty ||
        (widget.attachmentsEnabled && widget.attachments.isNotEmpty);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Material(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.input),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.input),
              border: Border.all(color: colorScheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.attachments.isNotEmpty) ...[
                  SizedBox(
                    height: 80,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      itemCount: widget.attachments.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: AppSpacing.xs),
                      itemBuilder: (context, index) => _AttachmentPreview(
                        path: widget.attachments[index],
                        onRemove: () => widget.onRemoveAttachment(index),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                TextField(
                  controller: widget.controller,
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: AppTypography.supportingSize,
                    height: 1.45,
                  ),
                  decoration: const InputDecoration(
                    hintText: '输入消息…',
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    IconButton(
                      tooltip: widget.attachmentsEnabled
                          ? '拍照或选择图片'
                          : 'Sunland AI 暂不支持文件上传',
                      onPressed: widget.attachmentsEnabled
                          ? widget.onPickImage
                          : null,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                    ),
                    FilterChip(
                      avatar: Icon(
                        widget.deepThinkingAvailable
                            ? Icons.psychology_outlined
                            : Icons.lock_outline,
                        size: 16,
                      ),
                      label: const Text('深度思考'),
                      selected: widget.deepThinkingEnabled,
                      onSelected: widget.attachmentsEnabled
                          ? (_) => widget.onToggleDeepThinking()
                          : null,
                      showCheckmark: false,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.tune, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 128),
                        child: Text(
                          widget.modelLabel,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      onPressed: widget.onSelectModel,
                    ),
                    IconButton.filled(
                      key: const ValueKey('chat-composer-action'),
                      tooltip: widget.isGenerating ? '停止生成' : '发送',
                      onPressed: widget.isGenerating
                          ? widget.onStop
                          : (canSend ? widget.onSend : null),
                      icon: Icon(
                        widget.isGenerating
                            ? Icons.stop_rounded
                            : Icons.arrow_upward,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.path, required this.onRemove});

  final String path;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '移除附件',
      button: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.image),
            child: Image.file(
              File(path),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              cacheWidth: 216,
              errorBuilder: (_, _, _) => Container(
                width: 72,
                height: 72,
                color: colorScheme.surfaceContainerHigh,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined),
              ),
            ),
          ),
          Positioned(
            right: -8,
            top: -8,
            child: IconButton.filledTonal(
              tooltip: '移除图片',
              iconSize: 16,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
              onPressed: onRemove,
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }
}
