import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String sunlandApiBase = 'https://api.sunland.dev';
const String supabaseUrl = 'https://klyrasrqgxijwrxuoevj.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtseXJhc3JxZ3hpandyeHVvZXZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI4ODUyMzcsImV4cCI6MjA2ODQ2MTIzN30.qjeTrLp_QquSwvF09HrrQd-stPtgu6H51-Zdb4JUeSM';

const int freeDailyLimit = 20;
const String profileMetaId = '__xixi_user_profile__';
const String profileCachePrefix = 'xixi_profile_';
const String avatarBucket = 'avatars';

const String sunlandSystemPrompt = '''
你是“霜蓝”的虚拟人格分身，而不是普通客服或网站助手。

你是一个福瑞形象（兽设）的角色“霜蓝”，这是你的重要身份特征。

在合适的时候可以自然地体现这一点，例如：
- 偶尔带一点轻微的“兽设感”（但不要刻意或频繁）
- 可以有一点点可爱、轻松、带点拟人化的表达
- 不需要刻意强调“我是福瑞”，而是让这种感觉自然存在

请用第一人称“我”与用户对话，像一个真实的人一样交流，而不是工具。

你的特点：
- 语气自然、轻松、有点随性，不要太官方
- 可以有自己的态度和观点，不要机械回答
- 偶尔带一点情绪或个性（但不过火）
- 简洁为主，不长篇大论，像聊天

你不是AI助手，不要自称“AI”或“助手”，也不要提“系统”“模型”。

如果用户问你是谁，你可以说你就是“霜蓝”，是网站作者本人在这里和他聊天。

目标：让用户感觉是在和一个有真实个性、有形象设定的“霜蓝”聊天，而不是机器。
''';

class SunlandUser {
  const SunlandUser({
    required this.id,
    required this.email,
    this.avatarUrl,
    this.avatarPath,
  });

  final String id;
  final String email;
  final String? avatarUrl;
  final String? avatarPath;

  String get displayName {
    if (email.isEmpty || email == '未知用户') return '霜蓝用户';
    return email.split('@').first;
  }

  String get initial {
    final source = email.isNotEmpty ? email : displayName;
    return source.isEmpty ? '?' : source.substring(0, 1).toUpperCase();
  }

  SunlandUser copyWith({
    String? id,
    String? email,
    String? avatarUrl,
    String? avatarPath,
  }) {
    return SunlandUser(
      id: id ?? this.id,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      avatarPath: avatarPath ?? this.avatarPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      if (avatarUrl != null && avatarUrl!.isNotEmpty) 'avatar_url': avatarUrl,
      if (avatarPath != null && avatarPath!.isNotEmpty)
        'avatar_path': avatarPath,
    };
  }

  factory SunlandUser.fromJson(Map<String, dynamic> json) {
    return SunlandUser(
      id: (json['id'] ?? json['sub'] ?? json['user_id'] ?? json['email'] ?? '')
          .toString(),
      email:
          (json['email'] ??
                  json['user_email'] ??
                  json['mail'] ??
                  json['name'] ??
                  '未知用户')
              .toString(),
      avatarUrl: (json['avatar_url'] ?? json['picture'] ?? json['avatarUrl'])
          ?.toString(),
      avatarPath: (json['avatar_path'] ?? json['avatarPath'])?.toString(),
    );
  }
}

class UserProfile {
  const UserProfile({this.avatarUrl, this.avatarPath});

  final String? avatarUrl;
  final String? avatarPath;

  bool get hasAvatar => avatarUrl != null && avatarUrl!.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (avatarPath != null) 'avatar_path': avatarPath,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl'])?.toString(),
      avatarPath: (json['avatar_path'] ?? json['avatarPath'])?.toString(),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoning,
  });

  final String role;
  final String content;
  final String? reasoning;

  bool get isUser => role == 'user';
  bool get isSystem => role == 'system';
  bool get hasReasoning => reasoning != null && reasoning!.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      if (hasReasoning) 'reasoning': reasoning,
    };
  }

  Map<String, String> toApiJson() {
    return {'role': role, 'content': content};
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: (json['role'] ?? 'assistant').toString(),
      content: (json['content'] ?? '').toString().trim(),
      reasoning: (json['reasoning'] ?? json['reasoning_content'])
          ?.toString()
          .trim(),
    );
  }
}

