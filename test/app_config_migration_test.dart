import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260811000001_create_app_config.sql',
  ).readAsStringSync();

  test('app_config migration permits exactly one global row', () {
    expect(
      migration,
      matches(
        RegExp(r'config_key\s+text\s+primary\s+key', caseSensitive: false),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'check\s*\(\s*config_key\s*=\s*\x27global\x27\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    expect(migration, contains("'global'"));
  });

  test('app_config client roles have select-only access', () {
    expect(
      migration,
      matches(
        RegExp(
          r'alter\s+table\s+public\.app_config\s+enable\s+row\s+level\s+security',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'revoke\s+all\s+on\s+table\s+public\.app_config\s+from\s+'
          r'public\s*,\s*anon\s*,\s*authenticated',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'grant\s+select\s+on\s+table\s+public\.app_config\s+to\s+'
          r'anon\s*,\s*authenticated',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      matches(
        RegExp(
          r'for\s+select\s+to\s+anon\s*,\s*authenticated\s+using\s*'
          r'\(\s*config_key\s*=\s*\x27global\x27\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    expect(
      migration,
      isNot(
        matches(
          RegExp(r'grant\s+(insert|update|delete|all)', caseSensitive: false),
        ),
      ),
    );
  });
}
