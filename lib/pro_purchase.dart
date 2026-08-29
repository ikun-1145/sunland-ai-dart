const String proAfdianPlanId = '4c2527fc6c7411f1bbe45254001e7c00';

Uri buildProPurchaseUri(String userId) {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) {
    throw ArgumentError.value(userId, 'userId', 'must not be empty');
  }

  return Uri.https('afdian.com', '/order/create', {
    'product_type': '0',
    'plan_id': proAfdianPlanId,
    'custom_order_id': normalizedUserId,
  });
}
