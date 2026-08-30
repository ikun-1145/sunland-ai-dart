import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sunland_ai_app/sunland_beta_diagnostics.dart';
import 'package:sunland_ai_app/sunland_remote_provider.dart';
import 'package:sunland_ai_app/widgets/sunland_settings_sections.dart';

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

Map<String, dynamic> _observation() {
  return <String, dynamic>{
    'schemaVersion': 1,
    'sunlandCoreVersion': '0.1.0',
    'semanticSchemaVersion': 1,
    'contextSchemaVersion': 1,
    'resultCategory': 'understood',
    'reasonCategory': 'complete-passive-understanding',
    'relationCategory': 'none',
    'semanticAdopted': true,
    'legacyFallback': false,
    'contextUsed': false,
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

  testWidgets('data management loads records and confirms one-record delete', (
    tester,
  ) async {
    var deleteCount = 0;
    final records = <SunlandKnowledgeRecord>[
      const SunlandKnowledgeRecord(
        id: 'record-a',
        subject: '小蓝',
        relation: '喜欢',
        object: '猫',
        negated: false,
      ),
    ];

    await tester.pumpWidget(
      _app(
        SunlandDataManagementCard(
          userId: 'user-a',
          currentUserIdProvider: () => 'user-a',
          loadKnowledge: () async => List<SunlandKnowledgeRecord>.from(records),
          deleteKnowledge: (id) async {
            deleteCount += 1;
            records.removeWhere((record) => record.id == id);
          },
          deleteAllKnowledge: () async => records.clear(),
          deleteRememberedName: () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('姓名记忆'), findsOneWidget);
    expect(find.text('用户教学知识'), findsOneWidget);
    expect(find.text('小蓝 喜欢 猫'), findsOneWidget);
    expect(find.text('共 1 条'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '删除'));
    await tester.pumpAndSettle();
    expect(find.text('确定删除“小蓝 喜欢 猫”吗？删除后无法恢复。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(deleteCount, 1);
    expect(find.text('暂无用户教学知识'), findsOneWidget);
    expect(find.text('这条教学知识已删除。'), findsOneWidget);
  });

  testWidgets(
    'diagnostics start collapsed and require consent before enabling',
    (tester) async {
      final store = SunlandBetaDiagnosticsStore(
        randomBytes: (length) => List<int>.filled(length, 29),
      );

      await tester.pumpWidget(
        _app(
          SunlandBetaDiagnosticsCard(
            userId: 'user-a',
            currentUserIdProvider: () => 'user-a',
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Beta 诊断（仅本地）'), findsOneWidget);
      expect(find.text('参与本地 Beta 诊断'), findsNothing);
      expect((await store.capture('user-a')).enabled, isFalse);

      await tester.tap(find.text('Beta 诊断（仅本地）'));
      await tester.pumpAndSettle();
      expect(find.text('参与本地 Beta 诊断'), findsOneWidget);
      expect(find.text('暂无本地诊断数据'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(
        find.text('开启后，只会在此设备保存匿名聚合数据，不会自动上传。确定参与本地 Beta 诊断吗？'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, '开启'));
      await tester.pumpAndSettle();

      expect((await store.capture('user-a')).enabled, isTrue);
      expect(find.text('已开启 · 仅本地'), findsOneWidget);
      expect(find.text('已开启本地 Beta 诊断。当前不会自动上传任何数据。'), findsOneWidget);
    },
  );

  testWidgets('diagnostics preview shows the complete anonymous export', (
    tester,
  ) async {
    final store = SunlandBetaDiagnosticsStore(
      randomBytes: (length) => List<int>.filled(length, 31),
    );
    await store.setEnabled('user-a', true);
    final capture = await store.capture('user-a');
    await store.record(
      capture: capture,
      currentUserId: 'user-a',
      observationSummary: _observation(),
    );
    await tester.pumpWidget(
      _app(
        SunlandBetaDiagnosticsCard(
          userId: 'user-a',
          currentUserIdProvider: () => 'user-a',
          store: store,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beta 诊断（仅本地）'));
    await tester.pumpAndSettle();
    final previewButton = find.widgetWithText(OutlinedButton, '查看导出内容');
    await tester.ensureVisible(previewButton);
    await tester.tap(previewButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('匿名诊断导出预览'), findsOneWidget);
    expect(
      find.textContaining('sunland-beta-diagnostics-export'),
      findsOneWidget,
    );
    expect(find.textContaining('user-a'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.widgetWithText(FilledButton, '关闭预览'));
    await tester.pump(const Duration(milliseconds: 400));
  });
}
