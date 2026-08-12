import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sunland_ai_app/services/network_connectivity_service.dart';

void main() {
  test(
    'treats any HTTP response as an available internet connection',
    () async {
      final service = NetworkConnectivityService(
        client: MockClient((request) async {
          expect(request.method, 'HEAD');
          expect(request.url, Uri.parse('https://api.sunland.dev/'));
          return http.Response('', 405);
        }),
      );

      expect(await service.hasInternetConnection(), isTrue);
    },
  );

  test('returns false for a transport failure', () async {
    final service = NetworkConnectivityService(
      client: MockClient((_) async => throw http.ClientException('离线')),
    );

    expect(await service.hasInternetConnection(), isFalse);
  });

  test('returns false when the probe times out', () async {
    final response = Completer<http.Response>();
    final service = NetworkConnectivityService(
      client: MockClient((_) => response.future),
      requestTimeout: const Duration(milliseconds: 10),
    );

    expect(await service.hasInternetConnection(), isFalse);
  });
}
