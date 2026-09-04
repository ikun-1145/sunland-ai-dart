import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260904122722_admin_control_plane.sql',
  ).readAsStringSync();

  test(
    'Admin control plane keeps Pro, announcements and audit schema local and protected',
    () {
      for (final table in [
        'public.pro_activations',
        'public.announcements',
        'public.admin_audit_logs',
      ]) {
        expect(migration, contains('create table if not exists $table'));
        expect(
          migration,
          contains('alter table $table enable row level security'),
        );
        expect(
          migration,
          contains(
            'revoke all on table $table from public, anon, authenticated',
          ),
        );
      }
      expect(
        migration,
        contains('create unique index if not exists pro_activations_order_id_unique'),
      );
      expect(migration, contains('where order_id is not null'));
      expect(migration, contains('sunland_activate_pro_from_payment'));
      expect(migration, contains('sunland_admin_record_failed_action'));
    },
  );

  test(
    'announcement lifecycle is draft-delete-only and public reads are server filtered',
    () {
      expect(
        migration,
        contains("raise exception 'ANNOUNCEMENT_WAS_PUBLISHED'"),
      );
      expect(migration, contains('where a.published_at is not null'));
      expect(migration, contains('and a.is_active = true'));
      expect(
        migration,
        contains('(a.starts_at is null or a.starts_at <= now())'),
      );
      expect(
        migration,
        contains('(a.ends_at is null or a.ends_at > now())'),
      );
    },
  );

  test('retired activation code RPC has no remaining executable public path', () {
    expect(
      migration,
      contains(
        'revoke execute on function public.sunland_claim_activation_code(text, text)',
      ),
    );
    expect(
      migration,
      contains('from public, anon, authenticated, service_role'),
    );
  });
}
