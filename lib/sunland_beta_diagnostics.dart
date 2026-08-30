import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int _diagnosticsSchemaVersion = 1;
const int _maximumDiagnosticCount = 1000000000;
const int _maximumSnapshotBytes = 16 * 1024;

const Map<String, Object> _supportedVersions = <String, Object>{
  'sunlandCoreVersion': '0.1.0',
  'semanticSchemaVersion': 1,
  'contextSchemaVersion': 1,
  'observationSchemaVersion': 1,
};

const List<String> _counterKeys = <String>[
  'requestCompleted',
  'understood',
  'clarification',
  'noUnderstanding',
  'missingKnowledge',
  'relationUnsupported',
  'contextUnresolved',
  'sideEffectBlocked',
  'legacyFallback',
  'safeFallback',
  'semanticAdopted',
  'contextUsed',
];

const List<String> _resultCategories = <String>[
  'understood',
  'clarification',
  'no-understanding',
  'missing-knowledge',
  'relation-unsupported',
  'context-unresolved',
  'side-effect-blocked',
  'safe-fallback',
];

const List<String> _reasonCategories = <String>[
  'complete-passive-understanding',
  'missing-subject',
  'missing-relation',
  'missing-object',
  'ambiguous-intent',
  'conflicting-candidates',
  'insufficient-evidence',
  'missing-knowledge',
  'unsupported-relation',
  'unresolved-context',
  'blocked-side-effect',
  'semantic-runtime',
  'reasoner-error',
  'unknown-safe-fallback',
  'unclassified',
];

const List<String> _relationCategories = <String>[
  '属于',
  '是',
  '会',
  '喜欢',
  '在',
  '有',
  '意思是',
  '开发者',
  'none',
  'unknown',
];

const List<String> _clarificationKinds = <String>[
  'ambiguous-intent',
  'missing-subject',
  'missing-relation',
  'missing-object',
  'uncertain-name',
  'uncertain-teaching',
  'conflicting-candidates',
  'none',
];

const List<String> _durationBuckets = <String>[
  'under-1ms',
  '1-5ms',
  '5-16ms',
  '16-50ms',
  'over-50ms',
  'unavailable',
];

const List<String> _knowledgeSizeBuckets = <String>[
  '0',
  '1-99',
  '100-999',
  '1000-4999',
  '5000-plus',
  'unavailable',
];

const List<String> _reasonerPathBuckets = <String>[
  'direct',
  '2-5',
  '6-20',
  '21-50',
  '51-plus',
  'none',
  'unavailable',
];

const List<String> _alignmentResults = <String>[
  'aligned',
  'possible-mismatch',
  'no-alternative-known',
  'unavailable',
];

const List<String> _observationKeys = <String>[
  'schemaVersion',
  'sunlandCoreVersion',
  'semanticSchemaVersion',
  'contextSchemaVersion',
  'resultCategory',
  'reasonCategory',
  'relationCategory',
  'semanticAdopted',
  'legacyFallback',
  'contextUsed',
  'clarificationKind',
  'pathLengthBucket',
  'knowledgeCountBucket',
  'totalDurationBucket',
  'semanticDurationBucket',
  'reasonerDurationBucket',
  'queriedRelation',
  'alternativeKnownRelation',
  'alignmentResult',
];

const List<String> _snapshotKeys = <String>[
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
];

const Map<String, String> _resultCounters = <String, String>{
  'understood': 'understood',
  'clarification': 'clarification',
  'no-understanding': 'noUnderstanding',
  'missing-knowledge': 'missingKnowledge',
  'relation-unsupported': 'relationUnsupported',
  'context-unresolved': 'contextUnresolved',
  'side-effect-blocked': 'sideEffectBlocked',
  'safe-fallback': 'safeFallback',
};

typedef PreferencesProvider = Future<SharedPreferences> Function();
typedef DiagnosticRandomBytes = List<int> Function(int length);

final SunlandBetaDiagnosticsStore sharedSunlandBetaDiagnosticsStore =
    SunlandBetaDiagnosticsStore();

class SunlandBetaDiagnosticsCapture {
  const SunlandBetaDiagnosticsCapture({
    required this.userId,
    required this.enabled,
    required this.revision,
  });

