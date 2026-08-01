import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ── 原有单事件模型（保留不变）────────────────────────────────────────────

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

class WeatherApi {
  // 🧠 天气缓存：key = city|date
  static final Map<String, _WeatherCacheItem> _cache = {};

  static Future<FurryEventWeather?> fetch(String city, String date) async {
    try {
      if (city.isEmpty || date.isEmpty) return null;

      final dt = DateTime.tryParse(date);
      if (dt == null) return null;

      final d = dt.toIso8601String().split("T")[0];

      // 🚀 方案二：如果日期太远，用“今天天气”兜底
      final now = DateTime.now();
      final diff = dt.difference(now).inDays;

      if (diff > 10) {
        final todayStr = now.toIso8601String().split("T")[0];

        // 防止无限递归
        if (todayStr != d) {
          debugPrint("⏭ 天气超范围，使用今日天气替代: $city $date");
          return await fetch(city, todayStr);
        }
      }

      final key = "$city|$d";

      // ✅ 命中缓存（1天内有效）
      final cached = _cache[key];
      if (cached != null) {
        final diff = DateTime.now().difference(cached.time);
        if (diff.inHours < 24) {
          return cached.weather;
        } else {
          // ❌ 过期删除
          _cache.remove(key);
        }
      }

      double? lat;
      double? lon;

      // 🌍 先用地理编码API（支持所有城市）
      try {
        final geoRes = await http.get(
          Uri.parse(
            "https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}",
          ),
        );

        final geoJson = jsonDecode(geoRes.body);

        if (geoJson['results'] != null && geoJson['results'].isNotEmpty) {
          lat = geoJson['results'][0]['latitude'];
          lon = geoJson['results'][0]['longitude'];
          debugPrint("🌍 地理API命中: $city -> $lat,$lon");
        }
      } catch (e) {
        debugPrint("❌ 地理API失败: $e");
      }

      // 🔥 fallback：常见城市
      if (lat == null || lon == null) {
        const cityMap = {
          // 一线 / 核心
          "上海": [31.23, 121.47],
          "北京": [39.90, 116.40],
          "广州": [23.13, 113.26],
          "深圳": [22.54, 114.06],

          // 新一线
          "成都": [30.67, 104.06],
          "杭州": [30.27, 120.15],
          "武汉": [30.59, 114.30],
          "重庆": [29.56, 106.55],
          "西安": [34.34, 108.94],
          "南京": [32.06, 118.79],
          "天津": [39.13, 117.20],
          "苏州": [31.30, 120.62],
          "郑州": [34.75, 113.62],
          "长沙": [28.23, 112.93],

          // 东部沿海
          "青岛": [36.07, 120.38],
          "宁波": [29.87, 121.55],
          "厦门": [24.48, 118.08],
          "福州": [26.08, 119.30],
          "温州": [27.99, 120.70],

          // 华南
          "佛山": [23.02, 113.12],
          "东莞": [23.02, 113.75],
          "南宁": [22.82, 108.32],
          "海口": [20.02, 110.35],

          // 东北（你缺的重点）
          "长春": [43.88, 125.32],
          "沈阳": [41.80, 123.43],
          "大连": [38.91, 121.61],
          "哈尔滨": [45.80, 126.53],

          // 西南
          "昆明": [25.04, 102.71],
          "贵阳": [26.65, 106.63],
          "拉萨": [29.65, 91.13],

          // 西北
          "兰州": [36.06, 103.83],
          "西宁": [36.62, 101.78],
          "乌鲁木齐": [43.82, 87.62],

          // 港台
          "新北": [25.01, 121.46],
          "台北": [25.03, 121.56],
          "高雄": [22.63, 120.30],
          "香港": [22.30, 114.17],
        };

        for (final key in cityMap.keys) {
          if (city.contains(key)) {
            lat = cityMap[key]![0];
            lon = cityMap[key]![1];
            debugPrint("⚠️ fallback命中: $city -> $lat,$lon");
            break;
          }
        }
      }

      if (lat == null || lon == null) {
        debugPrint("❌ 无法获取城市坐标: $city");
        return null;
      }
      debugPrint("🌤 请求天气: city=$city date=$d lat=$lat lon=$lon");
      final res = await http.get(
        Uri.parse(
          "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&daily=weathercode,temperature_2m_max,temperature_2m_min&start_date=$d&end_date=$d&timezone=Asia%2FShanghai",
        ),
      );

      final json = jsonDecode(res.body);

      final codes = json['daily']?['weathercode'];
      if (json['daily'] == null || codes == null || (codes as List).isEmpty) {
        debugPrint("❌ 天气API返回异常: $json");
        return null;
      }

      final weatherCode = _toInt(codes[0]);
      final weather = FurryEventWeather(
        date: d,
        code: weatherCode,
        label: _mapWeather(weatherCode),
        tempMax: _toDouble(json['daily']['temperature_2m_max']?[0]),
        tempMin: _toDouble(json['daily']['temperature_2m_min']?[0]),
      );

      // 💾 写入缓存
      _cache[key] = _WeatherCacheItem(weather);

      return weather;
    } catch (e) {
      debugPrint("天气获取失败: $e");
      return null;
    }
  }
}

String _mapWeather(int? code) {
  if (code == null) return "未知";
  if (code == 0) return "晴";
  if (code <= 3) return "多云";
  if (code <= 48) return "雾";
  if (code <= 67) return "小雨";
  if (code <= 77) return "雪";
  if (code <= 82) return "中雨";
  if (code <= 99) return "雷暴";
  return "未知";
}

