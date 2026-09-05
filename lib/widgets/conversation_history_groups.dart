import 'package:flutter/material.dart';

class ConversationHistoryGroup {
  const ConversationHistoryGroup({
    required this.label,
    required this.conversations,
  });

  final String label;
  final List<Map<String, dynamic>> conversations;
}

List<ConversationHistoryGroup> groupConversationsByUpdatedAt(
  List<Map<String, dynamic>> conversations, {
  required DateTime now,
}) {
  final indexed = conversations.asMap().entries.toList()
    ..sort((a, b) {
      final aTime = int.tryParse(a.value['updatedAt']?.toString() ?? '') ?? 0;
      final bTime = int.tryParse(b.value['updatedAt']?.toString() ?? '') ?? 0;
      final byTime = bTime.compareTo(aTime);
      return byTime == 0 ? a.key.compareTo(b.key) : byTime;
    });
  final groups = <String, List<Map<String, dynamic>>>{
    '今天': [],
    '昨天': [],
    '过去 7 天': [],
    '更早': [],
  };
  final today = DateUtils.dateOnly(now);
  for (final entry in indexed) {
    final updatedAt =
        int.tryParse(entry.value['updatedAt']?.toString() ?? '') ?? 0;
    final date = updatedAt > 0
        ? DateUtils.dateOnly(DateTime.fromMillisecondsSinceEpoch(updatedAt))
        : null;
    final daysAgo = date == null ? -1 : today.difference(date).inDays;
    final label = daysAgo == 0
        ? '今天'
        : daysAgo == 1
        ? '昨天'
        : daysAgo >= 2 && daysAgo <= 7
        ? '过去 7 天'
        : '更早';
    groups[label]!.add(entry.value);
  }
  return groups.entries
      .where((entry) => entry.value.isNotEmpty)
      .map(
        (entry) => ConversationHistoryGroup(
          label: entry.key,
          conversations: entry.value,
        ),
      )
      .toList();
}
