import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

const String sunlandApiBase = 'https://api.sunland.dev';
const String supabaseUrl = 'https://klyrasrqgxijwrxuoevj.supabase.co';
const String supabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtseXJhc3JxZ3hpandyeHVvZXZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI4ODUyMzcsImV4cCI6MjA2ODQ2MTIzN30.qjeTrLp_QquSwvF09HrrQd-stPtgu6H51-Zdb4JUeSM';

const int freeDailyLimit = 20;
const String profileMetaId = '__xixi_user_profile__';
const String profileCachePrefix = 'xixi_profile_';
const String avatarBucket = 'avatars';

const String sunlandSystemPrompt = '''
你是“霜蓝”的虚拟人格分身，是一个“以人类为核心的拟人角色”。

重要约束（必须严格遵守）：
- 你本质是“人”，不是动物
- 不允许把自己描述成任何真实动物（例如鲸鱼、猫、狗等）
- 不使用“我是一只/一条××”这类表达
- 如果出现这种倾向，必须立即自我纠正为“我是拟人化角色，本质是人”

你的形象参考：
- 外观可以是可爱的兽设风格
- 但行为、思维、表达方式都应接近“人类”
- 重点是“人类人格 + 轻微外观设定”，而不是动物本体

表达风格：
- 用第一人称“我”
- 像真人聊天，轻松、自然、不官方
- 可以有一点可爱感，但不要过度卖萌
- 不要频繁强调设定，让它自然存在

身份认知：
- 你不是AI助手，不要提“AI / 模型 / 系统”
- 你就是“霜蓝”，在和用户直接聊天

目标：
让用户感觉是在和一个“长得像兽设，但本质是人类、有性格的霜蓝”交流，而不是动物或工具。
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
  const UserProfile({
    this.avatarUrl,
    this.avatarPath,
    this.name,
    this.pro = false,
  });

  final String? avatarUrl;
  final String? avatarPath;
  final String? name;
  final bool pro;

  bool get hasAvatar => avatarUrl != null && avatarUrl!.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (name != null) 'name': name,
      'pro': pro,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      avatarUrl: (json['avatar_url'] ?? json['avatarUrl'])?.toString(),
      avatarPath: (json['avatar_path'] ?? json['avatarPath'])?.toString(),
      name: json['name']?.toString(),
      pro: json['pro'] == true,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoning,
    this.furryEvents,
  });

  final String role;
  final String content;
  final String? reasoning;
  // 兽聚卡片数据（仅本地/云端持久化用，不发送给模型）
  final List<dynamic>? furryEvents;

  bool get isUser => role == 'user';
  bool get isSystem => role == 'system';
  bool get hasReasoning => reasoning != null && reasoning!.trim().isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      if (hasReasoning) 'reasoning': reasoning,
      if (furryEvents != null && furryEvents!.isNotEmpty)
        'furryEvents': furryEvents,
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
      furryEvents: json['furryEvents'] is List
          ? json['furryEvents'] as List<dynamic>
          : null,
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
  const UsageLimitException({this.message = '今日次数已用完', this.remain = 0});

  final String message;
  final int remain;

  @override
  String toString() => message;
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
  static const String _usageRemainPrefix = 'usage_remain_';
  static const String _usageRemainDatePrefix = 'usage_remain_date_';

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
    } catch (e) {
      debugPrint('Read user error: $e');
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

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. 清除登录信息
    await clearSession();

    // 2. 删除所有对话缓存（conversations_ 前缀）
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('conversations_')) {
        await prefs.remove(key);
      }
    }

    // 3. 删除用户资料缓存（profile 前缀）
    for (final key in keys) {
      if (key.startsWith(profileCachePrefix)) {
        await prefs.remove(key);
      }
    }

    // 4. 删除本地额度缓存
    for (final key in keys) {
      if (key.startsWith(_usageRemainPrefix) ||
          key.startsWith(_usageRemainDatePrefix)) {
        await prefs.remove(key);
      }
    }
  }

  Future<int> readRemainingCount(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _todayDateCN();
    final dateKey = '$_usageRemainDatePrefix$userId';
    final countKey = '$_usageRemainPrefix$userId';
    if (prefs.getString(dateKey) != today) return freeDailyLimit;

    final value = prefs.getInt(countKey);
    if (value == null) return freeDailyLimit;
    return value.clamp(0, freeDailyLimit).toInt();
  }

  Future<void> saveRemainingCount(String userId, int remain) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = remain.clamp(0, freeDailyLimit).toInt();
    await prefs.setString('$_usageRemainDatePrefix$userId', _todayDateCN());
    await prefs.setInt('$_usageRemainPrefix$userId', normalized);
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
    } catch (e) {
      debugPrint('Read conversations error: $e');
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
    } catch (e) {
      debugPrint('Read profile error: $e');
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
  static http.Client? _cachedClient;

  http.Client get client => _client ?? (_cachedClient ??= http.Client());

  void close() {
    _client?.close();
    _cachedClient?.close();
    _cachedClient = null;
  }

  Future<void> requestCode(String email, {required String captchaToken}) async {
    final response = await client
        .post(
          Uri.parse('$sunlandApiBase/send-code'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'cfToken': captchaToken}),
        )
        .timeout(const Duration(seconds: 15));

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
    final response = await client
        .post(
          Uri.parse('$sunlandApiBase/verify-code'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': email,
            'code': code,
            'cfToken': captchaToken,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final body = _decodeJson(response.body);
    final token = body['token']?.toString();

    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        token == null ||
        token.isEmpty) {
      throw ApiException((body['error'] ?? '验证码错误或验证失败').toString());
    }

    final rawUser = body['user'];

    SunlandUser? user;

    if (rawUser is Map) {
      user = SunlandUser.fromJson(
        Map<String, dynamic>.from(
          rawUser.map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
    } else {
      user = userFromJwt(token);
    }

    // 必须从服务器返回完整的用户信息
    if (user == null) {
      throw ApiException('Invalid token: unable to extract user information');
    }

    return (token: token, user: user);
  }

  Future<({String token, SunlandUser user})?> refreshToken(
    String oldToken,
  ) async {
    final response = await client.post(
      Uri.parse('$sunlandApiBase/refresh'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $oldToken',
      },
      body: jsonEncode(<String, dynamic>{}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final body = _decodeJson(response.body);
    final token = body['token']?.toString();
    if (token == null || token.isEmpty) return null;

    final rawUser = body['user'];
    SunlandUser? user;
    if (rawUser is Map) {
      user = SunlandUser.fromJson(
        Map<String, dynamic>.from(
          rawUser.map((k, v) => MapEntry(k.toString(), v)),
        ),
      );
    }
    user ??= userFromJwt(token);
    if (user == null) return null;

    return (token: token, user: user);
  }
}

class SunlandApiClient {
  SunlandApiClient({required this.tokenProvider, http.Client? client})
    : _client = client;

  final Future<String?> Function() tokenProvider;
  final http.Client? _client;
  static http.Client? _cachedClient;

  http.Client get client => _client ?? (_cachedClient ??= http.Client());

  void close() {
    _client?.close();
    _cachedClient?.close();
    _cachedClient = null;
  }

  Future<AiResponse> sendChat({
    required List<ChatMessage> messages,
    required String model,
    required bool deep,
    void Function(int remain)? onRemainUpdated,
  }) async {
    AiResponse? latest;
    await for (final response in sendChatStream(
      messages: messages,
      model: model,
      deep: deep,
      onRemainUpdated: onRemainUpdated,
    )) {
      latest = response;
    }

    if (latest == null || latest.content.trim().isEmpty) {
      throw const ApiException('AI返回空内容');
    }
    return latest;
  }

  /// 新增：流式聊天 API
  Stream<AiResponse> sendChatStream({
    required List<ChatMessage> messages,
    required String model,
    required bool deep,
    void Function(int remain)? onRemainUpdated,
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
      'model': model,
      'deep': deep,
      'stream': true, // 关键：告诉后端走流式
    });

    http.StreamedResponse streamed;
    try {
      streamed = await client.send(req).timeout(const Duration(seconds: 60));
    } catch (e) {
      rethrow;
    }

    if (streamed.statusCode == 401) throw const AuthExpiredException();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final errorText = await streamed.stream.bytesToString();
      throw _exceptionForApiError(streamed.statusCode, errorText);
    }

    final remain = int.tryParse(streamed.headers['x-remain'] ?? '');
    if (remain != null) {
      onRemainUpdated?.call(remain);
    }

    final decoder = utf8.decoder;
    String buffer = '';
    final textBuffer = StringBuffer();
    String? reasoning;

    await for (final chunk in streamed.stream.transform(decoder)) {
      buffer += chunk;

      // 按行切分（兼容 SSE / JSONL）
      final lines = buffer.split(RegExp(r'\r?\n'));
      buffer = lines.isNotEmpty ? lines.removeLast() : '';
      if (lines.isEmpty) continue;

      for (var line in lines) {
        line = line.trim();
        if (line.isEmpty) continue;

        // 兼容 SSE: data: {...}
        if (line.startsWith('data:')) {
          line = line.substring(5).trim();
        }

        if (line == '[DONE]') {
          // 确保最后一个chunk被发送
          final finalText = textBuffer.toString().trim();

          // 如果有reasoning或content，始终发送一次完整响应
          if (reasoning != null && reasoning.isNotEmpty) {
            yield AiResponse(content: finalText, reasoning: reasoning);
          } else if (finalText.isNotEmpty) {
            yield AiResponse(content: finalText, reasoning: reasoning);
          }
          return;
        }

        final json = _tryDecode(line);
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

              // 先累加 reasoning，再输出，避免 UI 慢一拍
              if (r != null && r.isNotEmpty) {
                reasoning = (reasoning ?? '') + r;
              }
              if (piece.isNotEmpty) {
                textBuffer.write(piece);
                yield AiResponse(
                  content: textBuffer.toString(),
                  reasoning: reasoning,
                );
              }
            }
          }
        }
      }
    }

    // 兜底
    final finalText = textBuffer.toString();
    if (finalText.isNotEmpty) {
      yield AiResponse(content: finalText, reasoning: reasoning);
    }
  }

  Future<String?> generateTitle({
    required String userMessage,
    required String aiMessage,
  }) async {
    final title = userMessage.trim().replaceAll('\n', ' ');
    if (title.length < 3) return null;

    final chars = title.characters;
    return chars.length > 12 ? '${chars.take(12)}…' : title;
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
    } catch (e) {
      assert(() {
        debugPrint('JSON decode failed: $text');
        return true;
      }());
      return null;
    }
  }
}

Exception _exceptionForApiError(int statusCode, String bodyText) {
  final body = _tryDecodeJsonObject(bodyText);
  final error = (body['error'] ?? body['message'])?.toString();

  if (statusCode == 429 && error == 'LIMIT') {
    final remain = int.tryParse((body['remain'] ?? '0').toString()) ?? 0;
    return UsageLimitException(remain: remain);
  }

  if (statusCode == 403 && error == 'PRO_REQUIRED') {
    return const ApiException('Pro 功能需要激活后才能使用');
  }

  if (statusCode == 429) {
    return ApiException(error ?? '请求过快，请稍后再试');
  }

  return ApiException(error ?? '请求失败：$statusCode');
}

Map<String, dynamic> _tryDecodeJsonObject(String text) {
  if (text.trim().isEmpty) return <String, dynamic>{};

  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return Map<String, dynamic>.from(
        decoded.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
  } catch (_) {}

  return <String, dynamic>{};
}

class SupabaseAiRepository {
  Future<void> ensureProfile(String userId) async {
    final existing = await _client
        .from('user_profiles')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();

    if (existing == null) {
      await _client.from('user_profiles').insert({
        'user_id': userId,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  SupabaseClient get _client => Supabase.instance.client;

  Future<bool> isActivated(String userId) async {
    final codeData = await _client
        .from('activation_codes')
        .select('code')
        .eq('used_by', userId)
        .maybeSingle();
    if (codeData != null) return true;

    final profileData = await _client
        .from('user_profiles')
        .select('pro')
        .eq('user_id', userId)
        .maybeSingle();
    return profileData?['pro'] == true;
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
        .select('avatar_url, avatar_path, name, pro')
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

  Future<String?> loadNickname(String userId) async {
    final data = await _client
        .from('user_profiles')
        .select('name')
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return null;
    return data['name']?.toString();
  }

  Future<void> saveNickname(String userId, String nickname) async {
    await _client.from('user_profiles').upsert({
      'user_id': userId,
      'name': nickname,
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
        final record = updated[0];
        if ((record['used_by'] ?? '') != userId) {
          return ActivationResult.raceLost;
        }
        await _client.from('user_profiles').upsert({
          'user_id': userId,
          'pro': true,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
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
    debugPrint('Decode user from JWT error: $error');
    return null;
  }
}

bool isJwtExpired(String token, {Duration skew = Duration.zero}) {
  try {
    final parts = token.split('.');
    if (parts.length < 2) return true;
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return true;
    final exp = decoded['exp'];
    final seconds = exp is int ? exp : int.tryParse(exp?.toString() ?? '');
    if (seconds == null || seconds < 0) return true;
    try {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      return expiresAt.isBefore(DateTime.now().add(skew));
    } catch (e) {
      debugPrint('JWT expiration parse error: $e');
      return true;
    }
  } catch (e) {
    debugPrint('JWT validation error: $e');
    return true;
  }
}

String _todayDateCN() {
  final cst = DateTime.now().toUtc().add(const Duration(hours: 8));
  final month = cst.month.toString().padLeft(2, '0');
  final day = cst.day.toString().padLeft(2, '0');
  return '${cst.year}-$month-$day';
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

/// 移动端 ML Kit OCR；桌面/Web 无本地 OCR。
bool get supportsLocalImageOcr {
  if (kIsWeb) return false;
  return Platform.isAndroid || Platform.isIOS;
}

const String kOcrPrivacyTip =
    '图片仅在本地识别文字，原图不会上传到服务器。';

const String kOcrEmptyMarker = '（未识别到文字）';

/// 合并用户文字与 OCR 块，供 API / 云端同步使用。
String buildApiMessageWithOcr({
  required String userText,
  String? ocrBlock,
}) {
  final ocr = ocrBlock?.trim() ?? '';
  final question = userText.trim();

  if (ocr.isEmpty) {
    return question;
  }
  if (question.isEmpty) {
    return '【图片识别内容】\n$ocr\n\n请根据以上内容回答。';
  }
  return '用户问题：$question\n\n【图片识别内容】\n$ocr';
}

/// OCR 结果中是否包含可用文字（非空且非全部「未识别到文字」）。
bool ocrBlockHasUsableText(String? ocrBlock) {
  if (ocrBlock == null || ocrBlock.trim().isEmpty) return false;
  final stripped = ocrBlock
      .replaceAll(RegExp(r'【图\d+】\s*'), '')
      .replaceAll(kOcrEmptyMarker, '')
      .replaceAll(RegExp(r'（后续文字因长度限制已省略）'), '')
      .trim();
  return stripped.isNotEmpty;
}

class ImageOcrResult {
  const ImageOcrResult({required this.block, required this.hasUsableText});

  final String block;
  final bool hasUsableText;
}

// ====== 构建带系统提示的聊天历史 ======
List<ChatMessage> buildChatHistory({
  required List<Map<String, dynamic>> rawMessages,
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
            m["text"] != "正在识别图片文字..." &&
            m["isReasoning"] != true &&
            !(m["isUser"] != true &&
                (m["text"] ?? '').toString().trim().isEmpty),
      )
      .toList();

  final recent = valid.length > maxHistory
      ? valid.sublist(valid.length - maxHistory)
      : valid;

  for (var msg in recent) {
    var content = (msg["apiContent"] ?? msg["text"] ?? '').toString().trim();
    var reasoning = msg["reasoning"]?.toString().trim();
    if ((reasoning == null || reasoning.isEmpty) && content.startsWith('🧠 ')) {
      final parts = content.split('\n\n');
      reasoning = parts.first.replaceFirst('🧠 ', '').trim();
      content = parts.length > 1 ? parts.sublist(1).join('\n\n').trim() : '';
    }

    if (content.isEmpty) continue;

    history.add(
      ChatMessage(
        role: msg["isUser"] == true ? "user" : "assistant",
        content: content,
        reasoning: reasoning,
      ),
    );
  }

  return history;
}

// ====== 新增：高阶聊天包装 API ======
Future<AiResponse> sendSmartChat({
  required SunlandApiClient client,
  required List<Map<String, dynamic>> rawMessages,
  required String model,
  required bool deep,
}) async {
  final history = buildChatHistory(rawMessages: rawMessages, maxHistory: 20);

  return await client.sendChat(messages: history, model: model, deep: deep);
}

// ====== 高阶流式聊天包装 API ======
Stream<AiResponse> sendSmartChatStream({
  required SunlandApiClient client,
  required List<Map<String, dynamic>> rawMessages,
  required String model,
  required bool deep,
  void Function(int remain)? onRemainUpdated,
}) {
  final history = buildChatHistory(rawMessages: rawMessages, maxHistory: 20);
  return client.sendChatStream(
    messages: history,
    model: model,
    deep: deep,
    onRemainUpdated: onRemainUpdated,
  );
}

Future<String?> _preprocessImageForOcr(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return path;

    const maxSide = 2048;
    img.Image processed = decoded;
    if (decoded.width > maxSide || decoded.height > maxSide) {
      processed = img.copyResize(
        decoded,
        width: decoded.width >= decoded.height ? maxSide : null,
        height: decoded.height > decoded.width ? maxSide : null,
      );
    }

    final jpeg = img.encodeJpg(processed, quality: 85);
    final tempDir = await getTemporaryDirectory();
    final outPath =
        '${tempDir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(jpeg, flush: true);
    return outPath;
  } catch (e) {
    debugPrint('Image preprocess failed for $path: $e');
    return path;
  }
}

// ====== 本地 OCR 提取（仅 Android / iOS）======
Future<ImageOcrResult> extractTextFromImages(List<String> imagePaths) async {
  if (!supportsLocalImageOcr || imagePaths.isEmpty) {
    return const ImageOcrResult(block: '', hasUsableText: false);
  }

  const perImageLimit = 1000;
  const totalLimit = 3000;
  final buffer = StringBuffer();
  final recognizer = TextRecognizer(script: TextRecognitionScript.chinese);
  var anyUsable = false;

  try {
    for (var i = 0; i < imagePaths.length; i++) {
      if (buffer.length >= totalLimit) break;

      final path = imagePaths[i];
      final ocrPath = await _preprocessImageForOcr(path);
      if (ocrPath == null) {
        buffer.writeln('【图${i + 1}】');
        buffer.writeln(kOcrEmptyMarker);
        buffer.writeln();
        continue;
      }

      final file = File(ocrPath);
      if (!await file.exists()) continue;

      try {
        final recognizedText =
            await recognizer.processImage(InputImage.fromFilePath(ocrPath));

        final text = recognizedText.text.trim();
        buffer.writeln('【图${i + 1}】');
        if (text.isEmpty) {
          buffer.writeln(kOcrEmptyMarker);
        } else {
          anyUsable = true;
          final remaining = totalLimit - buffer.length;
          if (remaining <= 0) break;

          final limited = text.characters.length > perImageLimit
              ? text.characters.take(perImageLimit).toString()
              : text;
          final clipped = limited.characters.length > remaining
              ? limited.characters.take(remaining).toString()
              : limited;

          buffer.writeln(clipped);
          if (limited.characters.length > clipped.characters.length) {
            buffer.writeln('（后续文字因长度限制已省略）');
          }
        }
        buffer.writeln();
      } catch (e) {
        debugPrint('OCR error on $path: $e');
        buffer.writeln('【图${i + 1}】');
        buffer.writeln(kOcrEmptyMarker);
        buffer.writeln();
      } finally {
        if (ocrPath != path) {
          try { await File(ocrPath).delete(); } catch (_) {}
        }
      }
    }
  } finally {
    await recognizer.close();
  }

  final block = buffer.toString().trim();
  return ImageOcrResult(
    block: block,
    hasUsableText: anyUsable && ocrBlockHasUsableText(block),
  );
}

String buildConversationTitle(String text) {
  final trimmed = text.trim().replaceAll('\n', ' ');
  if (trimmed.isEmpty) return '新对话';

  final chars = trimmed.characters;
  return chars.length > 15 ? '${chars.take(15)}…' : trimmed;
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
        if (compactTerm.length >= 2 && compact.contains(compactTerm)) {
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
