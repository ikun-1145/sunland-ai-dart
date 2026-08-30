import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../sunland_beta_diagnostics.dart';
import '../sunland_remote_provider.dart';

typedef CurrentUserIdProvider = String? Function();
typedef KnowledgeLoader = Future<List<SunlandKnowledgeRecord>> Function();
typedef KnowledgeDelete = Future<void> Function(String id);
typedef DiagnosticsJsonExporter = Future<bool> Function(String json);

class SunlandDataManagementCard extends StatefulWidget {
  const SunlandDataManagementCard({
    super.key,
    required this.userId,
    required this.currentUserIdProvider,
    required this.loadKnowledge,
    required this.deleteKnowledge,
    required this.deleteAllKnowledge,
    required this.deleteRememberedName,
  });

  final String userId;
  final CurrentUserIdProvider currentUserIdProvider;
  final KnowledgeLoader loadKnowledge;
  final KnowledgeDelete deleteKnowledge;
  final Future<void> Function() deleteAllKnowledge;
  final Future<void> Function() deleteRememberedName;

  @override
  State<SunlandDataManagementCard> createState() =>
      _SunlandDataManagementCardState();
}

class _SunlandDataManagementCardState extends State<SunlandDataManagementCard> {
  List<SunlandKnowledgeRecord> _records = const <SunlandKnowledgeRecord>[];
  bool _loading = true;
  bool _readable = false;
  bool _busy = false;
  String? _status;
  int _loadGeneration = 0;

  bool get _identityIsCurrent =>
      widget.currentUserIdProvider() == widget.userId;

  @override
  void initState() {
    super.initState();
    _refreshKnowledge();
  }

