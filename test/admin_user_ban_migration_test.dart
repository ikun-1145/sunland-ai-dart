import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260905063737_admin_user_ban_action.sql',
  ).readAsStringSync();

  test('ban RPC changes the existing profile and records the successful action', () {
    expect(
      migration,
      contains('create or replace function public.sunland_admin_set_user_ban'),
    );
    expect(migration, contains('update public.user_profiles'));
    expect(migration, contains('is_banned = p_is_banned'));
    expect(migration, contains('insert into public.admin_audit_logs'));
    expect(migration, contains("'user_banned'"));
    expect(migration, contains("'user_unbanned'"));
  });

  test('ban RPC is security-definer and unavailable to client database roles', () {
    expect(migration, contains('security definer'));
    expect(migration, contains("set search_path = ''"));
    expect(
      migration,
      contains('revoke execute on function public.sunland_admin_set_user_ban'),
    );
    expect(migration, contains('from public, anon, authenticated'));
    expect(migration, contains('grant execute on function public.sunland_admin_set_user_ban'));
    expect(migration, contains('to service_role'));
  });
}