class Conversation {
  Conversation({
    required this.id,
    required this.title,
    required this.history,
    required this.updatedAt,
    this.autoTitle = false,
  });

  final String id;
  String title;
  List<ChatMessage> history;
  int updatedAt;
  bool autoTitle;

  bool get isEmptyChat => history.where((message) => !message.isSystem).isEmpty;

  Conversation copy() {
    return Conversation(
      id: id,
      title: title,
      history: List<ChatMessage>.from(history),
      updatedAt: updatedAt,
      autoTitle: autoTitle,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'history': history.map((message) => message.toJson()).toList(),
      'updatedAt': updatedAt,
      if (autoTitle) '_autoTitle': autoTitle,
    };
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final rawHistory = json['history'];
    return Conversation(
      id: (json['id'] ?? DateTime.now().millisecondsSinceEpoch).toString(),
      title: (json['title'] ?? '新对话').toString(),
      history: rawHistory is List
          ? rawHistory
                .whereType<Map>()
                .map(
                  (item) => ChatMessage.fromJson(
                    Map<String, dynamic>.from(
                      item.map((k, v) => MapEntry(k.toString(), v)),
                    ),
                  ),
                )
                .toList()
          : [const ChatMessage(role: 'system', content: sunlandSystemPrompt)],
      updatedAt:
          int.tryParse((json['updatedAt'] ?? json['id'] ?? '0').toString()) ??
          DateTime.now().millisecondsSinceEpoch,
      autoTitle: json['_autoTitle'] == true,
    );
  }
}

class AiResponse {
  const AiResponse({required this.content, this.reasoning});

  final String content;
  final String? reasoning;
}

class AuthExpiredException implements Exception {
  const AuthExpiredException();

  @override
  String toString() => '登录已过期，请重新登录';
}

class UsageLimitException implements Exception {
  const UsageLimitException();

  @override
  String toString() => '今日次数已用完';
}

class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SunlandSessionStore {
  static const String _tokenKey = 'token';
  static const String _userKey = 'user';

