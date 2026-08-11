import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy exposed tables use least-privilege RLS', () {
    final sql = File(
      'supabase/migrations/20260811000003_harden_legacy_table_rls.sql',
    ).readAsStringSync();

    for (final table in <String>[
      'activation_codes',
      'conversations',
      'messages',
      'usage',
    ]) {
      expect(
        sql,
        contains('alter table public.$table enable row level security;'),
      );
      expect(
        sql,
        contains(
          'revoke all on table public.$table from public, anon, authenticated;',
        ),
      );
    }

    expect(sql, contains('on table public.conversations to authenticated;'));
    expect(
      sql,
      contains('grant select on table public.usage to authenticated;'),
    );
    expect(sql, contains('to authenticated'));
    expect(sql, contains("(select auth.jwt() ->> 'id') = user_id"));
    expect(
      sql,
      isNot(contains('grant select on table public.activation_codes')),
    );
    expect(sql, isNot(contains('grant select on table public.messages')));
  });
}
