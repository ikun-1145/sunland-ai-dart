import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sunland_ai_app/announcement_service.dart';

class _Client extends http.BaseClient {
  _Client(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => handler(request);
}

http.StreamedResponse _response(Object body, {int status = 200}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

void main() {
  test('只解析服务端已过滤的公告信封，不需要聊天数据或登录 Token', () async {
    late http.BaseRequest request;
    final service = AnnouncementService(
      client: _Client((value) async {
        request = value;
        return _response({
          'items': [
            {
              'id': 'notice-1',
              'title': '维护通知',
              'content': '服务将在夜间维护。',
              'publishedAt': '2026-09-04T00:00:00Z',
            },
          ],
        });
      }),
    );

    final announcements = await service.load();

    expect(request.url.toString(), 'https://api.sunland.dev/v1/announcements');
    expect(request.headers.containsKey('authorization'), isFalse);
    expect(announcements.single.content, '服务将在夜间维护。');
  });

  test('无效响应不会被当作空公告成功展示', () async {
    final service = AnnouncementService(
      client: _Client((_) async => _response({'items': 'not-a-list'})),
    );

    expect(service.load(), throwsFormatException);
  });
}
