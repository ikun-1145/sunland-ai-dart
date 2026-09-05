import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260905080929_fix_admin_write_rpcs.sql',
  ).readAsStringSync();

  test('maintenance RPC targets the real app_config primary key', () {
    expect(migration, contains('where config_key = \'global\''));
    expect(migration, isNot(contains("where id = 'global'")));
    expect(migration, contains('insert into public.admin_audit_logs'));
  });

  test('replacement RPC remains restricted to service_role', () {
    expect(migration, contains("set search_path = ''"));
    expect(migration, contains('from public, anon, authenticated'));
    expect(migration, contains('to service_role'));
  });
}