  @override
  void didUpdateWidget(covariant SunlandDataManagementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId == widget.userId) return;
    _loadGeneration += 1;
    _records = const <SunlandKnowledgeRecord>[];
    _readable = false;
    _loading = true;
    _status = null;
    _refreshKnowledge();
  }

  Future<void> _refreshKnowledge({bool showLoading = true}) async {
    final userId = widget.userId;
    final generation = ++_loadGeneration;
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final records = await widget.loadKnowledge();
      if (!mounted ||
          generation != _loadGeneration ||
          widget.userId != userId ||
          !_identityIsCurrent) {
        return;
      }
      setState(() {
        _records = records;
        _readable = true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted ||
          generation != _loadGeneration ||
          widget.userId != userId ||
          !_identityIsCurrent) {
        return;
      }
      setState(() {
        _records = const <SunlandKnowledgeRecord>[];
        _readable = false;
        _loading = false;
      });
    }
  }

  Future<bool> _confirm({
    required String message,
    required String actionLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('请确认'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return mounted && confirmed == true;
  }

  Future<void> _runDangerous({
    required String confirmation,
    required String actionLabel,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    if (_busy || !_identityIsCurrent) return;
    if (!await _confirm(message: confirmation, actionLabel: actionLabel)) {
      return;
    }
    if (!_identityIsCurrent) {
      if (mounted) setState(() => _status = '登录身份已切换，请重新打开设置页。');
      return;
    }

    final userId = widget.userId;
    setState(() {
      _busy = true;
      _status = '正在处理，请稍候。';
    });
    try {
      await action();
      if (!mounted || widget.userId != userId || !_identityIsCurrent) return;
      await _refreshKnowledge(showLoading: false);
      if (!mounted || widget.userId != userId || !_identityIsCurrent) return;
      setState(() => _status = successMessage);
    } catch (_) {
      if (!mounted || widget.userId != userId || !_identityIsCurrent) return;
      setState(() => _status = '暂时无法完成这个操作，请稍后再试。');
    } finally {
      if (mounted && widget.userId == userId) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final countLabel = _loading
        ? '正在读取'
        : !_readable
        ? '暂时无法读取'
        : _records.length == 100
        ? '已显示前 100 条'
        : '共 ${_records.length} 条';

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _DataActionRow(
            icon: Icons.person_outline,
            title: '姓名记忆',
            subtitle: '只让 Sunland AI 忘记你的名字',
            buttonLabel: '清除姓名',
            enabled: !_busy && _identityIsCurrent,
            onPressed: () => _runDangerous(
              confirmation: '确定让 Sunland AI 忘记你的名字吗？聊天记录不会受到影响。',
              actionLabel: '清除',
              action: widget.deleteRememberedName,
              successMessage: 'Sunland AI 已忘记你的名字，聊天记录没有受到影响。',
            ),
          ),
          const Divider(height: 1, indent: 56),
          _DataActionRow(
            icon: Icons.psychology_outlined,
            title: '用户教学知识',
            subtitle: '清除你主动教给 Sunland AI 的知识',
            buttonLabel: '清除知识',
            enabled: !_busy && _readable && _records.isNotEmpty,
            onPressed: () => _runDangerous(
              confirmation: '确定清除你教给 Sunland AI 的全部知识吗？系统内置知识和聊天记录不会受到影响。',
              actionLabel: '清除',
              action: widget.deleteAllKnowledge,
              successMessage: '你教给 Sunland AI 的知识已清除。',
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '已教给 Sunland AI 的知识',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(
                      countLabel,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新教学知识',
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy || _loading || !_identityIsCurrent
                          ? null
                          : _refreshKnowledge,
                      icon: const Icon(Icons.refresh, size: 19),
                    ),
                  ],
                ),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (!_readable || _records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      _readable ? '暂无用户教学知识' : '暂时无法读取教学知识，请稍后再试。',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _records.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final record = _records[index];
                        return Row(
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                ),
                                child: Text(record.label),
                              ),
                            ),
                            TextButton(
                              onPressed: _busy || !_identityIsCurrent
                                  ? null
                                  : () => _runDangerous(
                                      confirmation:
                                          '确定删除“${record.label}”吗？删除后无法恢复。',
                                      actionLabel: '删除',
                                      action: () =>
                                          widget.deleteKnowledge(record.id),
                                      successMessage: '这条教学知识已删除。',
                                    ),
                              child: const Text('删除'),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                if (_status != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _status!,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DataActionRow extends StatelessWidget {
  const _DataActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    required this.enabled,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String buttonLabel;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: OutlinedButton(
        onPressed: enabled ? onPressed : null,
        child: Text(buttonLabel),
      ),
    );
  }
}

class SunlandBetaDiagnosticsCard extends StatefulWidget {
  const SunlandBetaDiagnosticsCard({
    super.key,
    required this.userId,
    required this.currentUserIdProvider,
    required this.store,
    this.exportJson,
  });

  final String userId;
  final CurrentUserIdProvider currentUserIdProvider;
  final SunlandBetaDiagnosticsStore store;
  final DiagnosticsJsonExporter? exportJson;

  @override
  State<SunlandBetaDiagnosticsCard> createState() =>
      _SunlandBetaDiagnosticsCardState();
}

class _SunlandBetaDiagnosticsCardState
    extends State<SunlandBetaDiagnosticsCard> {
  SunlandBetaDiagnosticsState? _state;
  bool _loading = true;
  bool _busy = false;
  bool _expanded = false;
  String? _status;
  int _loadGeneration = 0;

  bool get _identityIsCurrent =>
      widget.currentUserIdProvider() == widget.userId;

  @override
  void initState() {
    super.initState();
    _load(includeSnapshot: false);
  }

  @override
  void didUpdateWidget(covariant SunlandBetaDiagnosticsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId == widget.userId) return;
    _loadGeneration += 1;
    _state = null;
    _loading = true;
    _status = null;
    _load(includeSnapshot: _expanded);
  }

  Future<SunlandBetaDiagnosticsState?> _load({
    required bool includeSnapshot,
    bool showLoading = true,
  }) async {
    final userId = widget.userId;
    final generation = ++_loadGeneration;
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final state = await widget.store.load(
        userId,
        includeSnapshot: includeSnapshot,
      );
      if (!mounted ||
          generation != _loadGeneration ||
          widget.userId != userId ||
          !_identityIsCurrent) {
        return null;
      }
      setState(() {
        _state = state;
        _loading = false;
        if (state.resetCorruptSnapshot) {
          _status = '本地诊断数据已重置。';
        }
      });
      return state;
    } catch (_) {
      if (!mounted ||
          generation != _loadGeneration ||
          widget.userId != userId ||
          !_identityIsCurrent) {
        return null;
      }
      setState(() {
        _loading = false;
        _status = '本地诊断设置暂时不可用，其他设置不受影响。';
      });
      return null;
    }
  }

  Future<bool> _confirm({
    required String message,
    required String actionLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('请确认'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return mounted && confirmed == true;
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_busy || !_identityIsCurrent) return;
    if (enabled &&
        !await _confirm(
          message: '开启后，只会在此设备保存匿名聚合数据，不会自动上传。确定参与本地 Beta 诊断吗？',
          actionLabel: '开启',
        )) {
      return;
    }
    if (!_identityIsCurrent) return;

    final userId = widget.userId;
    setState(() => _busy = true);
    try {
      await widget.store.setEnabled(userId, enabled);
      if (!mounted || widget.userId != userId || !_identityIsCurrent) return;
      final state = await _load(includeSnapshot: true, showLoading: false);
      if (!mounted || state == null) return;
      setState(() {
        _status = enabled
            ? '已开启本地 Beta 诊断。当前不会自动上传任何数据。'
            : '已停止本地诊断。之前保存的诊断数据仍保留，可使用“清除本地诊断数据”删除。';
      });
    } catch (_) {
      if (mounted && widget.userId == userId && _identityIsCurrent) {
        setState(() => _status = '诊断设置暂时无法更新，请稍后再试。');
      }
    } finally {
      if (mounted && widget.userId == userId) {
        setState(() => _busy = false);
      }
    }
  }

  Future<String?> _prepareExport() async {
    if (_busy || !_identityIsCurrent) return null;
    final userId = widget.userId;
    setState(() => _busy = true);
    try {
      final state = await widget.store.load(userId);
      if (!mounted || widget.userId != userId || !_identityIsCurrent) {
        return null;
      }
      setState(() => _state = state);
      final snapshot = state.snapshot;
      if (!state.hasData || snapshot == null) {
        setState(() => _status = '暂无本地诊断数据。');
        return null;
      }
      return widget.store.buildExportJson(snapshot);
    } catch (_) {
      if (mounted && widget.userId == userId && _identityIsCurrent) {
        setState(() => _status = '暂时无法读取匿名摘要，请稍后再试。');
      }
      return null;
    } finally {
      if (mounted && widget.userId == userId) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _viewExport() async {
    final json = await _prepareExport();
    if (!mounted || json == null || !_identityIsCurrent) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final previewHeight = (MediaQuery.sizeOf(dialogContext).height * 0.6)
            .clamp(240.0, 420.0)
            .toDouble();
        return AlertDialog(
          title: const Text('匿名诊断导出预览'),
          content: SizedBox(
            width: 560,
            height: previewHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('这里显示的 JSON 就是复制或导出的全部内容，不包含聊天原文或账号标识。'),
                const SizedBox(height: 12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        dialogContext,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        json,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭预览'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _copyExport() async {
    final json = await _prepareExport();
    if (!mounted || json == null || !_identityIsCurrent) return;
    try {
      await Clipboard.setData(ClipboardData(text: json));
      if (mounted && _identityIsCurrent) {
        setState(() => _status = '匿名诊断摘要已复制。');
      }
    } catch (_) {
      if (mounted && _identityIsCurrent) {
        setState(() => _status = '复制失败，请检查系统权限后再试。');
      }
    }
  }

  Future<void> _exportJson() async {
    final json = await _prepareExport();
    if (!mounted || json == null || !_identityIsCurrent) return;
    if (!await _confirm(message: '导出内容只包含上方显示的匿名聚合数据。', actionLabel: '导出')) {
      return;
    }
    if (!_identityIsCurrent) return;
    try {
      final exported = widget.exportJson != null
          ? await widget.exportJson!(json)
          : await _saveJson(json);
      if (mounted && exported && _identityIsCurrent) {
        setState(() => _status = '匿名诊断 JSON 已导出。');
      }
    } catch (_) {
      if (mounted && _identityIsCurrent) {
        setState(() => _status = '导出失败，请稍后再试。');
      }
    }
  }

  Future<void> _clearDiagnostics() async {
    if (_busy || !_identityIsCurrent) return;
    if (!await _confirm(
      message: '确定清除此设备上当前账号的本地 Beta 诊断数据吗？此操作不会删除聊天记录、姓名记忆或教学知识。',
      actionLabel: '清除',
    )) {
      return;
    }
    if (!_identityIsCurrent) return;

    final userId = widget.userId;
    setState(() => _busy = true);
    try {
      await widget.store.clearSnapshot(userId);
      if (!mounted || widget.userId != userId || !_identityIsCurrent) return;
      final state = await widget.store.load(userId);
      if (!mounted || widget.userId != userId || !_identityIsCurrent) return;
      setState(() {
        _state = state;
        _status = '当前账号的本地诊断数据已清除，其他数据没有受到影响。';
      });
    } catch (_) {
      if (mounted && widget.userId == userId && _identityIsCurrent) {
        setState(() => _status = '暂时无法清除本地诊断数据，请稍后再试。');
      }
    } finally {
      if (mounted && widget.userId == userId) {
        setState(() => _busy = false);
      }
    }
  }

  Future<bool> _saveJson(String json) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '导出匿名诊断 JSON',
      fileName: 'sunland-beta-diagnostics.json',
      type: FileType.custom,
      allowedExtensions: const <String>['json'],
      bytes: Uint8List.fromList(utf8.encode(json)),
    );
    return path != null;
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final snapshot = state?.snapshot;
    final hasData = state?.hasData == true;
    final enabled = state?.enabled == true;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (expanded) {
          _expanded = expanded;
          if (expanded && state?.snapshotLoaded != true && !_busy) {
            _load(includeSnapshot: true);
          }
        },
        title: const Text(
          'Beta 诊断（仅本地）',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: const Text('默认关闭，可随时清除'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '参与本地 Beta 诊断后，Sunland AI 会在此设备上统计匿名的理解结果和性能分桶，用于帮助改进 Beta 体验。诊断不会自动上传，也不包含对话内容、姓名、教学知识或账号标识。',
            ),
          ),
          const SizedBox(height: 10),
          const _DiagnosticPoint('默认关闭，仅保存在当前设备'),
          const _DiagnosticPoint('不会自动上传，不包含聊天内容、姓名、用户教学知识或账号标识'),
          const _DiagnosticPoint('可以随时关闭，也可以单独清除已有诊断数据'),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('参与本地 Beta 诊断'),
            subtitle: Text(enabled ? '已开启 · 仅本地' : '默认关闭'),
            value: enabled,
            onChanged: _loading || _busy || !_identityIsCurrent
                ? null
                : _setEnabled,
          ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: CircularProgressIndicator(),
            )
          else if (!hasData || snapshot == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                '暂无本地诊断数据',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else ...[
            _DiagnosticsCounters(snapshot: snapshot),
            const SizedBox(height: 10),
            _DiagnosticsPerformance(snapshot: snapshot),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: hasData && !_busy ? _viewExport : null,
                child: const Text('查看导出内容'),
              ),
              OutlinedButton(
                onPressed: hasData && !_busy ? _copyExport : null,
                child: const Text('复制匿名摘要'),
              ),
              OutlinedButton(
                onPressed: hasData && !_busy ? _exportJson : null,
                child: const Text('导出匿名 JSON'),
              ),
              TextButton(
                onPressed: hasData && !_busy ? _clearDiagnostics : null,
                style: TextButton.styleFrom(foregroundColor: colorScheme.error),
                child: const Text('清除本地诊断数据'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _status!,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '开启后，仅从后续完成的 Sunland AI 请求开始统计。',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticPoint extends StatelessWidget {
  const _DiagnosticPoint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 5),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

const List<(String, String)> _counterLabels = <(String, String)>[
  ('requestCompleted', 'Sunland 请求总数'),
  ('understood', '正常理解'),
  ('clarification', '澄清'),
  ('noUnderstanding', '未理解'),
  ('missingKnowledge', '缺少知识'),
  ('contextUsed', 'Context 使用'),
  ('legacyFallback', 'Legacy 回退'),
  ('sideEffectBlocked', '副作用阻止'),
  ('safeFallback', '安全降级'),
];

class _DiagnosticsCounters extends StatelessWidget {
  const _DiagnosticsCounters({required this.snapshot});

  final SunlandBetaDiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        const spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (columns - 1) * spacing) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in _counterLabels)
              SizedBox(
                width: itemWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${snapshot.counters[entry.$1] ?? 0}',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          entry.$2,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DiagnosticsPerformance extends StatelessWidget {
  const _DiagnosticsPerformance({required this.snapshot});

  final SunlandBetaDiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('性能分桶'),
      children: [
        _PerformanceRow(
          label: '总处理耗时',
          values: snapshot.durations['total']!,
          labels: _durationLabels,
        ),
        _PerformanceRow(
          label: 'Semantic 耗时',
          values: snapshot.durations['semantic']!,
          labels: _durationLabels,
        ),
        _PerformanceRow(
          label: 'Reasoner 耗时',
          values: snapshot.durations['reasoner']!,
          labels: _durationLabels,
        ),
        _PerformanceRow(
          label: 'Knowledge 数量',
          values: snapshot.knowledgeSizeBuckets,
          labels: _knowledgeLabels,
        ),
        _PerformanceRow(
          label: 'Reasoner 路径',
          values: snapshot.reasonerPathBuckets,
          labels: _pathLabels,
        ),
      ],
    );
  }
}

const List<(String, String)> _durationLabels = <(String, String)>[
  ('under-1ms', '<1ms'),
  ('1-5ms', '1–5ms'),
  ('5-16ms', '5–16ms'),
  ('16-50ms', '16–50ms'),
  ('over-50ms', '>50ms'),
  ('unavailable', '不可用'),
];

const List<(String, String)> _knowledgeLabels = <(String, String)>[
  ('0', '0'),
  ('1-99', '1–99'),
  ('100-999', '100–999'),
  ('1000-4999', '1000–4999'),
  ('5000-plus', '5000+'),
  ('unavailable', '不可用'),
];

const List<(String, String)> _pathLabels = <(String, String)>[
  ('direct', '直接'),
  ('2-5', '2–5'),
  ('6-20', '6–20'),
  ('21-50', '21–50'),
  ('51-plus', '51+'),
  ('none', '无'),
  ('unavailable', '不可用'),
];

class _PerformanceRow extends StatelessWidget {
  const _PerformanceRow({
    required this.label,
    required this.values,
    required this.labels,
  });

  final String label;
  final Map<String, int> values;
  final List<(String, String)> labels;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final entry in labels)
                  Text('${entry.$2} ${values[entry.$1] ?? 0}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
