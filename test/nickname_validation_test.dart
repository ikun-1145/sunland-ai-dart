import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/settings_page.dart';

void main() {
  test('昵称只允许最多8个可打印ASCII字符或中文字符', () {
    expect(isValidNickname('Sunland8'), isTrue);
    expect(isValidNickname('太阳'), isTrue);
    expect(isValidNickname('123456789'), isFalse);
    expect(isValidNickname('Sun land'), isFalse);
    expect(isValidNickname('太阳🙂'), isFalse);
    expect(isValidNickname(''), isFalse);
  });
}