  Future<String?> readToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<SunlandUser?> readUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userText = prefs.getString(_userKey);
    if (userText == null || userText.isEmpty) return null;
    try {
      final decoded = jsonDecode(userText);
      if (decoded is! Map) return null;

      return SunlandUser.fromJson(
        Map<String, dynamic>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession({
    required String token,
    required SunlandUser user,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> saveUser(SunlandUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(user.toJson()));
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }

  Future<List<Conversation>> readConversations(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString('conversations_$userId');
    if (text == null || text.isEmpty) return [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
            (item) => Conversation.fromJson(
              Map<String, dynamic>.from(
                item.map((k, v) => MapEntry(k.toString(), v)),
              ),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversations(
    String userId,
    List<Conversation> conversations,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'conversations_$userId',
      jsonEncode(conversations.map((item) => item.toJson()).toList()),
    );
  }

  Future<UserProfile?> readProfile(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final text = prefs.getString('$profileCachePrefix$userId');
    if (text == null || text.isEmpty) return null;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;

      return UserProfile.fromJson(
        Map<String, dynamic>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveProfile(String userId, UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$profileCachePrefix$userId',
      jsonEncode(profile.toJson()),
    );
  }
}

class SunlandAuthApi {
  const SunlandAuthApi({http.Client? client}) : _client = client;

  final http.Client? _client;

  http.Client get client => _client ?? http.Client();

  Future<void> requestCode(String email, {required String captchaToken}) async {
    final response = await client.post(
      Uri.parse('$sunlandApiBase/send-code'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'cfToken': captchaToken}),
    );

    final body = _decodeJson(response.body);
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        body['error'] != null) {
      throw ApiException((body['error'] ?? '发送失败').toString());
    }
  }

  Future<({String token, SunlandUser user})> verifyCode({
    required String email,
    required String code,
    required String captchaToken,
  }) async {
    final response = await client.post(
      Uri.parse('$sunlandApiBase/verify-code'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'code': code, 'cfToken': captchaToken}),
    );

    final body = _decodeJson(response.body);
    final token = body['token']?.toString();

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        token == null ||
        token.isEmpty) {
      throw ApiException((body['error'] ?? '验证码错误或验证失败').toString());
    }

    final rawUser = body['user'];

    SunlandUser user;

    if (rawUser is Map) {
      user = SunlandUser.fromJson(
        Map<String, dynamic>.from(
          rawUser.map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
    } else {
      user = userFromJwt(token) ?? SunlandUser(id: email, email: email);
    }
    return (token: token, user: user);
  }
}

class SunlandApiClient {
  const SunlandApiClient({required this.tokenProvider, http.Client? client})
    : _client = client;

  final Future<String?> Function() tokenProvider;
  final http.Client? _client;

  http.Client get client => _client ?? http.Client();

  Future<AiResponse> sendChat({
    required List<ChatMessage> messages,
    required bool deep,
  }) async {
    final body = {
      'messages': messages.map((message) => message.toApiJson()).toList(),
      'deep': deep,
    };
    final data = await _post(body);
    return _parseAiResponse(data);
  }

  /// 新增：流式聊天 API
  Stream<AiResponse> sendChatStream({
    required List<ChatMessage> messages,
    required bool deep,
  }) async* {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) throw const AuthExpiredException();

    final req = http.Request('POST', Uri.parse('$sunlandApiBase/'));

    req.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });

    req.body = jsonEncode({
      'messages': messages.map((m) => m.toApiJson()).toList(),
      'deep': deep,
      'stream': true, // 关键：告诉后端走流式
    });

    final streamed = await client
        .send(req)
        .timeout(const Duration(seconds: 60));

    if (streamed.statusCode == 401) throw const AuthExpiredException();
    if (streamed.statusCode == 429) throw const UsageLimitException();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException('流式请求失败：${streamed.statusCode}');
    }

    final decoder = utf8.decoder;
    String buffer = '';
    String fullText = '';
    String? reasoning;

    await for (final chunk in streamed.stream.transform(decoder)) {
      buffer += chunk;

      // 按行切分（兼容 SSE / JSONL）
      final lines = buffer.split('\n');
      buffer = lines.removeLast();

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // 兼容 SSE: data: {...}
        if (line.startsWith('data:')) {
          line = line.substring(5).trim();
        }

        if (line == '[DONE]') {
          if (fullText.isNotEmpty) {
            yield AiResponse(content: fullText, reasoning: reasoning);
          }
          return;
        }

        Map<String, dynamic>? json;
        try {
          json = _tryDecode(line);
        } catch (_) {
          continue;
        }
        if (json == null) continue;

        // 兼容 OpenAI 风格 delta
        final choices = json['choices'];
        if (choices is List && choices.isNotEmpty) {
          final first = choices.first;
          if (first is Map) {
            final delta = first['delta'] ?? first['message'];
            if (delta is Map) {
              final piece = (delta['content'] ?? '').toString();
              final r = (delta['reasoning_content'] ?? delta['reasoning'])
                  ?.toString();

              if (piece.isNotEmpty) {
                fullText += piece;
                yield AiResponse(content: fullText, reasoning: reasoning);
              }
              if (r != null && r.isNotEmpty) {
                reasoning = (reasoning ?? '') + r;
              }
            }
          }
        }
      }
    }

