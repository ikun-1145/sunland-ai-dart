import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String _captchaHtml = '''
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>安全验证</title>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>

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

    .cf-turnstile {
      margin-top: 10px;
    }
  </style>
</head>

<body>
  <div class="box">
    <div class="spinner"></div>
    <h2>正在验证身份</h2>
    <p>请稍候，这不会花很久</p>

    <div
      class="cf-turnstile"
      data-sitekey="0x4AAAAAAC_W2Wj2YdkrQiMf"
      data-callback="onSuccess"
      data-theme="dark">
    </div>
  </div>

  <script>
    function onSuccess(token) {
      document.querySelector('.spinner').style.display = 'none';
      console.log("Turnstile success, token:", token);
      window.location.href = "sunland://captcha?token=" + encodeURIComponent(token);
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
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.4),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/loading.gif', width: 40, height: 40),
                    const SizedBox(height: 16),
                    const Text(
                      "正在进行安全验证...",
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
