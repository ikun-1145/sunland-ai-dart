import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';
import 'package:sunland_ai_app/sunland_beta_diagnostics.dart';

Map<String, dynamic> _observation({
  String resultCategory = 'understood',
  String reasonCategory = 'complete-passive-understanding',
  bool semanticAdopted = true,
  bool legacyFallback = false,
  bool contextUsed = false,
}) {
  return <String, dynamic>{
    'schemaVersion': 1,
    'sunlandCoreVersion': '0.1.0',
    'semanticSchemaVersion': 1,
    'contextSchemaVersion': 1,
    'resultCategory': resultCategory,
    'reasonCategory': reasonCategory,
    'relationCategory': 'none',
    'semanticAdopted': semanticAdopted,
    'legacyFallback': legacyFallback,
    'contextUsed': contextUsed,
    'clarificationKind': 'none',
    'pathLengthBucket': 'none',
    'knowledgeCountBucket': '0',
    'totalDurationBucket': '1-5ms',
    'semanticDurationBucket': 'under-1ms',
    'reasonerDurationBucket': 'unavailable',
    'queriedRelation': 'none',
    'alternativeKnownRelation': 'none',
    'alignmentResult': 'unavailable',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test(
    'diagnostics are off by default without creating a device boundary',
    () async {
      final store = SunlandBetaDiagnosticsStore();

      final capture = await store.capture('user-a');
      final state = await store.load('user-a');
      final prefs = await SharedPreferences.getInstance();

      expect(capture.enabled, isFalse);
      expect(capture.observationMode, 'off');
      expect(state.enabled, isFalse);
      expect(state.hasData, isFalse);
      expect(
        prefs.getString(SunlandBetaDiagnosticsStore.deviceSecretStorageKey),
        isNull,
      );
    },
  );

  test('valid summaries aggregate into isolated per-user snapshots', () async {
    final store = SunlandBetaDiagnosticsStore(
      randomBytes: (length) => List<int>.generate(length, (index) => index),
    );
    await store.setEnabled('user-a', true);
    await store.setEnabled('user-b', true);

    final captureA = await store.capture('user-a');
    final captureB = await store.capture('user-b');
    expect(
      await store.record(
        capture: captureA,
        currentUserId: 'user-a',
        observationSummary: _observation(),
      ),
      isTrue,
    );
    expect(
      await store.record(
        capture: captureB,
        currentUserId: 'user-b',
        observationSummary: _observation(
          resultCategory: 'clarification',
          reasonCategory: 'missing-object',
          semanticAdopted: false,
          legacyFallback: true,
          contextUsed: true,
        ),
      ),
      isTrue,
    );

    final snapshotA = (await store.load('user-a')).snapshot!;
    final snapshotB = (await store.load('user-b')).snapshot!;
    final prefs = await SharedPreferences.getInstance();
    expect(snapshotA.counters['requestCompleted'], 1);
    expect(snapshotA.counters['understood'], 1);
    expect(snapshotA.counters['clarification'], 0);
    expect(snapshotB.counters['understood'], 0);
    expect(snapshotB.counters['clarification'], 1);
    expect(snapshotB.counters['legacyFallback'], 1);
    expect(snapshotB.counters['contextUsed'], 1);
    expect(
      prefs.getKeys().where(
        (key) => key != SunlandBetaDiagnosticsStore.deviceSecretStorageKey,
      ),
      everyElement(isNot(contains('user-a'))),
    );
    expect(
      () => snapshotA.counters['requestCompleted'] = 99,
      throwsUnsupportedError,
    );
  });

  test(
    'invalid or extra-field summaries never change local counters',
    () async {
      final store = SunlandBetaDiagnosticsStore(
        randomBytes: (length) => List<int>.filled(length, 7),
      );
      await store.setEnabled('user-a', true);
      final capture = await store.capture('user-a');

      expect(
        await store.record(
          capture: capture,
          currentUserId: 'user-a',
          observationSummary: <String, dynamic>{
            ..._observation(),
            'rawInput': 'private conversation',
          },
        ),
        isFalse,
      );
      expect(
        await store.record(
          capture: capture,
          currentUserId: 'user-a',
          observationSummary: <String, dynamic>{
            ..._observation(),
            'schemaVersion': 2,
          },
        ),
        isFalse,
      );
      expect((await store.load('user-a')).hasData, isFalse);
    },
  );

  test(
    'turning diagnostics off preserves data and invalidates old captures',
    () async {
      final store = SunlandBetaDiagnosticsStore(
        randomBytes: (length) => List<int>.filled(length, 11),
      );
      await store.setEnabled('user-a', true);
      final capture = await store.capture('user-a');
      expect(
        await store.record(
          capture: capture,
          currentUserId: 'user-a',
          observationSummary: _observation(),
        ),
        isTrue,
      );

      await store.setEnabled('user-a', false);

      final state = await store.load('user-a');
      expect(state.enabled, isFalse);
      expect(state.hasData, isTrue);
      expect(
        await store.record(
          capture: capture,
          currentUserId: 'user-a',
          observationSummary: _observation(),
        ),
        isFalse,
      );
      expect(state.snapshot!.counters['requestCompleted'], 1);
    },
  );

  test(
    'clearing affects one account and stale requests cannot restore data',
    () async {
      final store = SunlandBetaDiagnosticsStore(
        randomBytes: (length) => List<int>.filled(length, 19),
      );
      await store.setEnabled('user-a', true);
      await store.setEnabled('user-b', true);
      final captureA = await store.capture('user-a');
      final captureB = await store.capture('user-b');
      await store.record(
        capture: captureA,
        currentUserId: 'user-a',
        observationSummary: _observation(),
      );
      await store.record(
        capture: captureB,
        currentUserId: 'user-b',
        observationSummary: _observation(),
      );

      await store.clearSnapshot('user-a');

      expect((await store.load('user-a')).hasData, isFalse);
      expect((await store.load('user-a')).enabled, isTrue);
      expect((await store.load('user-b')).hasData, isTrue);
      expect(
        await store.record(
          capture: captureA,
          currentUserId: 'user-a',
          observationSummary: _observation(),
        ),
        isFalse,
      );
      expect((await store.load('user-a')).hasData, isFalse);
    },
  );

  test(
    'late eligibility rejection prevents a completed summary write',
    () async {
      final store = SunlandBetaDiagnosticsStore(
        randomBytes: (length) => List<int>.filled(length, 21),
      );
      await store.setEnabled('user-a', true);
      final capture = await store.capture('user-a');
      var eligibilityChecks = 0;

      expect(
        await store.record(
          capture: capture,
          currentUserId: 'user-a',
          observationSummary: _observation(),
          eligibilityProvider: () {
            eligibilityChecks += 1;
            return eligibilityChecks == 1;
          },
        ),
        isFalse,
      );
      expect((await store.load('user-a')).hasData, isFalse);
    },
  );

  test(
    'corrupt snapshots are discarded and invalidate stale captures',
    () async {
      final store = SunlandBetaDiagnosticsStore(
        randomBytes: (length) => List<int>.filled(length, 22),
      );
      await store.setEnabled('user-a', true);
      final capture = await store.capture('user-a');
      await store.record(
        capture: capture,
        currentUserId: 'user-a',
        observationSummary: _observation(),
      );
      final prefs = await SharedPreferences.getInstance();
      final snapshotKey = prefs.getKeys().singleWhere(
        (key) => key.startsWith('sunland_beta_diag_v1::'),
      );
      await prefs.setString(snapshotKey, '{"unexpected":"private"}');

      final state = await store.load('user-a');

      expect(state.resetCorruptSnapshot, isTrue);
      expect(state.enabled, isTrue);
      expect(state.hasData, isFalse);
      expect(prefs.containsKey(snapshotKey), isFalse);
      expect(
        await store.record(
          capture: capture,
          currentUserId: 'user-a',
          observationSummary: _observation(),
        ),
        isFalse,
      );
    },
  );

  test(
    'normal logout cleanup keeps the account-scoped local snapshot',
    () async {
      final store = SunlandBetaDiagnosticsStore(
        randomBytes: (length) => List<int>.filled(length, 24),
      );
      await store.setEnabled('user-a', true);
      final capture = await store.capture('user-a');
      await store.record(
        capture: capture,
        currentUserId: 'user-a',
        observationSummary: _observation(),
      );

      await SunlandSessionStore().clearAll();

      final state = await store.load('user-a');
      expect(state.enabled, isTrue);
      expect(state.hasData, isTrue);
    },
  );

  test('anonymous export is rebuilt from a strict whitelist', () async {
    final store = SunlandBetaDiagnosticsStore(
      randomBytes: (length) => List<int>.filled(length, 23),
    );
    await store.setEnabled('private-user', true);
    final capture = await store.capture('private-user');
    await store.record(
      capture: capture,
      currentUserId: 'private-user',
      observationSummary: _observation(),
    );

    final json = store.buildExportJson(
      (await store.load('private-user')).snapshot!,
    );
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    expect(decoded.keys, <String>[
      'schema',
      'diagnosticsSchemaVersion',
      'versions',
      'counters',
      'resultCategories',
      'reasonCategories',
      'relationCategories',
      'clarificationKinds',
      'durations',
      'knowledgeSizeBuckets',
      'reasonerPathBuckets',
    ]);
    expect(json, isNot(contains('private-user')));
    expect(json, isNot(contains('conversationId')));
    expect(json, isNot(matches(RegExp(r'"(?:subject|object)"\s*:'))));
    expect(json, isNot(contains('timestamp')));
  });
}