  final String userId;
  final bool enabled;
  final int revision;

  String get observationMode => enabled ? 'summary' : 'off';
}

class SunlandBetaDiagnosticsState {
  const SunlandBetaDiagnosticsState({
    required this.enabled,
    required this.snapshot,
    required this.snapshotLoaded,
    required this.storedSnapshotExists,
    this.resetCorruptSnapshot = false,
  });

  final bool enabled;
  final SunlandBetaDiagnosticsSnapshot? snapshot;
  final bool snapshotLoaded;
  final bool storedSnapshotExists;
  final bool resetCorruptSnapshot;

  bool get hasData => (snapshot?.counters['requestCompleted'] ?? 0) > 0;
}

class SunlandBetaDiagnosticsSnapshot {
  SunlandBetaDiagnosticsSnapshot._({
    required Map<String, int> counters,
    required Map<String, int> resultCategories,
    required Map<String, int> reasonCategories,
    required Map<String, int> relationCategories,
    required Map<String, int> clarificationKinds,
    required Map<String, Map<String, int>> durations,
    required Map<String, int> knowledgeSizeBuckets,
    required Map<String, int> reasonerPathBuckets,
  }) : _counterValues = Map<String, int>.from(counters),
       _resultCategoryValues = Map<String, int>.from(resultCategories),
       _reasonCategoryValues = Map<String, int>.from(reasonCategories),
       _relationCategoryValues = Map<String, int>.from(relationCategories),
       _clarificationKindValues = Map<String, int>.from(clarificationKinds),
       _durationValues = <String, Map<String, int>>{
         for (final entry in durations.entries)
           entry.key: Map<String, int>.from(entry.value),
       },
       _knowledgeSizeBucketValues = Map<String, int>.from(knowledgeSizeBuckets),
       _reasonerPathBucketValues = Map<String, int>.from(reasonerPathBuckets);

  factory SunlandBetaDiagnosticsSnapshot.empty() {
    return SunlandBetaDiagnosticsSnapshot._(
      counters: _zeroes(_counterKeys),
      resultCategories: _zeroes(_resultCategories),
      reasonCategories: _zeroes(_reasonCategories),
      relationCategories: _zeroes(_relationCategories),
      clarificationKinds: _zeroes(_clarificationKinds),
      durations: <String, Map<String, int>>{
        'total': _zeroes(_durationBuckets),
        'semantic': _zeroes(_durationBuckets),
        'reasoner': _zeroes(_durationBuckets),
      },
      knowledgeSizeBuckets: _zeroes(_knowledgeSizeBuckets),
      reasonerPathBuckets: _zeroes(_reasonerPathBuckets),
    );
  }

  final Map<String, int> _counterValues;
  final Map<String, int> _resultCategoryValues;
  final Map<String, int> _reasonCategoryValues;
  final Map<String, int> _relationCategoryValues;
  final Map<String, int> _clarificationKindValues;
  final Map<String, Map<String, int>> _durationValues;
  final Map<String, int> _knowledgeSizeBucketValues;
  final Map<String, int> _reasonerPathBucketValues;

  Map<String, int> get counters =>
      Map<String, int>.unmodifiable(_counterValues);
  Map<String, int> get resultCategories =>
      Map<String, int>.unmodifiable(_resultCategoryValues);
  Map<String, int> get reasonCategories =>
      Map<String, int>.unmodifiable(_reasonCategoryValues);
  Map<String, int> get relationCategories =>
      Map<String, int>.unmodifiable(_relationCategoryValues);
  Map<String, int> get clarificationKinds =>
      Map<String, int>.unmodifiable(_clarificationKindValues);
  Map<String, Map<String, int>> get durations =>
      Map<String, Map<String, int>>.unmodifiable(<String, Map<String, int>>{
        for (final entry in _durationValues.entries)
          entry.key: Map<String, int>.unmodifiable(entry.value),
      });
  Map<String, int> get knowledgeSizeBuckets =>
      Map<String, int>.unmodifiable(_knowledgeSizeBucketValues);
  Map<String, int> get reasonerPathBuckets =>
      Map<String, int>.unmodifiable(_reasonerPathBucketValues);

