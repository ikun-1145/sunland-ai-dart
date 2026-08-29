import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/pro_purchase.dart';

void main() {
  test('builds the same Afdian order URL used by the web client', () {
    final uri = buildProPurchaseUri('user-123');

    expect(uri.scheme, 'https');
    expect(uri.host, 'afdian.com');
    expect(uri.path, '/order/create');
    expect(uri.queryParameters, {
      'product_type': '0',
      'plan_id': proAfdianPlanId,
      'custom_order_id': 'user-123',
    });
  });

  test('encodes the complete user id as custom_order_id', () {
    final uri = buildProPurchaseUri('user+name@example.com');

    expect(uri.queryParameters['custom_order_id'], 'user+name@example.com');
    expect(
      uri.toString(),
      contains('custom_order_id=user%2Bname%40example.com'),
    );
  });

  test('rejects an empty user id', () {
    expect(() => buildProPurchaseUri('  '), throwsArgumentError);
  });

  test('Flutter Pro UI uses the external order flow only', () {
    final settingsSource = File('lib/settings_page.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(settingsSource, contains('buildProPurchaseUri(user.id)'));
    expect(settingsSource, contains('LaunchMode.externalApplication'));
    expect(settingsSource, isNot(contains('输入激活码')));
    expect(settingsSource, isNot(contains('_PaymentQr')));
    expect(mainSource, isNot(contains('openActivation')));
    expect(mainSource, isNot(contains('输入激活码')));
    expect(pubspec, isNot(contains('assets/ten_wx.webp')));
    expect(pubspec, isNot(contains('assets/ten_zfb.webp')));
  });
}
