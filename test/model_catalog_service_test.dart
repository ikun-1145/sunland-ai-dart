import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/model_catalog_service.dart';

Map<String, dynamic> _row({
  required String id,
  required String provider,
  required String name,
  required String model,
  required bool free,
  required bool pro,
  required int order,
  bool enabled = true,
}) => <String, dynamic>{
  'id': id,
  'provider': provider,
  'display_name': name,
  'model_name': model,
  'free_enabled': free,
  'pro_enabled': pro,
  'enabled': enabled,
  'sort_order': order,
};

void main() {
  test(
    'catalogue validates, filters disabled rows, and sorts stably',
    () async {
      final service = ModelCatalogService(
        rowLoader: () async => [
          _row(
            id: 'b',
            provider: 'deepseek',
            name: 'Pro',
            model: 'pro',
            free: false,
            pro: true,
            order: 20,
          ),
          _row(
            id: 'a',
            provider: 'deepseek',
            name: 'Flash',
            model: 'flash',
            free: true,
            pro: true,
            order: 10,
          ),
          _row(
            id: 'c',
            provider: 'sunland',
            name: 'Hidden',
            model: 'frost',
            free: true,
            pro: true,
            order: 0,
            enabled: false,
          ),
        ],
      );

      final models = await service.fetchModels();

      expect(models.map((model) => model.modelName), ['flash', 'pro']);
      expect(models.first.isAvailableFor(isPro: false), isTrue);
      expect(models.last.isAvailableFor(isPro: false), isFalse);
      expect(models.last.isAvailableFor(isPro: true), isTrue);
    },
  );

  test('catalogue rejects malformed rows and coalesces active loads', () async {
    final response = Completer<List<Map<String, dynamic>>>();
    var requests = 0;
    final service = ModelCatalogService(
      rowLoader: () {
        requests++;
        return response.future;
      },
    );

    final first = service.fetchModels();
    final second = service.fetchModels();
    expect(requests, 1);
    response.complete([
      _row(
        id: 'a',
        provider: 'unsupported',
        name: 'Bad',
        model: 'bad',
        free: true,
        pro: true,
        order: 0,
      ),
    ]);
    await expectLater(first, throwsFormatException);
    await expectLater(second, throwsFormatException);
  });
}
