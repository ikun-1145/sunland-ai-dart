import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

typedef NetworkAvailabilityProbe = Future<bool> Function();

class NetworkConnectivityService {
  NetworkConnectivityService({
    http.Client? client,
    Uri? probeUri,
    NetworkAvailabilityProbe? availabilityProbe,
    Duration requestTimeout = const Duration(seconds: 5),
  }) : _client = client,
       _probeUri = probeUri ?? Uri.parse('https://api.sunland.dev/'),
       _availabilityProbe = availabilityProbe,
       _requestTimeout = requestTimeout;

  final http.Client? _client;
  final Uri _probeUri;
  final NetworkAvailabilityProbe? _availabilityProbe;
  final Duration _requestTimeout;

  Future<bool> hasInternetConnection() async {
    try {
      final availabilityProbe = _availabilityProbe;
      if (availabilityProbe != null) {
        return await availabilityProbe().timeout(_requestTimeout);
      }

      final client = _client ?? http.Client();
      try {
        await client.head(_probeUri).timeout(_requestTimeout);
        return true;
      } finally {
        if (_client == null) client.close();
      }
    } on TimeoutException {
      debugPrint('Network connectivity check timed out.');
      return false;
    } catch (error) {
      debugPrint('Network connectivity check failed: $error');
      return false;
    }
  }
}
