import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260811000002_add_user_ban_status.sql',
  ).readAsStringSync();

  test('migration adds ban fields to the real user_profiles table', () {
    expect(
      migration,
      matches(
        RegExp(r'alter\s+table\s+public\.user_profiles', caseSensitive: false),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'is_banned\s+boolean\s+not\s+null\s+default\s+false',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(RegExp(r'ban_reason\s+text', caseSensitive: false)),
    );
    expect(
      migration,
      isNot(matches(RegExp(r'create\s+table\s+.*user', caseSensitive: false))),
    );
  });

  test('client roles cannot write ban fields', () {
    expect(
      migration,
      matches(
        RegExp(
          r'revoke\s+all\s+on\s+table\s+public\.user_profiles\s+from\s+anon',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'revoke\s+insert\s*,\s*update\s*,\s*delete[\s\S]*'
          r'from\s+authenticated',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'grant\s+update\s*\(\s*avatar_url\s*,\s*avatar_path\s*,\s*'
          r'updated_at\s*,\s*name\s*\)[\s\S]*to\s+authenticated',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      isNot(
        matches(
          RegExp(
            r'grant\s+update\s*\([^)]*(is_banned|ban_reason)',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test('RLS limits authenticated reads and updates to the current user', () {
    expect(
      migration,
      matches(
        RegExp(
          r'for\s+select\s+to\s+authenticated[\s\S]*'
          r'auth\.jwt\(\)[\s\S]*=\s*user_id',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'for\s+update\s+to\s+authenticated[\s\S]*'
          r'with\s+check[\s\S]*auth\.jwt\(\)[\s\S]*=\s*user_id',
          caseSensitive: false,
        ),
      ),
    );
  });
}