  static SunlandBetaDiagnosticsSnapshot? fromJson(Object? value) {
    if (value is! Map || !_hasExactKeys(value, _snapshotKeys)) return null;
    if (value['schema'] != 'sunland-beta-diagnostics' ||
        value['diagnosticsSchemaVersion'] != _diagnosticsSchemaVersion ||
        !_matchesVersions(value['versions'])) {
      return null;
    }
    final counters = _readCounts(value['counters'], _counterKeys);
    final results = _readCounts(value['resultCategories'], _resultCategories);
    final reasons = _readCounts(value['reasonCategories'], _reasonCategories);
    final relations = _readCounts(
      value['relationCategories'],
      _relationCategories,
    );
    final clarifications = _readCounts(
      value['clarificationKinds'],
      _clarificationKinds,
    );
    final knowledge = _readCounts(
      value['knowledgeSizeBuckets'],
      _knowledgeSizeBuckets,
    );
    final paths = _readCounts(
      value['reasonerPathBuckets'],
      _reasonerPathBuckets,
    );
    final rawDurations = value['durations'];
    if (counters == null ||
        results == null ||
        reasons == null ||
        relations == null ||
        clarifications == null ||
        knowledge == null ||
        paths == null ||
        rawDurations is! Map ||
        !_hasExactKeys(rawDurations, const <String>[
          'total',
          'semantic',
          'reasoner',
        ])) {
      return null;
    }
    final total = _readCounts(rawDurations['total'], _durationBuckets);
    final semantic = _readCounts(rawDurations['semantic'], _durationBuckets);
    final reasoner = _readCounts(rawDurations['reasoner'], _durationBuckets);
    if (total == null || semantic == null || reasoner == null) return null;

    return SunlandBetaDiagnosticsSnapshot._(
      counters: counters,
      resultCategories: results,
      reasonCategories: reasons,
      relationCategories: relations,
      clarificationKinds: clarifications,
      durations: <String, Map<String, int>>{
        'total': total,
        'semantic': semantic,
        'reasoner': reasoner,
      },
      knowledgeSizeBuckets: knowledge,
      reasonerPathBuckets: paths,
    );
  }

  SunlandBetaDiagnosticsSnapshot copy() {
    return SunlandBetaDiagnosticsSnapshot.fromJson(toJson())!;
  }

  Map<String, dynamic> toJson({String? schema}) {
    return <String, dynamic>{
      'schema': schema ?? 'sunland-beta-diagnostics',
      'diagnosticsSchemaVersion': _diagnosticsSchemaVersion,
      'versions': Map<String, Object>.from(_supportedVersions),
      'counters': Map<String, int>.from(_counterValues),
      'resultCategories': Map<String, int>.from(_resultCategoryValues),
      'reasonCategories': Map<String, int>.from(_reasonCategoryValues),
      'relationCategories': Map<String, int>.from(_relationCategoryValues),
      'clarificationKinds': Map<String, int>.from(_clarificationKindValues),
      'durations': <String, Map<String, int>>{
        'total': Map<String, int>.from(_durationValues['total']!),
        'semantic': Map<String, int>.from(_durationValues['semantic']!),
        'reasoner': Map<String, int>.from(_durationValues['reasoner']!),
      },
      'knowledgeSizeBuckets': Map<String, int>.from(_knowledgeSizeBucketValues),
      'reasonerPathBuckets': Map<String, int>.from(_reasonerPathBucketValues),
    };
  }
}

class _ObservationSummary {
  const _ObservationSummary(this.value);

  final Map<String, dynamic> value;