class FurryEventEnriched {
  final String? sourceId;
  final String name;
  final String? fullName;
  final String startAt;
  final String endAt;
  final String? province;
  final String city;
  final String? address;
  final String venue;
  final String? coverUrl;
  final String? sourceUrl;
  final String? organization;
  final String? detail;
  final String? status;
  final int? sourceState;
  final String? sourceStateText;
  final int? daysUntil;

  // ⚠️ 后端天气可能为空，前端需实时调用 WeatherApi.fetch
  final FurryEventWeather? weather;
  final String? ctripUrl;
  final String? meituanUrl;

  const FurryEventEnriched({
    this.sourceId,
    required this.name,
    this.fullName,
    required this.startAt,
    required this.endAt,
    this.province,
    required this.city,
    this.address,
    required this.venue,
    this.coverUrl,
    this.sourceUrl,
    this.organization,
    this.detail,
    this.status,
    this.sourceState,
    this.sourceStateText,
    this.daysUntil,
    this.weather,
    this.ctripUrl,
    this.meituanUrl,
  });

  factory FurryEventEnriched.fromMap(Map<String, dynamic> m) {
    final weatherRaw = m['weather'];
    final hotelsRaw = m['hotels'];
    final venue = m['venue']?.toString() ?? '';

    return FurryEventEnriched(
      sourceId: m['source_id']?.toString(),
      name: m['name']?.toString() ?? '',
      fullName: m['full_name']?.toString(),
      startAt: m['start_at']?.toString() ?? '',
      endAt: m['end_at']?.toString() ?? '',
      province: m['province']?.toString(),
      city: m['city']?.toString() ?? '',
      address: m['address']?.toString(),
      venue: venue,
      coverUrl: m['cover']?.toString(),
      sourceUrl: m['source_url']?.toString(),
      organization: m['organization']?.toString(),
      detail: m['detail']?.toString(),
      status: m['status']?.toString(),
      sourceState: _toInt(m['source_state']),
      sourceStateText: m['source_state_text']?.toString(),
      daysUntil: _toInt(m['days_until']),
      weather: weatherRaw is Map<String, dynamic>
          ? FurryEventWeather.fromMap(weatherRaw)
          : null,
      ctripUrl: (hotelsRaw is Map && venue.isNotEmpty)
          ? hotelsRaw['ctripUrl']?.toString()
          : null,
      meituanUrl: (hotelsRaw is Map && venue.isNotEmpty)
          ? hotelsRaw['meituanUrl']?.toString()
          : null,
    );
  }

  factory FurryEventEnriched.fromHistoricalMap(Map<String, dynamic> m) {
    return FurryEventEnriched.fromMap({
      ...m,
      'source_id': m['source_id'] ?? m['sourceId'],
      'full_name': m['full_name'] ?? m['fullName'] ?? m['name'],
      'start_at': m['start_at'] ?? m['startAt'],
      'end_at': m['end_at'] ?? m['endAt'],
      'address': m['address'] ?? m['venue'],
      'venue': m['venue'],
      'cover': m['cover'] ?? m['coverUrl'] ?? m['cover_url'],
      'source_url': m['source_url'] ?? m['sourceUrl'],
      'status': m['status'] ?? m['rawStatus'] ?? m['raw_status'],
      'source_state': m['source_state'] ?? m['sourceState'],
      'source_state_text': m['source_state_text'] ?? m['sourceStateText'],
      'organization': m['organization'] ?? m['organizer'],
    });
  }

  String get displayName =>
      (fullName?.trim().isNotEmpty ?? false) ? fullName!.trim() : name;

  Map<String, dynamic> toMap() => {
    'source_id': sourceId,
    'name': name,
    'full_name': fullName,
    'start_at': startAt,
    'end_at': endAt,
    'province': province,
    'city': city,
    'address': address,
    'venue': venue,
    'cover': coverUrl,
    'source_url': sourceUrl,
    'organization': organization,
    'detail': detail,
    'status': status,
    'source_state': sourceState,
    'source_state_text': sourceStateText,
    'days_until': daysUntil,
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
          .whereType<Map>()
          .map((e) => FurryEventEnriched.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      cached: m['cached'] == true,
      total: (m['total'] as num?)?.toInt() ?? 0,
    );
  }
}

// ⭐ 天气缓存结构（必须在类外）
class _WeatherCacheItem {
  final FurryEventWeather weather;
  final DateTime time;

  _WeatherCacheItem(this.weather) : time = DateTime.now();
}

class FurryEventSearchApi {
  // 兽聚查询入口：城市 / 月份 / 年份均可选，只通过公开 Edge Function 查询。
  // 参数解析与跨轮上下文合并由调用方（main.dart 的 _resolveFurryQueryParams）负责。
  static Future<FurryEventSearchResult> search({
    String? city,
    int? month,
    int? year,
  }) async {
    return _doSearch(city: city, month: month, year: year);
  }

  static Future<FurryEventSearchResult> _doSearch({
    String? city,
    int? month,
    int? year,
  }) async {
    final client = Supabase.instance.client;
    try {
      final normalizedCity = city?.trim().isNotEmpty == true
          ? city!.trim()
          : null;
      final response = await client.functions.invoke(
        'furry-event-search',
        body: {'city': ?normalizedCity, 'month': ?month, 'year': ?year},
      );
      if (response.data is! Map) throw Exception('兽聚查询返回格式无效');
      return FurryEventSearchResult.fromMap(
        Map<String, dynamic>.from(response.data as Map),
      );
    } catch (e) {
      throw Exception('兽聚查询失败');
    }
  }
}
