import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sunland_ai_app/services/image_attachment_service.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';

void main() {
  test('serializes current user images as DeepSeek content blocks only', () {
    const imageDataUrl = 'data:image/jpeg;base64,/9j/2Q==';
    const message = ChatMessage(
      role: 'user',
      content: '这张图片里有什么？',
      imageDataUrls: [imageDataUrl],
    );

    final apiJson = message.toApiJson();
    final blocks = apiJson['content']! as List<dynamic>;
    expect(blocks.first, {'type': 'text', 'text': '这张图片里有什么？'});
    expect(blocks.last, {
      'type': 'image_url',
      'image_url': {'url': imageDataUrl, 'detail': 'auto'},
    });
    expect(message.toJson().containsKey('imageDataUrls'), isFalse);

    const assistant = ChatMessage(
      role: 'assistant',
      content: '回答',
      imageDataUrls: [imageDataUrl],
    );
    expect(assistant.toApiJson()['content'], '回答');
  });

  test('attaches images only to the latest user turn in API history', () {
    const imageDataUrl = 'data:image/jpeg;base64,/9j/2Q==';
    final history = buildChatHistory(
      rawMessages: [
        {'isUser': true, 'text': '第一问'},
        {'isUser': false, 'text': '第一答'},
        {'isUser': true, 'text': '看看这张图'},
      ],
      maxHistory: 20,
      currentImageDataUrls: const [imageDataUrl],
    );

    final userMessages = history.where((message) => message.isUser).toList();
    expect(userMessages, hasLength(2));
    expect(userMessages.first.hasImages, isFalse);
    expect(userMessages.last.hasImages, isTrue);
    expect(userMessages.last.imageDataUrls, const [imageDataUrl]);
  });

  test(
    'prepares a bounded JPEG data URL from a readable local image',
    () async {
      final tempDirectory = Directory.systemTemp.createTempSync(
        'sunland-vision-images-',
      );
      addTearDown(() => tempDirectory.deleteSync(recursive: true));

      final source = img.Image(width: 8, height: 4);
      final file = File('${tempDirectory.path}/source.png')
        ..writeAsBytesSync(img.encodePng(source));

      final dataUrls = await prepareDeepSeekVisionImages(
        imagePaths: [file.path],
        maxSide: 4,
      );

      expect(dataUrls, hasLength(1));
      expect(dataUrls.single, startsWith('data:image/jpeg;base64,'));
      final encoded = dataUrls.single.split(',').last;
      final decoded = img.decodeImage(base64Decode(encoded));
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(4));
      expect(decoded.height, lessThanOrEqualTo(4));
    },
  );

  test('rejects an image batch above the prepared total size limit', () async {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'sunland-vision-limit-',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));

    final file = File('${tempDirectory.path}/source.png')
      ..writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));

    await expectLater(
      prepareDeepSeekVisionImages(imagePaths: [file.path], maxTotalBytes: 1),
      throwsA(isA<ImagePreparationException>()),
    );
  });
}
