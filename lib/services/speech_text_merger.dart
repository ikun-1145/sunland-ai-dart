/// 语音识别结果写回输入框时的文本拼接规则。
///
/// 设计要点：
/// - 永远不覆盖输入框里已有的内容，识别结果只做追加。
/// - 中日韩（含粤语、韩语）书写不使用词间空格，因此绝不无脑补空格。
/// - 英文等需要分词空格的语种，在两侧都没有空白时才补一个空格。
///
/// 语种判定直接看识别结果自身的字符：辨识 CJK 比信任模型返回的语种标签更
/// 稳妥（同一个标签在混说中英时也可能不准）。
library;

/// 中文/日文标点，追加到已有内容后面时同样不补空格。
const String _cjkPunctuation = '，。！？、；：""''「」『』（）【】《》〈〉…—～·';

/// 判断一个字符是否属于中日韩（CJK）表意文字或假名/谚文。
bool isCjkCharacter(String char) {
  if (char.isEmpty) return false;
  final code = char.runes.first;
  return (code >= 0x4E00 && code <= 0x9FFF) || // CJK 统一表意文字
      (code >= 0x3400 && code <= 0x4DBF) || // 扩展 A
      (code >= 0xF900 && code <= 0xFAFF) || // 兼容表意文字
      (code >= 0x3040 && code <= 0x30FF) || // 平假名 / 片假名
      (code >= 0xAC00 && code <= 0xD7AF) || // 谚文音节
      (code >= 0x3000 && code <= 0x303F) || // CJK 标点
      (code >= 0xFF00 && code <= 0xFFEF); // 全角字符
}

bool _isWhitespace(String char) => char.trim().isEmpty;

/// 把 [recognized] 追加到 [existing] 末尾。
///
/// - [existing] 为空时直接返回识别结果。
/// - [recognized] 为空或全空白时原样返回 [existing]，保证用户已输入的内容不丢。
/// - 两侧任一已有空白（含换行）时不重复补空格。
/// - 识别结果以中文/日文字符或 CJK 标点开头时不补空格；否则补一个空格。
String mergeRecognizedText({
  required String existing,
  required String recognized,
}) {
  final addition = recognized.trim();
  if (addition.isEmpty) return existing;
  if (existing.isEmpty) return addition;

  final lastChar = existing[existing.length - 1];
  final firstChar = addition[0];
  if (_isWhitespace(lastChar) || _isWhitespace(firstChar)) {
    return existing + addition;
  }
  if (isCjkCharacter(firstChar) || _cjkPunctuation.contains(firstChar)) {
    return existing + addition;
  }
  return '$existing $addition';
}
