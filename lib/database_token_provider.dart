import 'dart:convert';

import 'package:http/http.dart' as http;

typedef AppTokenProvider = Future<String?> Function({bool forceRefresh});

class DatabaseTokenProvider {
  DatabaseTokenProvider({
    required this.appTokenProvider,
    http.Client? client,
    this.baseUrl = 'https://api.sunland.dev',
  }) : _client = client ?? http.Client();

  final AppTokenProvider appTokenProvider;
  final http.Client _client;
  final String baseUrl;
  String? _token;
  DateTime? _expiresAt;
  Future<String?>? _pending;
  int _generation = 0;

  Future<String?> getToken({bool forceRefresh = false}) {
    final now = DateTime.now();
    if (!forceRefresh &&
        _token != null &&
        _expiresAt != null &&
        _expiresAt!.isAfter(now.add(const Duration(minutes: 1)))) {
      return Future.value(_token);
    }
    if (_pending != null) return _pending!;
    final generation = _generation;
    late final Future<String?> request;
    request =
        _requestToken(
          forceAppRefresh: forceRefresh,
          generation: generation,
        ).whenComplete(() {
          if (identical(_pending, request)) _pending = null;
        });
    _pending = request;
    return request;
  }

  Future<String?> _requestToken({
    required bool forceAppRefresh,
    required int generation,
  }) async {
    var appToken = await appTokenProvider(forceRefresh: forceAppRefresh);
    if (appToken == null || appToken.isEmpty) return null;
    var response = await _client.post(
      Uri.parse('$baseUrl/v1/database-token'),
      headers: {
        'content-type': 'application/json',
        'authorization': 'Bearer $appToken',
      },
      body: '{}',
    );
    if (response.statusCode == 401 && !forceAppRefresh) {
      appToken = await appTokenProvider(forceRefresh: true);
      if (appToken == null || appToken.isEmpty) return null;
      response = await _client.post(
        Uri.parse('$baseUrl/v1/database-token'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $appToken',
        },
        body: '{}',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiTokenException('数据库访问凭证暂时不可用', response.statusCode);
    }
    if (generation != _generation) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['token'] is! String) {
      throw const ApiTokenException('数据库访问凭证格式无效');
    }
    final token = decoded['token'] as String;
    final claims = _decodeClaims(token);
    final appClaims = _decodeClaims(appToken);
    final userId = (appClaims['id'] ?? appClaims['sub'])?.toString();
    final exp = claims['exp'];
    if (claims['role'] != 'authenticated' ||
        claims['aud'] != 'authenticated' ||
        claims['id']?.toString() != userId ||
        claims['sub']?.toString() != userId ||
        exp is! num) {
      throw const ApiTokenException('数据库访问凭证校验失败');
    }
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(
      exp.toInt() * 1000,
      isUtc: true,
    );
    if (!expiresAt.isAfter(DateTime.now())) {
      throw const ApiTokenException('数据库访问凭证已过期');
    }
    _token = token;
    _expiresAt = expiresAt;
    return token;
  }

  void clear() {
    _generation++;
    _token = null;
    _expiresAt = null;
    _pending = null;
  }

  void dispose() {
    clear();
    _client.close();
  }

  Map<String, dynamic> _decodeClaims(String token) {
    try {
      final segment = token.split('.')[1];
      final decoded = utf8.decode(
        base64Url.decode(base64Url.normalize(segment)),
      );
      final value = jsonDecode(decoded);
      return value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }
}

class ApiTokenException implements Exception {
  const ApiTokenException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
