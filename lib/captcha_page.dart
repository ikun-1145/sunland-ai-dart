import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _captchaResultChannel = 'CaptchaResult';

const String _captchaHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>安全验证</title>

  <script src="https://static.geetest.com/v4/gt4.js"></script>

  <style>
    body {
      margin: 0;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: radial-gradient(circle at 50% 30%, #1e293b, #0f172a);
      color: white;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    }

    .box {
      text-align: center;
      padding: 32px 28px;
      border-radius: 20px;
      background: rgba(255,255,255,0.08);
      backdrop-filter: blur(20px);
      box-shadow: 0 20px 60px rgba(0,0,0,0.5);
      width: 280px;
    }

    .spinner {
      width: 28px;
      height: 28px;
      border: 3px solid rgba(255,255,255,0.2);
      border-top: 3px solid #22d3ee;
      border-radius: 50%;
      margin: 0 auto 16px;
      animation: spin 1s linear infinite;
    }

    @keyframes spin {
      to { transform: rotate(360deg); }
    }

    h2 {
      margin: 0 0 10px;
      font-weight: 600;
      font-size: 16px;
      letter-spacing: 0.5px;
    }

    p {
      margin: 0 0 18px;
      font-size: 13px;
      color: rgba(255,255,255,0.6);
    }

    #captcha {
      margin-top: 10px;
    }
  </style>
</head>

<body>
  <div class="box">
    <div class="spinner"></div>
    <h2>正在验证身份</h2>
    <p>请稍候，这不会花很久</p>

    <div id="captcha"></div>
  </div>

  <script>
    initGeetest4({
      captchaId: "ad3a8126afe716ccd4541f35d428071e",
      product: "float"
    }, function (captchaObj) {

      captchaObj.appendTo("#captcha");

      captchaObj.onSuccess(function () {
        document.querySelector('.spinner').style.display = 'none';

        const result = captchaObj.getValidate();
        if (!result) return;

        const token = JSON.stringify(result);
        CaptchaResult.postMessage(token);
      });

    });
  </script>
</body>
</html>
''';

String? validateCaptchaResult(String token) {
  try {
    final decoded = jsonDecode(token);
    if (decoded is! Map) return null;

    for (final field in const <String>[
      'lot_number',
      'captcha_output',
      'pass_token',
      'gen_time',
    ]) {
      final value = decoded[field];
      if (value is! String || value.isEmpty) return null;
    }

    final genTime = decoded['gen_time'] as String;
    if (!RegExp(r'^\d+$').hasMatch(genTime)) return null;
    return token;
  } on FormatException {
    return null;
  }
}

class CaptchaPage extends StatefulWidget {
  const CaptchaPage({super.key});

  @override
  State<CaptchaPage> createState() => _CaptchaPageState();
}

class _CaptchaPageState extends State<CaptchaPage> {
  void _handleCaptchaResult(String message) {
    if (_handled) return;

    final token = validateCaptchaResult(message);
    if (token == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('验证结果异常，请重试')));
      _reloadCaptcha();
      return;
    }

    _handled = true;
    Navigator.pop(context, token);
  }

  void _reloadCaptcha() {
    setState(() {
      _pageLoaded = false;
      _handled = false;
    });
    controller.reload();
  }

  bool _handled = false;
  bool _pageLoaded = false;
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        _captchaResultChannel,
        onMessageReceived: (message) {
          if (mounted) _handleCaptchaResult(message.message);
        },
      )
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        debugPrint("JS Console [${message.level}]: ${message.message}");
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => debugPrint("Page started: $url"),
          onPageFinished: (url) {
            debugPrint("Page finished: $url");
            if (mounted) {
              setState(() => _pageLoaded = true);
            }
          },
          onWebResourceError: (error) {
            debugPrint(
              'WebView error ${error.errorCode}: ${error.description}',
            );
          },
        ),
      )
      ..loadHtmlString(_captchaHtml, baseUrl: 'https://sunland.dev');
  }

  @override
  void dispose() {
    controller.clearCache();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F1A),
      appBar: AppBar(
        title: const Text("安全验证"),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // WebView
          WebViewWidget(controller: controller),

          // Loading overlay（页面加载时更高级一点）
          if (!_pageLoaded)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.4),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/loading.gif', width: 80, height: 80),
                      const SizedBox(height: 20),
                      const Text(
                        "正在进行安全验证...",
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: TextButton(
                onPressed: _reloadCaptcha,
                child: const Text(
                  "验证加载失败？点击重试",
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
