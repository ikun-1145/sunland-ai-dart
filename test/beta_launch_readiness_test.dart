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
    expect(mainSource, contains('本地符号推理，不使用 DeepSeek'));
    expect(mainSource, contains('服务器开小差了，稍后再试试'));
    expect(mainSource, contains('请求超时了，稍后再试一下'));
    expect(mainSource, contains('网络好像断了，检查一下连接'));
    expect(mainSource, contains('请求失败了，试试重新发送'));
  });
}
