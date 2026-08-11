import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AppConfigRowLoader = Future<Map<String, dynamic>?> Function();

class AppConfig {
  const AppConfig({
    required this.maintenanceEnabled,
    required this.maintenanceTitle,
    required this.maintenanceMessage,
    this.maintenanceEstimatedEnd,
  });

  static const defaults = AppConfig(
    maintenanceEnabled: false,
    maintenanceTitle: '服务器维护中',
    maintenanceMessage: '服务器正在进行维护，请稍后再试。',
  );

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final maintenanceEnabled = json['maintenance_enabled'];
    if (maintenanceEnabled is! bool) {
      throw const FormatException('maintenance_enabled must be a boolean');
    }

    final maintenanceTitle = _readRequiredText(
      json['maintenance_title'],
      'maintenance_title',
    );
    final maintenanceMessage = _readRequiredText(
      json['maintenance_message'],
      'maintenance_message',
    );

    return AppConfig(
      maintenanceEnabled: maintenanceEnabled,
      maintenanceTitle: maintenanceTitle,
      maintenanceMessage: maintenanceMessage,
      maintenanceEstimatedEnd: _readOptionalDateTime(
        json['maintenance_estimated_end'],
      ),
    );
  }

  final bool maintenanceEnabled;
  final String maintenanceTitle;
  final String maintenanceMessage;
  final DateTime? maintenanceEstimatedEnd;

  static String _readRequiredText(Object? value, String fieldName) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$fieldName must be a non-empty string');
    }
    return value.trim();
  }

  static DateTime? _readOptionalDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw const FormatException(
      'maintenance_estimated_end must be a valid timestamp',
    );
  }
}

class AppConfigService {
  AppConfigService({
    SupabaseClient? client,
    AppConfigRowLoader? rowLoader,
    Duration requestTimeout = const Duration(seconds: 7),
  }) : _client = client,
       _rowLoader = rowLoader,
       _requestTimeout = requestTimeout;

  final SupabaseClient? _client;
  final AppConfigRowLoader? _rowLoader;
  final Duration _requestTimeout;

  Future<AppConfig>? _inFlightRequest;

  Future<AppConfig> fetchAppConfig() {
    final inFlightRequest = _inFlightRequest;
    if (inFlightRequest != null) return inFlightRequest;

    late final Future<AppConfig> request;
    request = _fetchAppConfig().whenComplete(() {
      if (identical(_inFlightRequest, request)) {
        _inFlightRequest = null;
      }
    });
    _inFlightRequest = request;
    return request;
  }

  Future<AppConfig> _fetchAppConfig() async {
    try {
      final row = await (_rowLoader?.call() ?? _fetchGlobalConfigRow()).timeout(
        _requestTimeout,
      );
      if (row == null) return AppConfig.defaults;
      return AppConfig.fromJson(row);
    } on TimeoutException {
      debugPrint('App config request timed out; continuing in fail-open mode.');
      return AppConfig.defaults;
    } catch (error) {
      debugPrint(
        'App config request failed; continuing in fail-open mode: $error',
      );
      return AppConfig.defaults;
    }
  }

  Future<Map<String, dynamic>?> _fetchGlobalConfigRow() async {
    final response = await (_client ?? Supabase.instance.client)
        .from('app_config')
        .select(
          'maintenance_enabled, maintenance_title, maintenance_message, '
          'maintenance_estimated_end',
        )
        .eq('config_key', 'global')
        .maybeSingle();
    return response == null ? null : Map<String, dynamic>.from(response);
  }
}
