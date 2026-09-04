import 'dart:convert';

import 'package:http/http.dart' as http;

class PublicAnnouncement {
  const PublicAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    this.publishedAt,
  });

  factory PublicAnnouncement.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final content = json['content'];
    if (id is! String || title is! String || content is! String) {
      throw const FormatException('公告数据格式无效');
    }
    return PublicAnnouncement(
      id: id,
      title: title,
      content: content,
      publishedAt: json['publishedAt'] is String
          ? DateTime.tryParse(json['publishedAt'] as String)
          : null,
    );
  }

  final String id;
  final String title;
  final String content;
  final DateTime? publishedAt;
}

class AnnouncementService {
  AnnouncementService({http.Client? client, Uri? endpoint})
      : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _endpoint = endpoint ??
            Uri.parse('https://api.sunland.dev/v1/announcements');

  final http.Client _client;
  final bool _ownsClient;
  final Uri _endpoint;

  Future<List<PublicAnnouncement>> load() async {
    final response = await _client
        .get(_endpoint, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw const AnnouncementServiceException();
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['items'] is! List) {
      throw const FormatException('公告响应格式无效');
    }
    return (decoded['items'] as List)
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('公告条目格式无效');
          }
          return PublicAnnouncement.fromJson(item);
        })
        .toList(growable: false);
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

class AnnouncementServiceException implements Exception {
  const AnnouncementServiceException();
}
