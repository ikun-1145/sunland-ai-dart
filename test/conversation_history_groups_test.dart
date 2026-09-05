import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/widgets/conversation_history_groups.dart';

void main() {
  test(
    'groups dates by local calendar boundary with stable newest-first order',
    () {
      final now = DateTime(2026, 9, 5, 12);
      final groups = groupConversationsByUpdatedAt([
        _conversation('older', DateTime(2026, 8, 28, 12)),
        _conversation('today-a', DateTime(2026, 9, 5, 8)),
        _conversation('previous', DateTime(2026, 8, 30, 12)),
        _conversation('yesterday', DateTime(2026, 9, 4, 23, 59)),
        _conversation('today-b', DateTime(2026, 9, 5, 10)),
        <String, dynamic>{'id': 'invalid', 'updatedAt': 'not-a-time'},
      ], now: now);

      expect(groups.map((group) => group.label), ['今天', '昨天', '过去 7 天', '更早']);
      expect(groups[0].conversations.map((item) => item['id']), [
        'today-b',
        'today-a',
      ]);
      expect(groups[1].conversations.single['id'], 'yesterday');
      expect(groups[2].conversations.single['id'], 'previous');
      expect(groups[3].conversations.map((item) => item['id']), [
        'older',
        'invalid',
      ]);
    },
  );
}

Map<String, dynamic> _conversation(String id, DateTime updatedAt) => {
  'id': id,
  'updatedAt': updatedAt.millisecondsSinceEpoch,
};