  static _ObservationSummary? parse(Map<String, dynamic>? value) {
    if (value == null || !_hasExactKeys(value, _observationKeys)) return null;
    if (value['schemaVersion'] != 1 ||
        value['sunlandCoreVersion'] != '0.1.0' ||
        value['semanticSchemaVersion'] != 1 ||
        value['contextSchemaVersion'] != 1 ||
        !_resultCategories.contains(value['resultCategory']) ||
        !_reasonCategories.contains(value['reasonCategory']) ||
        !_relationCategories.contains(value['relationCategory']) ||
        value['semanticAdopted'] is! bool ||
        value['legacyFallback'] is! bool ||
        value['contextUsed'] is! bool ||
        !_clarificationKinds.contains(value['clarificationKind']) ||
        !_reasonerPathBuckets.contains(value['pathLengthBucket']) ||
        !_knowledgeSizeBuckets.contains(value['knowledgeCountBucket']) ||
        !_durationBuckets.contains(value['totalDurationBucket']) ||
        !_durationBuckets.contains(value['semanticDurationBucket']) ||
        !_durationBuckets.contains(value['reasonerDurationBucket']) ||
        !_relationCategories.contains(value['queriedRelation']) ||
        !_relationCategories.contains(value['alternativeKnownRelation']) ||
        !_alignmentResults.contains(value['alignmentResult'])) {
      return null;
    }
    return _ObservationSummary(Map<String, dynamic>.from(value));
  }
}

class SunlandBetaDiagnosticsStore {
  SunlandBetaDiagnosticsStore({
    PreferencesProvider? preferencesProvider,
    DiagnosticRandomBytes? randomBytes,
  }) : _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance,
       _randomBytes = randomBytes ?? _secureRandomBytes;

