import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/app_config_service.dart';

Map<String, dynamic> _configRow({
  required bool maintenanceEnabled,
  Object? estimatedEnd,
}) {
  return <String, dynamic>{
    'maintenance_enabled': maintenanceEnabled,
    'maintenance_title': '计划维护',
    'maintenance_message': '服务正在升级。',
    'maintenance_estimated_end': estimatedEnd,
  };
}

void main() {
  group('AppConfigService', () {
    test('returns a disabled config when maintenance is off', () async {
      final service = AppConfigService(
        rowLoader: () async => _configRow(maintenanceEnabled: false),
      );

      final config = await service.fetchAppConfig();

      expect(config.maintenanceEnabled, isFalse);
      expect(config.maintenanceTitle, '计划维护');
    });

    test('parses enabled maintenance and its estimated end', () async {
      final service = AppConfigService(
        rowLoader: () async => _configRow(
          maintenanceEnabled: true,
          estimatedEnd: '2026-08-11T12:30:00+08:00',
        ),
      );

      final config = await service.fetchAppConfig();

      expect(config.maintenanceEnabled, isTrue);
      expect(
        config.maintenanceEstimatedEnd,
        DateTime.parse('2026-08-11T12:30:00+08:00'),
      );
    });

    test('fails open when the config row is missing', () async {
      final service = AppConfigService(rowLoader: () async => null);

      final config = await service.fetchAppConfig();

      expect(config.maintenanceEnabled, isFalse);
    });

    test('fails open when the response is invalid', () async {
      final service = AppConfigService(
        rowLoader: () async => <String, dynamic>{
          'maintenance_enabled': 'true',
          'maintenance_title': '计划维护',
          'maintenance_message': '服务正在升级。',
        },
      );

      final config = await service.fetchAppConfig();

      expect(config, same(AppConfig.defaults));
    });

    test('fails open when the estimated end cannot be parsed', () async {
      final service = AppConfigService(
        rowLoader: () async => _configRow(
          maintenanceEnabled: true,
          estimatedEnd: 'not-a-timestamp',
        ),
      );

      final config = await service.fetchAppConfig();

      expect(config, same(AppConfig.defaults));
    });

    test('fails open when the request throws', () async {
      final service = AppConfigService(
        rowLoader: () async => throw const FormatException('network error'),
      );

      final config = await service.fetchAppConfig();

      expect(config.maintenanceEnabled, isFalse);
    });

    test('fails open when the request times out', () async {
      final pendingResponse = Completer<Map<String, dynamic>?>();
      final service = AppConfigService(
        rowLoader: () => pendingResponse.future,
        requestTimeout: const Duration(milliseconds: 10),
      );

      final config = await service.fetchAppConfig();

      expect(config.maintenanceEnabled, isFalse);
    });

    test('coalesces concurrent requests', () async {
      var loadCount = 0;
      final response = Completer<Map<String, dynamic>?>();
      final service = AppConfigService(
        rowLoader: () {
          loadCount++;
          return response.future;
        },
      );

      final first = service.fetchAppConfig();
      final second = service.fetchAppConfig();
      response.complete(_configRow(maintenanceEnabled: true));

      expect(identical(first, second), isTrue);
      expect((await first).maintenanceEnabled, isTrue);
      expect((await second).maintenanceEnabled, isTrue);
      expect(loadCount, 1);
    });
  });
}
