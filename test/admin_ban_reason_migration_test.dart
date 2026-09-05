import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260905073733_admin_ban_reason.sql',
  ).readAsStringSync();

  test('ban reason RPC validates and stores the supplied reason atomically', () {
    expect(
      migration,
      contains(
        'create or replace function public.sunland_admin_set_user_ban_with_reason',
      ),
    );
    expect(migration, contains('ban_reason = case'));
    expect(migration, contains("raise exception 'BAN_REASON_INVALID'"));
    expect(migration, contains('insert into public.admin_audit_logs'));
  });

  test('ban reason and user detail RPCs remain service-role only', () {
    expect(migration, contains("set search_path = ''"));
    expect(migration, contains('from public, anon, authenticated'));
    expect(migration, contains('to service_role'));
    expect(migration, contains("'banReason', up.ban_reason"));
  });
}