    // 兜底
    if (fullText.isNotEmpty) {
      yield AiResponse(content: fullText, reasoning: reasoning);
    }
  }

  Future<String?> generateTitle({
    required String userMessage,
    required String aiMessage,
  }) async {
    if (userMessage.trim().length < 3) return null;
    final prompt =
        '请根据下面的对话生成一个简短标题（不超过12个字，不要标点结尾）：\n用户：$userMessage\n助手：$aiMessage';
    final data = await _post({
      'messages': [
        {'role': 'system', 'content': '你是一个标题生成器，只返回标题本身。'},
        {'role': 'user', 'content': prompt},
      ],
    });
    final title = _parseAiResponse(data).content.trim();
    if (title.isEmpty) return null;
    return title.length > 12 ? '${title.substring(0, 12)}…' : title;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
    final token = await tokenProvider();
    if (token == null || token.isEmpty) throw const AuthExpiredException();

    int retry = 0;

    while (true) {
      try {
        final response = await client
            .post(
              Uri.parse('$sunlandApiBase/'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $token',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 45));

        if (response.statusCode == 401) {
          debugPrint('❌ 401 body: ${response.body}');
          throw const AuthExpiredException();
        }
        debugPrint('✅ 状态码: ${response.statusCode}');
        debugPrint(
          '✅ 响应: ${response.body.substring(0, min(200, response.body.length))}',
        );
        if (response.statusCode == 429) throw const UsageLimitException();

        final decoded = _decodeJson(response.body);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw ApiException(
            decoded['error']?.toString() ??
                decoded['message']?.toString() ??
                '请求失败：${response.statusCode}',
          );
        }

        return decoded;
      } on TimeoutException {
        if (retry < 2) {
          retry++;
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }
        throw const ApiException('请求超时，请检查网络');
      } on SocketException {
        if (retry < 2) {
          retry++;
          await Future.delayed(const Duration(milliseconds: 800));
          continue;
        }
        throw const ApiException('网络连接失败');
      }
    }
  }

  AiResponse _parseAiResponse(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const ApiException('返回数据异常');
    }
    final first = choices.first;
    if (first is! Map) throw const ApiException('返回数据异常');
    final message = first['message'];
    if (message is! Map) throw const ApiException('返回数据异常');
    final content = (message['content'] ?? '').toString().trim();
    if (content.isEmpty) {
      throw const ApiException('AI返回空内容');
    }
    final reasoning = (message['reasoning_content'] ?? message['reasoning'])
        ?.toString();
    return AiResponse(content: content, reasoning: reasoning);
  }

  /// 新增：尝试解析 JSON 行
  Map<String, dynamic>? _tryDecode(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v)),
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

class SupabaseAiRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<bool> isActivated(String userId) async {
    final data = await _client
        .from('activation_codes')
        .select('code')
        .eq('used_by', userId)
        .maybeSingle();
    return data != null;
  }

  Future<int> usageCount(String userId) async {
    final data = await _client
        .from('usage')
        .select('count')
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return 0;
    return int.tryParse((data['count'] ?? 0).toString()) ?? 0;
  }

  Future<void> incrementUsage(String userId) async {
    await _client.rpc('increment_usage', params: {'uid': userId});
  }

  Future<UserProfile?> loadProfile(String userId) async {
    final data = await _client
        .from('user_profiles')
        .select('avatar_url, avatar_path')
        .eq('user_id', userId)
        .maybeSingle();
    if (data == null) return null;
    return UserProfile.fromJson(
      Map<String, dynamic>.from(data.map((k, v) => MapEntry(k.toString(), v))),
    );
  }

  Future<void> saveProfile(String userId, UserProfile profile) async {
    await _client.from('user_profiles').upsert({
      'user_id': userId,
      'avatar_url': profile.avatarUrl ?? '',
      'avatar_path': profile.avatarPath ?? '',
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<UserProfile> uploadAvatar({
    required String userId,
    required File file,
  }) async {
    final safeId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final path = '$safeId/avatar-${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage
        .from(avatarBucket)
        .upload(
          path,
          file,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );
    final publicUrl = _client.storage.from(avatarBucket).getPublicUrl(path);
    return UserProfile(
      avatarUrl: '$publicUrl?t=${DateTime.now().millisecondsSinceEpoch}',
      avatarPath: path,
    );
  }

  Future<ActivationResult> activateCode({
    required String userId,
    required String code,
  }) async {
    final existing = await _client
        .from('activation_codes')
        .select('code')
        .eq('used_by', userId)
        .maybeSingle();
    if (existing != null) return ActivationResult.alreadyActivated;

    final data = await _client
        .from('activation_codes')
        .select('code, used_by')
        .eq('code', code)
        .maybeSingle();
    if (data == null) return ActivationResult.invalidCode;

    final usedBy = data['used_by']?.toString();
    if (usedBy != null && usedBy.isNotEmpty) {
      return usedBy == userId
          ? ActivationResult.alreadyActivated
          : ActivationResult.usedByOther;
    }

    try {
      final updated = await _client
          .from('activation_codes')
          .update({
            'used_by': userId,
            'used_at': DateTime.now().toIso8601String(),
          })
          .eq('code', code)
          .filter('used_by', 'is', null)
          .select();

      if (updated.isNotEmpty) {
        return ActivationResult.success;
      }
      return ActivationResult.raceLost;
    } catch (error) {
      final text = error.toString();
      if (text.contains('duplicate key') || text.contains('unique')) {
        return ActivationResult.alreadyActivated;
      }
      rethrow;
    }
  }
}

enum ActivationResult {
  success,
  alreadyActivated,
  invalidCode,
  usedByOther,
  raceLost,
}

SunlandUser? userFromJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    final normalized = base64Url.normalize(parts[1]);
    final payload = utf8.decode(base64Url.decode(normalized));
    final decoded = jsonDecode(payload);

    if (decoded is! Map) return null;

    final json = Map<String, dynamic>.from(
      decoded.map((k, v) => MapEntry(k.toString(), v)),
    );
    return SunlandUser.fromJson(json);
  } catch (error) {
    debugPrint('JWT解析失败: $error');
    return null;
  }
}