  static const String deviceSecretStorageKey =
      'sunland_beta_diag_device_secret_v1';
  static const String _snapshotKeyPrefix = 'sunland_beta_diag_v1::';
  static const String _modeKeyPrefix = 'sunland_beta_diag_mode_v1::';
  static const String _revisionKeyPrefix = 'sunland_beta_diag_revision_v1::';
  static final RegExp _validDeviceSecret = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _validUserId = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9@._+\-]{0,127}$',
  );
  Future<void> _operationChain = Future<void>.value();

  final PreferencesProvider _preferencesProvider;
  final DiagnosticRandomBytes _randomBytes;

  Future<SunlandBetaDiagnosticsCapture> capture(String userId) {
    return _serialized(() async {
      _requireUserId(userId);
      final prefs = await _preferencesProvider();
      final namespace = await _namespace(prefs, userId, create: false);
      if (namespace == null) {
        return SunlandBetaDiagnosticsCapture(
          userId: userId,
          enabled: false,
          revision: 0,
        );
      }
      return SunlandBetaDiagnosticsCapture(
        userId: userId,
        enabled: prefs.getString('$_modeKeyPrefix$namespace') == 'local',
        revision: _readRevision(prefs, namespace),
      );
    });
  }

  Future<SunlandBetaDiagnosticsState> load(
    String userId, {
    bool includeSnapshot = true,
  }) {
    return _serialized(() async {
      _requireUserId(userId);
      final prefs = await _preferencesProvider();
      final namespace = await _namespace(prefs, userId, create: false);
      if (namespace == null) {
        return SunlandBetaDiagnosticsState(
          enabled: false,
          snapshot: null,
          snapshotLoaded: includeSnapshot,
          storedSnapshotExists: false,
        );
      }
      final enabled = prefs.getString('$_modeKeyPrefix$namespace') == 'local';
      if (!includeSnapshot && !enabled) {
        return const SunlandBetaDiagnosticsState(
          enabled: false,
          snapshot: null,
          snapshotLoaded: false,
          storedSnapshotExists: false,
        );
      }
      final loaded = await _loadSnapshot(prefs, namespace);
      return SunlandBetaDiagnosticsState(
        enabled: enabled,
        snapshot: loaded.snapshot,
        snapshotLoaded: true,
        storedSnapshotExists: loaded.snapshot != null,
        resetCorruptSnapshot: loaded.reset,
      );
    });
  }

  Future<void> setEnabled(String userId, bool enabled) {
    return _serialized(() async {
      _requireUserId(userId);
      final prefs = await _preferencesProvider();
      final namespace = await _namespace(prefs, userId, create: enabled);
      if (namespace == null) return;
      await _incrementRevision(prefs, namespace);
      if (enabled) {
        await _setString(prefs, '$_modeKeyPrefix$namespace', 'local');
      } else {
        await _remove(prefs, '$_modeKeyPrefix$namespace');
      }
    });
  }

  Future<void> clearSnapshot(String userId) {
    return _serialized(() async {
      _requireUserId(userId);
      final prefs = await _preferencesProvider();
      final namespace = await _namespace(prefs, userId, create: false);
      if (namespace == null) return;
      await _incrementRevision(prefs, namespace);
      await _remove(prefs, '$_snapshotKeyPrefix$namespace');
    });
  }

  Future<bool> record({
    required SunlandBetaDiagnosticsCapture capture,
    required String? currentUserId,
    required Map<String, dynamic>? observationSummary,
    bool requestEligible = true,
    bool Function()? eligibilityProvider,
  }) async {
    if (!capture.enabled) return false;
    return _serialized(() async {
      if (!requestEligible ||
          currentUserId != capture.userId ||
          eligibilityProvider?.call() == false) {
        return false;
      }
      final summary = _ObservationSummary.parse(observationSummary);
      if (summary == null) return false;
      final prefs = await _preferencesProvider();
      final namespace = await _namespace(prefs, capture.userId, create: false);
      if (namespace == null ||
          prefs.getString('$_modeKeyPrefix$namespace') != 'local' ||
          _readRevision(prefs, namespace) != capture.revision) {
        return false;
      }
      final loaded = await _loadSnapshot(prefs, namespace);
      if (loaded.reset || _readRevision(prefs, namespace) != capture.revision) {
        return false;
      }
      final snapshot =
          (loaded.snapshot ?? SunlandBetaDiagnosticsSnapshot.empty()).copy();
      _aggregate(snapshot, summary.value);
      final serialized = jsonEncode(snapshot.toJson());
      if (utf8.encode(serialized).length > _maximumSnapshotBytes ||
          eligibilityProvider?.call() == false) {
        return false;
      }
      await _setString(prefs, '$_snapshotKeyPrefix$namespace', serialized);
      return true;
    });
  }

  String buildExportJson(SunlandBetaDiagnosticsSnapshot snapshot) {
    final export = snapshot.toJson(schema: 'sunland-beta-diagnostics-export');
    return const JsonEncoder.withIndent('  ').convert(export);
  }

  Future<_LoadedSnapshot> _loadSnapshot(
    SharedPreferences prefs,
    String namespace,
  ) async {
    final key = '$_snapshotKeyPrefix$namespace';
    final serialized = prefs.getString(key);
    if (serialized == null) return const _LoadedSnapshot(null, false);
    try {
      if (utf8.encode(serialized).length > _maximumSnapshotBytes) {
        throw const FormatException('snapshot too large');
      }
      final snapshot = SunlandBetaDiagnosticsSnapshot.fromJson(
        jsonDecode(serialized),
      );
      if (snapshot == null) throw const FormatException('invalid snapshot');
      return _LoadedSnapshot(snapshot, false);
    } catch (_) {
      await _incrementRevision(prefs, namespace);
      await _remove(prefs, key);
      return const _LoadedSnapshot(null, true);
    }
  }

  Future<String?> _namespace(
    SharedPreferences prefs,
    String userId, {
    required bool create,
  }) async {
    var secret = prefs.getString(deviceSecretStorageKey);
    if (secret == null && create) {
      final bytes = _randomBytes(32);
      if (bytes.length != 32 ||
          bytes.any((value) => value < 0 || value > 255)) {
        throw StateError('Unable to create diagnostics storage boundary');
      }
      secret = bytes
          .map((value) => value.toRadixString(16).padLeft(2, '0'))
          .join();
      await _setString(prefs, deviceSecretStorageKey, secret);
    }
    if (secret == null) return null;
    if (!_validDeviceSecret.hasMatch(secret)) {
      throw StateError('Invalid diagnostics storage boundary');
    }
    final keyBytes = <int>[
      for (var index = 0; index < secret.length; index += 2)
        int.parse(secret.substring(index, index + 2), radix: 16),
    ];
    return Hmac(sha256, keyBytes).convert(utf8.encode(userId)).toString();
  }

  int _readRevision(SharedPreferences prefs, String namespace) {
    final value = prefs.getInt('$_revisionKeyPrefix$namespace') ?? 0;
    return value >= 0 ? value : 0;
  }

  Future<void> _incrementRevision(
    SharedPreferences prefs,
    String namespace,
  ) async {
    final current = _readRevision(prefs, namespace);
    final next = current >= 0x1fffffffffffff ? 1 : current + 1;
    if (!await prefs.setInt('$_revisionKeyPrefix$namespace', next)) {
      throw StateError('Unable to update diagnostics revision');
    }
  }

  Future<void> _setString(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    if (!await prefs.setString(key, value)) {
      throw StateError('Unable to save local diagnostics data');
    }
  }

  Future<void> _remove(SharedPreferences prefs, String key) async {
    if (prefs.containsKey(key) && !await prefs.remove(key)) {
      throw StateError('Unable to clear local diagnostics data');
    }
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _operationChain = _operationChain.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static void _requireUserId(String userId) {
    if (!_validUserId.hasMatch(userId)) {
      throw ArgumentError.value(userId, 'userId', 'Invalid user identity');
    }
  }
}

