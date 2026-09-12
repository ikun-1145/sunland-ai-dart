import 'dart:convert';
import 'package:http/http.dart' as http;
import '../sunland_ai_core.dart';

String chatUsageDate(DateTime now) => now
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);

class ChatUsage {
  const ChatUsage({
    required this.date,
    required this.remaining,
    required this.isPro,
  });
  final String date;
  final int remaining;
  final bool isPro;
}

/// Reads the gateway's daily counter. Device preferences are not quota truth.
class ChatUsageService {
  ChatUsageService({
    required this.tokenProvider,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;
  final Future<String?> Function() tokenProvider;
  final http.Client _client;
  final DateTime Function() _now;

  Future<ChatUsage> read(String userId) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) throw const AuthExpiredException();
    final response = await _client
        .post(
          Uri.parse('$sunlandApiBase/v1/usage'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Cache-Control': 'no-cache',
          },
          body: '{}',
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode == 401) throw const AuthExpiredException();
    if (response.statusCode != 200) throw const ApiException('额度暂时无法读取');
    final data = jsonDecode(response.body);
    if (data is! Map ||
        data['userId'] != userId ||
        data['date'] != chatUsageDate(_now()) ||
        data['isPro'] is! bool ||
        data['remain'] is! int ||
        (data['remain'] as int) < -1 ||
        (data['remain'] as int) > freeDailyLimit ||
        data['isPro'] != (data['remain'] == -1)) {
      throw const ApiException('额度响应无效');
    }
    return ChatUsage(
      date: data['date'] as String,
      remaining: data['remain'] as int,
      isPro: data['isPro'] as bool,
    );
  }

  void close() => _client.close();
}
