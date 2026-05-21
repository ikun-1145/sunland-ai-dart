import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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
  Future<void> _openExternalCaptcha() async {
    final url = Uri.parse(
      "https://challenges.cloudflare.com/turnstile/v0/demo",
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  bool _handled = false;
  bool _pageLoaded = false;
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(
        "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
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
          onNavigationRequest: (request) {
            debugPrint("WebView URL: ${request.url}");

            if (request.url.startsWith("sunland://captcha")) {
              if (_handled) return NavigationDecision.prevent;
              _handled = true;

              final uri = Uri.parse(request.url);
              final token = uri.queryParameters['token'];

              debugPrint("Captcha token received: $token");

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
                onPressed: _openExternalCaptcha,
                child: const Text(
                  "验证加载失败？点此在浏览器打开",
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
