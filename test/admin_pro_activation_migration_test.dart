import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final listMigration = File(
    'supabase/migrations/20260906061736_admin_pro_activation_source_alignment.sql',
  ).readAsStringSync();
  final detailMigration = File(
    'supabase/migrations/20260906062105_admin_pro_detail_stats_alignment.sql',
  ).readAsStringSync();

  test('Admin Pro reads activated payment orders without changing the API envelope', () {
    expect(listMigration, contains('create or replace function public.sunland_admin_pro_stats'));
    expect(listMigration, contains('create or replace function public.sunland_admin_list_pro_activations'));
    expect(listMigration, contains("from public.pro_payment_orders po"));
    expect(listMigration, contains("po.status = 'activated'"));
    expect(listMigration, contains("'source', 'payment'"));
    expect(listMigration, contains("'bindingSource', binding_source"));
    expect(listMigration, contains("'orderId', order_id"));
    expect(detailMigration, contains('create or replace function public.sunland_admin_stats'));
    expect(detailMigration, contains('create or replace function public.sunland_admin_user_detail'));
    expect(detailMigration, contains("from public.pro_payment_orders po"));
    expect(detailMigration, contains("po.status = 'activated'"));
  });
}
