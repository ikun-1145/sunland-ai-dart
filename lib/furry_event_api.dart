import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── 原有单事件模型（保留不变）────────────────────────────────────────────

class FurryEvent {
  final String name;
  final String start;
  final String end;
  final String city;
  final String venue;
  final String cover;

  FurryEvent({
    required this.name,
    required this.start,
    required this.end,
    required this.city,
    required this.venue,
    required this.cover,
  });

  factory FurryEvent.fromJson(Map<String, dynamic> json) {
    final event = json["pageProps"]["event"];

    return FurryEvent(
      name: event["name"],
      start: event["startAt"],
      end: event["endAt"],
      city: event["region"]["name"],
      venue: event["address"],
      cover: "https://www.furrycons.cn/" + (event["thumbnail"] ?? ""),
    );
  }
}

class FurryEventApi {
  static Future<FurryEvent> fetchEvent(String url) async {
    final res = await http.get(Uri.parse(url));

    if (res.statusCode != 200) {
      throw Exception("获取失败");
    }

    final data = jsonDecode(res.body);
    return FurryEvent.fromJson(data);
  }
}

// ── 通过 Supabase Edge Function 搜索兽聚（含天气 + 酒店链接）────────────

// 容错数值解析：Postgres NUMERIC 经 PostgREST 序列化时可能为数字或字符串，
// 两种情况都安全转换，避免硬 `as num` 在字符串场景抛 TypeError。
double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

class FurryEventWeather {
  final String? date;
  final int? code;
  final String? label;
  final double? tempMax;
  final double? tempMin;
  final double? precipMm;

  const FurryEventWeather({
    this.date,
    this.code,
    this.label,
    this.tempMax,
    this.tempMin,
    this.precipMm,
  });

  factory FurryEventWeather.fromMap(Map<String, dynamic> m) {
    return FurryEventWeather(
      date: m['date']?.toString(),
      code: _toInt(m['code']),
      label: m['label']?.toString(),
      tempMax: _toDouble(m['tempMax']),
      tempMin: _toDouble(m['tempMin']),
      precipMm: _toDouble(m['precipMm']),
    );
  }

  Map<String, dynamic> toMap() => {
        'date': date,
        'code': code,
        'label': label,
        'tempMax': tempMax,
        'tempMin': tempMin,
        'precipMm': precipMm,
      };
}

class FurryEventEnriched {
  final String name;
  final String startAt;
  final String endAt;
  final String city;
  final String venue;
  final String? coverUrl;
  final String? sourceUrl;
  final FurryEventWeather? weather;
  final String? ctripUrl;
  final String? meituanUrl;

  const FurryEventEnriched({
    required this.name,
    required this.startAt,
    required this.endAt,
    required this.city,
    required this.venue,
    this.coverUrl,
    this.sourceUrl,
    this.weather,
    this.ctripUrl,
    this.meituanUrl,
  });

  factory FurryEventEnriched.fromMap(Map<String, dynamic> m) {
    final weatherRaw = m['weather'];
    final hotelsRaw = m['hotels'];
    return FurryEventEnriched(
      name: m['name']?.toString() ?? '',
      startAt: m['startAt']?.toString() ?? '',
      endAt: m['endAt']?.toString() ?? '',
      city: m['city']?.toString() ?? '',
      venue: m['venue']?.toString() ?? '',
      coverUrl: m['coverUrl']?.toString(),
      sourceUrl: m['sourceUrl']?.toString(),
      weather: weatherRaw is Map<String, dynamic>
          ? FurryEventWeather.fromMap(weatherRaw)
          : null,
      ctripUrl:
          hotelsRaw is Map ? hotelsRaw['ctripUrl']?.toString() : null,
      meituanUrl:
          hotelsRaw is Map ? hotelsRaw['meituanUrl']?.toString() : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'startAt': startAt,
        'endAt': endAt,
        'city': city,
        'venue': venue,
        'coverUrl': coverUrl,
        'sourceUrl': sourceUrl,
        'weather': weather?.toMap(),
        'hotels': {'ctripUrl': ctripUrl, 'meituanUrl': meituanUrl},
      };
}

class FurryEventSearchResult {
  final List<FurryEventEnriched> events;
  final bool cached;
  final int total;

  const FurryEventSearchResult({
    required this.events,
    required this.cached,
    required this.total,
  });

  factory FurryEventSearchResult.fromMap(Map<String, dynamic> m) {
    final rawList = (m['events'] as List?) ?? [];
    return FurryEventSearchResult(
      events: rawList
          .whereType<Map<String, dynamic>>()
          .map(FurryEventEnriched.fromMap)
          .toList(),
      cached: m['cached'] == true,
      total: (m['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class FurryEventSearchApi {
  static Future<FurryEventSearchResult> search({
    String? city,
    int? month,
    int? year,
  }) async {
    final client = Supabase.instance.client;
    try {
      final response = await client.functions.invoke(
        'furry-event-search',
        body: {
          if (city != null) 'city': city,
          if (month != null) 'month': month,
          if (year != null) 'year': year,
        },
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) throw Exception('兽聚查询返回格式错误');
      return FurryEventSearchResult.fromMap(data);
    } on FunctionException catch (e) {
      // functions_client 在非 2xx 时抛 FunctionException，错误体在 details 中
      final d = e.details;
      final msg = (d is Map) ? d['error']?.toString() : null;
      throw Exception(msg ?? '兽聚查询失败');
    }
  }
}
