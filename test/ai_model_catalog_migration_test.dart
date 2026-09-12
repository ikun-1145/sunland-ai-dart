import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260911225219_ai_model_catalog.sql',
  ).readAsStringSync();

  test('AI model catalogue has public read-only access and bounded routes', () {
    expect(migration, contains('create table public.ai_models'));
    expect(migration, contains("provider in ('deepseek', 'sunland')"));
    expect(migration, contains("'deepseek-v4-flash'"));
    expect(migration, contains("'deepseek-v4-pro'"));
    expect(migration, contains("'frost'"));
    expect(migration, contains('alter table public.ai_models enable row level security'));
    expect(migration, contains('grant select on table public.ai_models to anon, authenticated'));
    expect(migration, contains('for select to anon, authenticated using (enabled)'));
  });

  test('AI model admin save is atomic, audited, and uses optimistic locking', () {
    expect(migration, contains('sunland_admin_save_ai_model'));
    expect(migration, contains('pg_advisory_xact_lock'));
    expect(migration, contains("raise exception 'AI_MODEL_CONFLICT'"));
    expect(migration, contains("'ai_model_saved'"));
    expect(migration, contains('grant execute on function public.sunland_admin_save_ai_model'));
  });
}
