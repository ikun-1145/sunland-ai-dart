import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sunland_ai_app/captcha_page.dart';
import 'package:sunland_ai_app/sunland_ai_core.dart';

void main() {
  test('accepts a complete GeeTest result without changing its contents', () {
    final token = jsonEncode(<String, String>{
      'lot_number': 'lot-1',
      'captcha_output': 'output+with/symbols=',
      'pass_token': 'pass-1',
      'gen_time': '1787961600',
    });

    expect(validateCaptchaResult(token), token);
  });

  test('rejects malformed or incomplete GeeTest results', () {
    expect(validateCaptchaResult('not-json'), isNull);
    expect(
      validateCaptchaResult(
        jsonEncode(<String, String>{
          'lot_number': 'lot-1',
          'captcha_output': 'output-1',
          'pass_token': 'pass-1',
        }),
      ),
      isNull,
    );
    expect(
      validateCaptchaResult(
        jsonEncode(<String, String>{
          'lot_number': 'lot-1',
          'captcha_output': '',
          'pass_token': 'pass-1',
          'gen_time': '1787961600',
        }),
      ),
      isNull,
    );
  });

  test('WebView uses the JavaScript channel without logging the token', () {
    final source = File('lib/captcha_page.dart').readAsStringSync();

    expect(source, contains('CaptchaResult.postMessage(token)'));
    expect(source, contains('addJavaScriptChannel('));
    expect(source, isNot(contains('sunland://captcha')));
    expect(source, isNot(contains('setUserAgent(')));
    expect(source, isNot(contains('Captcha token received')));
  });

  test(
    'send-code preserves the complete GeeTest token in the API body',
    () async {
      final token = jsonEncode(<String, String>{
        'lot_number': 'lot-1',
        'captcha_output': 'output+with/symbols=',
        'pass_token': 'pass-1',
        'gen_time': '1787961600',
      });
      final client = MockClient((request) async {
        expect(request.url.toString(), '$sunlandApiBase/send-code');
        expect(request.headers['content-type'], 'application/json');
        expect(jsonDecode(request.body), <String, String>{
          'email': 'user@example.com',
          'token': token,
        });
        return http.Response('{}', 200);
      });

      await SunlandAuthApi(
        client: client,
      ).requestCode('user@example.com', captchaToken: token);
    },
  );
}
