import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Beta 首次入口提供可执行动作、模型说明和可恢复错误', () {
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(mainSource, contains('今天想做点什么？'));
    expect(mainSource, contains('🐾 查找下个月的兽聚'));
    expect(mainSource, contains('✨ 给我一点灵感'));
    expect(mainSource, contains('📄 随便聊聊'));
    expect(mainSource, contains('Sunland AI · Beta'));
    expect(mainSource, contains('云端符号推理，不使用 DeepSeek'));
    expect(mainSource, contains('服务器开小差了，稍后再试试'));
    expect(mainSource, contains('请求超时了，稍后再试一下'));
    expect(mainSource, contains('网络好像断了，检查一下连接'));
    expect(mainSource, contains('请求失败了，试试重新发送'));
  });

  test('生产客户端不再加载本地 Core 或直写受保护账户字段', () {
    final coreSource = File('lib/sunland_ai_core.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(File('lib/sunland_core_client.dart').existsSync(), isFalse);
    expect(File('lib/sunland_local_provider.dart').existsSync(), isFalse);
    expect(
      File('lib/sunland_webview_runtime_adapter.dart').existsSync(),
      isFalse,
    );
    expect(File('assets/sunland-core.js').existsSync(), isFalse);
    expect(File('assets/sunland-core.manifest.json').existsSync(), isFalse);
    expect(pubspec, isNot(contains('assets/sunland-core.js')));
    expect(coreSource, contains('sb_publishable_'));
    expect(coreSource, isNot(contains('supabaseAnonKey')));
    expect(mainSource, contains('publishableKey: supabasePublishableKey'));
    expect(mainSource, isNot(contains('anonKey:')));
    expect(coreSource, isNot(contains("from('activation_codes')")));
    expect(coreSource, isNot(contains("rpc('increment_usage'")));
    expect(coreSource, isNot(contains("from('user_profiles').upsert")));
    expect(coreSource, contains('/v1/activation/claim'));
  });

  test('本地 Beta 诊断只接入真实 Sunland 远端请求', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final settingsSource = File('lib/settings_page.dart').readAsStringSync();

    expect(mainSource, contains('betaDiagnostics.capture(requestUserId)'));
    expect(
      mainSource,
      contains('observationMode: diagnosticsCapture.observationMode'),
    );
    expect(mainSource, contains('betaDiagnostics.record('));
    expect(
      mainSource,
      contains('observationSummary: result.observationSummary'),
    );
    expect(settingsSource, contains('SunlandDataManagementCard('));
    expect(settingsSource, contains('SunlandBetaDiagnosticsCard('));
  });
}
