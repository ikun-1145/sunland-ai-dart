import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/furry_event_api.dart';

void main() {
  test('maps the direct furry_events table shape', () {
    final event = FurryEventEnriched.fromMap({
      'name': '上海兽聚',
      'start_at': '2026-09-01T10:00:00+08:00',
      'end_at': '2026-09-02T18:00:00+08:00',
      'city': '上海',
      'venue': '世博展览馆',
      'cover_url': 'https://example.com/cover.jpg',
      'source_url': 'https://example.com/event',
      'ctrip_url': 'https://example.com/ctrip',
      'meituan_url': 'https://example.com/meituan',
    });

    expect(event.venue, '世博展览馆');
    expect(event.coverUrl, 'https://example.com/cover.jpg');
    expect(event.sourceUrl, 'https://example.com/event');
    expect(event.ctripUrl, 'https://example.com/ctrip');
    expect(event.meituanUrl, 'https://example.com/meituan');
  });

  test('maps the Edge Function location fields without losing the address', () {
    final event = FurryEventEnriched.fromMap({
      'name': '江苏兽聚',
      'startAt': '2026-10-01T10:00:00+08:00',
      'endAt': '2026-10-02T18:00:00+08:00',
      'province': '江苏',
      'city': '南京',
      'address': '江苏·南京',
      'venue': null,
      'coverUrl': 'https://example.com/cover.png',
      'sourceUrl': 'https://example.com/event',
      'hotels': {
        'ctripUrl': 'https://example.com/ctrip',
        'meituanUrl': 'https://example.com/meituan',
      },
    });

    expect(event.startAt, '2026-10-01T10:00:00+08:00');
    expect(event.endAt, '2026-10-02T18:00:00+08:00');
    expect(event.city, '南京');
    expect(event.venue, '江苏·南京');
    expect(event.ctripUrl, 'https://example.com/ctrip');
    expect(event.meituanUrl, 'https://example.com/meituan');
  });
}
