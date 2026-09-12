import 'package:flutter_test/flutter_test.dart';
import 'package:sunland_ai_app/services/speech_text_merger.dart';

void main() {
  group('mergeRecognizedText', () {
    test('追加到用户已输入的内容末尾而不是覆盖（Test 5）', () {
      expect(
        mergeRecognizedText(existing: '帮我查一下', recognized: '今天东京天气'),
        '帮我查一下今天东京天气',
      );
    });

    test('英文语种在原内容末尾没有空格时补一个空格', () {
      expect(mergeRecognizedText(existing: 'ABC', recognized: 'DEF'), 'ABC DEF');
    });

    test('英文句子追加时不破坏原有内容', () {
      expect(
        mergeRecognizedText(
          existing: 'Summarize this',
          recognized: 'in one sentence.',
        ),
        'Summarize this in one sentence.',
      );
    });

    test('已有尾随空格时不再重复补空格', () {
      expect(
        mergeRecognizedText(existing: 'hello ', recognized: 'world'),
        'hello world',
      );
    });

    test('识别结果自带前导空格时不再重复补空格', () {
      expect(
        mergeRecognizedText(existing: 'hello', recognized: ' world'),
        'hello world',
      );
    });

    test('中文不补空格', () {
      expect(mergeRecognizedText(existing: '帮我', recognized: '看看'), '帮我看看');
    });

    test('日文不补空格', () {
      expect(
        mergeRecognizedText(existing: '東京の', recognized: '天気は'),
        '東京の天気は',
      );
    });

    test('韩文与粤语不补空格', () {
      expect(mergeRecognizedText(existing: '안녕', recognized: '하세요'), '안녕하세요');
      expect(mergeRecognizedText(existing: '唔該', recognized: '晒'), '唔該晒');
    });

    test('识别结果以中文标点开头时不补空格', () {
      expect(mergeRecognizedText(existing: '你好', recognized: '，好久不见'), '你好，好久不见');
    });

    test('识别结果为空或全空白时不动原内容', () {
      expect(mergeRecognizedText(existing: '原有内容', recognized: ''), '原有内容');
      expect(mergeRecognizedText(existing: '原有内容', recognized: '   \n '), '原有内容');
    });

    test('原内容为空时直接使用识别结果', () {
      expect(mergeRecognizedText(existing: '', recognized: ' 你好 '), '你好');
    });

    test('识别结果前后的空白会被裁掉', () {
      expect(
        mergeRecognizedText(existing: '帮我查一下', recognized: '  今天东京天气  '),
        '帮我查一下今天东京天气',
      );
    });

    test('换行结尾不会额外补空格', () {
      expect(
        mergeRecognizedText(existing: '第一行\n', recognized: 'second'),
        '第一行\nsecond',
      );
    });

    test('中英混说时按首个字符决定是否补空格', () {
      expect(
        mergeRecognizedText(existing: '帮我查一下', recognized: 'Tokyo weather'),
        '帮我查一下 Tokyo weather',
      );
    });
  });

  group('isCjkCharacter', () {
    test('识别中日韩字符与标点', () {
      for (final char in ['中', 'あ', 'ア', '한', '，', '。', 'Ａ']) {
        expect(isCjkCharacter(char), isTrue, reason: char);
      }
    });

    test('拉丁字母与数字不算 CJK', () {
      for (final char in ['a', 'Z', '1', ',', '!', ' ']) {
        expect(isCjkCharacter(char), isFalse, reason: char);
      }
    });

    test('空字符串安全返回 false', () {
      expect(isCjkCharacter(''), isFalse);
    });
  });
}
