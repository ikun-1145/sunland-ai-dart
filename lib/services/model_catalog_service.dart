import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

typedef ModelCatalogRowLoader = Future<List<Map<String, dynamic>>> Function();

class CatalogModel {
  const CatalogModel({
    required this.id,
    required this.provider,
    required this.displayName,
    required this.modelName,
    required this.freeEnabled,
    required this.proEnabled,
    required this.enabled,
    required this.sortOrder,
  });

  factory CatalogModel.fromJson(Map<String, dynamic> json) {
    String text(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid model $key');
      }
      return value.trim();
    }

    final provider = text('provider');
    if (provider != 'deepseek' && provider != 'sunland') {
      throw const FormatException('Unsupported model provider');
    }
    for (final key in ['free_enabled', 'pro_enabled', 'enabled']) {
      if (json[key] is! bool) throw FormatException('Invalid model $key');
    }
    if (json['sort_order'] is! int) {
      throw const FormatException('Invalid model sort_order');
    }
    return CatalogModel(
      id: text('id'),
      provider: provider,
      displayName: text('display_name'),
      modelName: text('model_name'),
      freeEnabled: json['free_enabled'] as bool,
      proEnabled: json['pro_enabled'] as bool,
      enabled: json['enabled'] as bool,
      sortOrder: json['sort_order'] as int,
    );
  }

  final String id;
  final String provider;
  final String displayName;
  final String modelName;
  final bool freeEnabled;
  final bool proEnabled;
  final bool enabled;
  final int sortOrder;

  bool isAvailableFor({required bool isPro}) =>
      enabled && (isPro ? proEnabled : freeEnabled);
}

class ModelCatalogService {
  ModelCatalogService({
    SupabaseClient? client,
    ModelCatalogRowLoader? rowLoader,
    Duration requestTimeout = const Duration(seconds: 7),
  }) : _client = client,
       _rowLoader = rowLoader,
       _requestTimeout = requestTimeout;

  final SupabaseClient? _client;
  final ModelCatalogRowLoader? _rowLoader;
  final Duration _requestTimeout;
  Future<List<CatalogModel>>? _inFlightRequest;

  Future<List<CatalogModel>> fetchModels() {
    final pending = _inFlightRequest;
    if (pending != null) return pending;
    late final Future<List<CatalogModel>> request;
    request = _fetchModels().whenComplete(() {
      if (identical(_inFlightRequest, request)) _inFlightRequest = null;
    });
    _inFlightRequest = request;
    return request;
  }

  Future<List<CatalogModel>> _fetchModels() async {
    final rows = await (_rowLoader?.call() ?? _fetchRows()).timeout(
      _requestTimeout,
    );
    final models =
        rows.map(CatalogModel.fromJson).where((m) => m.enabled).toList()
          ..sort((a, b) {
            final order = a.sortOrder.compareTo(b.sortOrder);
            return order == 0 ? a.id.compareTo(b.id) : order;
          });
    return List.unmodifiable(models);
  }

  Future<List<Map<String, dynamic>>> _fetchRows() async {
    return await (_client ?? Supabase.instance.client)
        .from('ai_models')
        .select(
          'id,provider,display_name,model_name,free_enabled,pro_enabled,enabled,sort_order',
        )
        .eq('enabled', true)
        .order('sort_order')
        .order('id');
  }
}
