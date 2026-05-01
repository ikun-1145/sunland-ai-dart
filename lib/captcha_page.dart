import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _captchaHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>验证中</title>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
  <style>
    body {
      margin: 0;
      height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #0f172a;
      color: white;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    }
    .box {
      text-align: center;
      padding: 24px;
      border-radius: 16px;
      background: rgba(255,255,255,0.05);
      backdrop-filter: blur(10px);
    }
    h2 {
      margin-bottom: 16px;
      font-weight: 500;
    }
  </style>
</head>
<body>
  <div class="box">
    <h2>正在进行安全验证...</h2>
    <div
      class="cf-turnstile"
      data-sitekey="0x4AAAAAAC_W2Wj2YdkrQiMf"
      data-callback="onSuccess"
      data-theme="dark">
    </div>
  </div>

  <script>
    function onSuccess(token) {
      console.log("Turnstile success, token:", token);
      window.location.href = "sunland://captcha?token=" + encodeURIComponent(token);
      throw new Error("STOP_NAVIGATION");
    }
  </script>
</body>
</html>
''';

class CaptchaPage extends StatefulWidget {
  const CaptchaPage({super.key});

  @override
  State<CaptchaPage> createState() => _CaptchaPageState();
}

class _CaptchaPageState extends State<CaptchaPage> {
  bool _handled = false;
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) => print("Page started: $url"),
          onPageFinished: (url) => print("Page finished: $url"),
          onNavigationRequest: (request) {
            print("WebView URL: ${request.url}");

            if (_handled) return NavigationDecision.prevent;

            if (request.url.startsWith("sunland://captcha")) {
              _handled = true;

              final uri = Uri.parse(request.url);
              final token = uri.queryParameters['token'];

              print("Captcha token received: $token");

              controller.loadRequest(Uri.parse("about:blank"));

              if (mounted) Navigator.pop(context, token);

              return NavigationDecision.prevent;
            }

            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadHtmlString(_captchaHtml, baseUrl: 'https://sunland.dev');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("安全验证")),
      body: WebViewWidget(controller: controller),
    );
  }
}
