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
    expect(uri.toString(), contains('custom_order_id=user%2Bname%40example.com'));
  });

  test('rejects an empty user id', () {
    expect(() => buildProPurchaseUri('  '), throwsArgumentError);
  });
}
