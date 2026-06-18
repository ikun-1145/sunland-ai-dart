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
  final String name;
  final String startAt;
  final String endAt;
  final String city;
  final String venue;

  final String? coverUrl;
  final String? sourceUrl;

  final String? rawStatus;
  final int? daysUntil;

  // ⚠️ 后端天气可能为空，前端需实时调用 WeatherApi.fetch
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
    this.rawStatus,
    this.daysUntil,
    this.weather,
    this.ctripUrl,
    this.meituanUrl,
  });

  factory FurryEventEnriched.fromMap(Map<String, dynamic> m) {
    debugPrint('fromMap keys: ${m.keys.toList()}');
    debugPrint('fromMap coverUrl raw: ${m['coverUrl']}');
    final weatherRaw = m['weather'];
    final hotelsRaw = m['hotels'];
    final venueStr = m['address']?.toString() ?? '';

    // 表内真实图片在 cover 列（furryfusion 图床，公网可直连、无防盗链）；
    // 兼容旧 cover_url 列。早期版本经 *.workers.dev 代理，该域名在国内网络
    // 不稳定/易被污染，反而导致图片加载失败，故直接使用原图地址。
    String? cover = (m['cover'] ?? m['cover_url'])?.toString();
    if (cover != null) {
      cover = cover.trim();
      if (!cover.startsWith('http')) cover = null;
    }

    return FurryEventEnriched(
      name: m['name']?.toString() ?? '',

      // ✅ 使用 snake_case
      startAt: m['start_at']?.toString() ?? '',
      endAt: m['end_at']?.toString() ?? '',

      city: m['city']?.toString() ?? '',

      // ✅ address = 酒店名
      venue: m['address']?.toString() ?? '',

      coverUrl: cover,

      // ✅ 跳转链接
      sourceUrl: m['source_url']?.toString(),

      // ✅ 新增字段
      rawStatus: m['raw_status']?.toString(),
      daysUntil: _toInt(m['days_until']),

      weather: weatherRaw is Map<String, dynamic>
          ? FurryEventWeather.fromMap(weatherRaw)
          : null,

      // ✅ 只有有酒店才给链接
      ctripUrl: (hotelsRaw is Map && venueStr.isNotEmpty)
          ? hotelsRaw['ctripUrl']?.toString()
          : null,
      meituanUrl: (hotelsRaw is Map && venueStr.isNotEmpty)
          ? hotelsRaw['meituanUrl']?.toString()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'start_at': startAt,
    'end_at': endAt,
    'city': city,
    'address': venue,
    'cover': coverUrl,
    'source_url': sourceUrl,
    'raw_status': rawStatus,
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
  // 兽聚查询入口：城市 / 月份 / 年份均可选，直接查 furry_events 表。
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
      // 动态构建查询，支持城市、月份和年份筛选
      var query = client.from('furry_events').select();

      // 城市筛选
      if (city != null && city.isNotEmpty) {
        query = query.ilike('city', '%$city%');
      }

      // 时间筛选：月份优先，其次年份，都没有则只看未来。
      // start_at 为 ISO 字符串列，区间用字典序比较（与 ISO 时间序一致）。
      final now = DateTime.now();
      DateTime? start;
      DateTime? end;
      if (month != null) {
        // 月份已指定：年份用显式值，否则自动推断（已过去的月份顺延到明年）
        final y = year ?? (month < now.month ? now.year + 1 : now.year);
        start = DateTime(y, month, 1);
        end = DateTime(y, month + 1, 1); // month==12 → 次年1月，Dart 自动归一化
      } else if (year != null) {
        // 仅指定年份：限定整年
        start = DateTime(year, 1, 1);
        end = DateTime(year + 1, 1, 1);
      } else {
        // 无年月约束：只返回未来活动
        start = now;
      }

      query = query.gte('start_at', start.toIso8601String());
      if (end != null) {
        query = query.lt('start_at', end.toIso8601String());
      }

      final res = await query.order('start_at');

      final list = (res as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      debugPrint('兽聚查询 city=$city month=$month year=$year → ${list.length} 条');

      // 严格语义：无匹配即返回空（由 UI 显示"没有找到相关兽聚活动"），不放宽时间/城市
      return FurryEventSearchResult(
        events: list.map(FurryEventEnriched.fromMap).toList(),
        cached: false,
        total: list.length,
      );
    } on PostgrestException catch (e) {
      throw Exception(e.message.isNotEmpty ? e.message : '兽聚查询失败');
    } catch (e) {
      throw Exception('兽聚查询失败');
    }
  }
}