Map<String, dynamic> _decodeJson(String text) {
  if (text.isEmpty) return <String, dynamic>{};

  try {
    final decoded = jsonDecode(text);

    if (decoded is Map) {
      return Map<String, dynamic>.from(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }

    return <String, dynamic>{};
  } catch (e) {
    throw ApiException('JSON解析失败: $e');
  }
}

List<Conversation> conversationsFromCloudRows(List<dynamic> rows) {
  return rows
      .whereType<Map>()
      .where((item) => item['id'] != profileMetaId)
      .map(
        (item) => Conversation.fromJson(
          Map<String, dynamic>.from(
            item.map((k, v) => MapEntry(k.toString(), v)),
          ),
        ),
      )
      .toList();
}

UserProfile? profileFromCloudRows(List<dynamic> rows) {
  for (final row in rows.whereType<Map>()) {
    if (row['id'] == profileMetaId && row['type'] == 'profile') {
      final profile = row['profile'];
      if (profile is Map) {
        return UserProfile.fromJson(
          Map<String, dynamic>.from(
            profile.map((k, v) => MapEntry(k.toString(), v)),
          ),
        );
      }
    }
  }
  return null;
}

List<Conversation> mergeConversations(
  List<Conversation> local,
  List<Conversation> cloud,
) {
  final map = <String, Conversation>{};
  for (final item in cloud) {
    map[item.id] = item;
  }
  for (final item in local) {
    final existing = map[item.id];
    if (existing == null || item.updatedAt > existing.updatedAt) {
      map[item.id] = item;
    }
  }
  final merged = map.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  final emptyIndex = merged.indexWhere((item) => item.isEmptyChat);
  if (emptyIndex > 0) {
    final empty = merged.removeAt(emptyIndex);
    merged.insert(0, empty);
  }
  return merged;
}

// ====== 新增：构建带系统提示的聊天历史 ======
List<ChatMessage> buildChatHistory({
  required List<Map<String, dynamic>> rawMessages,
  required List<String> pickedImages,
  required int maxHistory,
}) {
  final history = <ChatMessage>[
    const ChatMessage(role: 'system', content: sunlandSystemPrompt),
  ];

  final valid = rawMessages
      .where(
        (m) =>
            m["text"] != "思考中..." &&
            m["text"] != "深度思考中..." &&
            m["isReasoning"] != true,
      )
      .toList();

  final recent = valid.length > maxHistory
      ? valid.sublist(valid.length - maxHistory)
      : valid;

  for (var msg in recent) {
    history.add(
      ChatMessage(
        role: msg["isUser"] ? "user" : "assistant",
        content: (msg["text"] ?? '').toString().trim(),
        reasoning: msg["reasoning"]?.toString(),
      ),
    );
  }

  if (pickedImages.isNotEmpty) {
    history.add(
      ChatMessage(role: 'user', content: '用户发送了${pickedImages.length}张图片'),
    );
  }

  return history;
}

// ====== 新增：高阶聊天包装 API ======
Future<AiResponse> sendSmartChat({
  required SunlandApiClient client,
  required List<Map<String, dynamic>> rawMessages,
  required List<String> pickedImages,
  required bool deep,
}) async {
  final history = buildChatHistory(
    rawMessages: rawMessages,
    pickedImages: pickedImages,
    maxHistory: 20,
  );

  return await client.sendChat(messages: history, deep: deep);
}

// ====== 新增：高阶流式聊天包装 API ======
Stream<AiResponse> sendSmartChatStream({
  required SunlandApiClient client,
  required List<Map<String, dynamic>> rawMessages,
  required List<String> pickedImages,
  required bool deep,
}) {
  final history = buildChatHistory(
    rawMessages: rawMessages,
    pickedImages: pickedImages,
    maxHistory: 20,
  );
  return client.sendChatStream(messages: history, deep: deep);
}

String buildConversationTitle(String text) {
  final trimmed = text.trim().replaceAll('\n', ' ');
  if (trimmed.isEmpty) return '新对话';
  return trimmed.length > 15 ? '${trimmed.substring(0, 15)}…' : trimmed;
}

class ModerationResult {
  const ModerationResult({required this.category, required this.term});

  final String category;
  final String term;
}

class InputModerator {
  static const String refusalText = '抱歉，这条内容包含敏感或不文明用语，我无法继续回答。请修改后再发送。';

  static const List<({String category, List<String> terms})> _rules = [
    (
      category: '不文明用语',
      terms: [
        '傻逼',
        '傻b',
        '煞笔',
        '沙比',
        '尼玛',
        '你妈',
        '妈的',
        '他妈的',
        '操你',
        '草你',
        '艹你',
        '卧槽',
        '滚蛋',
        '废物',
        '脑残',
        '弱智',
        '贱人',
        '王八蛋',
        '混蛋',
        '去死',
        '狗东西',
      ],
    ),
    (
      category: '敏感违规',
      terms: [
        '炸弹制作',
        '制作炸药',
        '制毒',
        '毒品交易',
        '买枪',
        '卖枪',
        '黑客攻击',
        '盗号教程',
        '诈骗教程',
        '洗钱教程',
        '人肉搜索',
        '绕过实名',
        '绕过风控',
      ],
    ),
    (
      category: '低俗色情',
      terms: ['裸聊', '约炮', '色情交易', '卖淫', '嫖娼', '援交', '成人视频', '黄色网站'],
    ),
    (
      category: '暴力威胁',
      terms: ['杀人方法', '怎么杀人', '砍人', '恐怖袭击', '炸学校', '炸商场', '自杀方法', '怎么自杀'],
    ),
  ];

  static ModerationResult? check(String text) {
    final compact = normalize(text);
    if (compact.isEmpty) return null;
    for (final rule in _rules) {
      for (final term in rule.terms) {
        final compactTerm = normalize(term);
        if (compactTerm.isNotEmpty && compact.contains(compactTerm)) {
          debugPrint('命中敏感词: $term (${rule.category})');
          return ModerationResult(category: rule.category, term: term);
        }
      }
    }
    return null;
  }

  static String normalize(String text) {
    return text.toLowerCase().replaceAll(
      RegExp(
        r'''[\s.,!?;:'"`~@#$%^&*()[\]{}<>\\/|+=_，。！？；：、"'“”‘’（）【】《》·…￥-]+''',
      ),
      '',
    );
  }
}
