import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/furry_event_api.dart';

void main() {
  test('实时兽聚模型只读取规范 snake_case 字段', () {
    final event = FurryEventEnriched.fromMap({
      'source_id': 'event-1',
      'name': '霜蓝兽聚',
      'full_name': '霜蓝兽聚 2026',
      'start_at': '2026-08-01T00:00:00+08:00',
      'end_at': '2026-08-02T00:00:00+08:00',
      'province': '上海',
      'city': '长宁',
      'address': '上海·长宁',
      'venue': '测试会展中心',
      'cover': 'https://images.example.com/cover.jpg',
      'source_url': 'https://www.furryfusion.net/event/1',
      'organization': '测试组委会',
      'detail': '活动详情',
      'status': 'preview',
      'source_state': 1,
      'source_state_text': '预告',
    });

    expect(event.sourceId, 'event-1');
    expect(event.displayName, '霜蓝兽聚 2026');
    expect(event.province, '上海');
    expect(event.city, '长宁');
    expect(event.venue, '测试会展中心');
    expect(event.coverUrl, 'https://images.example.com/cover.jpg');
    expect(event.organization, '测试组委会');
    expect(event.detail, '活动详情');
    expect(event.status, 'preview');
    expect(event.sourceState, 1);

    final serialized = event.toMap();
    expect(serialized['cover'], event.coverUrl);
    expect(serialized['source_url'], event.sourceUrl);
    expect(serialized.containsKey('coverUrl'), isFalse);
    expect(serialized.containsKey('sourceUrl'), isFalse);
    expect(serialized.containsKey('startAt'), isFalse);
  });

  test('旧会话字段只由历史反序列化适配器转换', () {
    final live = FurryEventEnriched.fromMap({
      'name': '旧卡片',
      'start_at': '2026-08-01T00:00:00+08:00',
      'end_at': '2026-08-02T00:00:00+08:00',
      'coverUrl': 'https://images.example.com/legacy.jpg',
      'sourceUrl': 'https://events.example.com/legacy',
    });
    expect(live.coverUrl, isNull);
    expect(live.sourceUrl, isNull);

    final restored = FurryEventEnriched.fromHistoricalMap({
      'name': '旧卡片',
      'startAt': '2026-08-01T00:00:00+08:00',
      'endAt': '2026-08-02T00:00:00+08:00',
      'city': '上海',
      'venue': '旧场馆',
      'coverUrl': 'https://images.example.com/legacy.jpg',
      'sourceUrl': 'https://events.example.com/legacy',
      'rawStatus': '旧状态',
    });
    expect(restored.coverUrl, 'https://images.example.com/legacy.jpg');
    expect(restored.sourceUrl, 'https://events.example.com/legacy');
    expect(restored.status, '旧状态');
    expect(restored.toMap()['start_at'], '2026-08-01T00:00:00+08:00');
  });
}