class _LoadedSnapshot {
  const _LoadedSnapshot(this.snapshot, this.reset);

  final SunlandBetaDiagnosticsSnapshot? snapshot;
  final bool reset;
}

Map<String, int> _zeroes(List<String> keys) {
  return <String, int>{for (final key in keys) key: 0};
}

bool _hasExactKeys(Map value, List<String> expected) {
  if (value.length != expected.length) return false;
  return value.keys.every((key) => key is String && expected.contains(key)) &&
      expected.every(value.containsKey);
}

bool _matchesVersions(Object? value) {
  if (value is! Map ||
      !_hasExactKeys(value, _supportedVersions.keys.toList())) {
    return false;
  }
  return _supportedVersions.entries.every(
    (entry) => value[entry.key] == entry.value,
  );
}

Map<String, int>? _readCounts(Object? value, List<String> keys) {
  if (value is! Map || !_hasExactKeys(value, keys)) return null;
  final result = <String, int>{};
  for (final key in keys) {
    final count = value[key];
    if (count is! int || count < 0 || count > _maximumDiagnosticCount) {
      return null;
    }
    result[key] = count;
  }
  return result;
}

void _increment(Map<String, int> target, String key) {
  final current = target[key] ?? 0;
  target[key] = min(_maximumDiagnosticCount, current + 1);
}

void _aggregate(
  SunlandBetaDiagnosticsSnapshot snapshot,
  Map<String, dynamic> summary,
) {
  _increment(snapshot._counterValues, 'requestCompleted');
  final resultCategory = summary['resultCategory'] as String;
  _increment(snapshot._counterValues, _resultCounters[resultCategory]!);
  if (summary['legacyFallback'] == true) {
    _increment(snapshot._counterValues, 'legacyFallback');
  }
  if (summary['semanticAdopted'] == true) {
    _increment(snapshot._counterValues, 'semanticAdopted');
  }
  if (summary['contextUsed'] == true) {
    _increment(snapshot._counterValues, 'contextUsed');
  }
  _increment(snapshot._resultCategoryValues, resultCategory);
  _increment(
    snapshot._reasonCategoryValues,
    summary['reasonCategory'] as String,
  );
  _increment(
    snapshot._relationCategoryValues,
    summary['relationCategory'] as String,
  );
  _increment(
    snapshot._clarificationKindValues,
    summary['clarificationKind'] as String,
  );
  _increment(
    snapshot._durationValues['total']!,
    summary['totalDurationBucket'] as String,
  );
  _increment(
    snapshot._durationValues['semantic']!,
    summary['semanticDurationBucket'] as String,
  );
  _increment(
    snapshot._durationValues['reasoner']!,
    summary['reasonerDurationBucket'] as String,
  );
  _increment(
    snapshot._knowledgeSizeBucketValues,
    summary['knowledgeCountBucket'] as String,
  );
  _increment(
    snapshot._reasonerPathBucketValues,
    summary['pathLengthBucket'] as String,
  );
}

List<int> _secureRandomBytes(int length) {
  final random = Random.secure();
  return List<int>.generate(length, (_) => random.nextInt(256));
}
