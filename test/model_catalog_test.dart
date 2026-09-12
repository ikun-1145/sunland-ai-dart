import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:sunland_ai_app/main.dart';
import 'package:sunland_ai_app/services/model_catalog_service.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';
import 'package:sunland_ai_app/widgets/chat_composer.dart';

Map<String, dynamic> row(
  String id, {
  String provider = 'deepseek',
  bool free = true,
  bool pro = true,
  bool enabled = true,
  int order = 0,
  String? label,
}) => {
  'id': id,
  'provider': provider,
  'display_name': label ?? '远程 $id',
  'model_name': 'api-$id',
  'free_enabled': free,
  'pro_enabled': pro,
  'enabled': enabled,
  'sort_order': order,
};

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
    );
  });
  setUp(() {
    currentUserNotifier.value = null;
  });

  test(
    'catalog sorts remote names and separates free and Pro eligibility',
    () async {
      final service = ModelCatalogService(
        rowLoader: () async => [
          row('paid', free: false, order: 2),
          row('free', pro: false, order: 1),
          row('hidden', enabled: false),
        ],
      );
      final models = await service.fetchModels();
      expect(models.map((m) => m.modelName), ['api-free', 'api-paid']);
      expect(models.first.isAvailableFor(isPro: false), isTrue);
      expect(models.first.isAvailableFor(isPro: true), isFalse);
      expect(models.last.isAvailableFor(isPro: false), isFalse);
      expect(models.last.isAvailableFor(isPro: true), isTrue);
    },
  );
  test('deduplicates pending fetch and allows refresh after timeout', () async {
    var calls = 0;
    final service = ModelCatalogService(
      requestTimeout: const Duration(milliseconds: 1),
      rowLoader: () {
        calls++;
        return calls == 1
            ? Completer<List<Map<String, dynamic>>>().future
            : Future.value([row('retry')]);
      },
    );
    final first = service.fetchModels();
    expect(identical(first, service.fetchModels()), isTrue);
    await expectLater(first, throwsA(isA<TimeoutException>()));
    expect((await service.fetchModels()).single.id, 'retry');
    expect(calls, 2);
  });
  test(
    'invalid provider or eligibility fails instead of inventing fallback',
    () async {
      for (final invalid in [
        row('bad', provider: 'other'),
        {...row('bad'), 'free_enabled': 'true'},
      ]) {
        await expectLater(
          ModelCatalogService(rowLoader: () async => [invalid]).fetchModels(),
          throwsFormatException,
        );
      }
    },
  );
  test('history preserves retired and future model identifiers', () {
    for (final provider in ['deepseek', 'sunland']) {
      final history = Conversation.fromJson({
        'id': '1',
        'provider': provider,
        'model': 'retired-model',
        'history': [],
      });
      expect(Conversation.fromJson(history.toJson()).model, 'retired-model');
    }
    expect(Conversation.fromJson({'id': '1'}).model, 'deepseek-v4-flash');
  });

  Future<void> pumpChat(
    WidgetTester tester,
    ModelCatalogRowLoader loader,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ChatPage(modelCatalogLoader: loader)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openPicker(WidgetTester tester) async {
    tester.widget<ChatComposer>(find.byType(ChatComposer)).onSelectModel();
    await tester.pumpAndSettle();
  }

  testWidgets(
    'picker refreshes remote names, scrolls and checks Pro-specific flags',
    (tester) async {
      var calls = 0;
      await pumpChat(tester, () async {
        calls++;
        return [
          row('free', pro: false, label: '远程模型名称' * 15),
          row('sunland', provider: 'sunland'),
          row('paid', free: false),
          ...List.generate(20, (i) => row('extra-$i', order: i + 1)),
        ];
      });
      final dynamic state = tester.state(find.byType(ChatPage));
      state.setState(() {
        state.isActivated = true;
      });
      await openPicker(tester);
      expect(calls, 2);
      final freeTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('远程模型名称' * 15).last,
          matching: find.byType(ListTile),
        ),
      );
      expect(freeTile.onTap, isNull);
      expect(find.text('远程 sunland'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('远程 extra-19'),
        250,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('远程 extra-19'), findsOneWidget);
    },
  );
  testWidgets(
    'failed catalog blocks send and picker retries without fallback',
    (tester) async {
      var fail = true;
      await pumpChat(tester, () async {
        if (fail) throw Exception('offline');
        return [row('restored')];
      });
      final dynamic state = tester.state(find.byType(ChatPage));
      state.controller.text = '保留我的输入';
      await state.sendMessage();
      await tester.pump();
      expect(state.controller.text, '保留我的输入');
      expect(state.isGenerating, isFalse);
      await openPicker(tester);
      expect(find.text('模型加载失败，点击重试'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('模型加载失败，点击重试'));
      await tester.pumpAndSettle();
      expect(find.text('远程 restored'), findsAtLeastNWidgets(1));
    },
  );
  testWidgets('removed historical model remains readable and cannot send', (
    tester,
  ) async {
    await pumpChat(tester, () async => [row('valid')]);
    final dynamic state = tester.state(find.byType(ChatPage));
    state.setState(() {
      state.currentModel = 'retired';
      state.messages.add({'isUser': true, 'text': '旧消息'});
    });
    state.controller.text = '后续消息';
    await state.sendMessage();
    await tester.pump();
    expect(state.currentModel, 'retired');
    expect(state.controller.text, '后续消息');
    expect(find.text('旧消息'), findsOneWidget);
  });
  testWidgets('generation prevents picker and disposed refresh is safe', (
    tester,
  ) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    await tester.pumpWidget(
      MaterialApp(home: ChatPage(modelCatalogLoader: () => pending.future)),
    );
    final dynamic state = tester.state(find.byType(ChatPage));
    state.setState(() {
      state.isGenerating = true;
    });
    tester.widget<ChatComposer>(find.byType(ChatComposer)).onSelectModel();
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpWidget(const SizedBox());
    pending.complete([row('late')]);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
