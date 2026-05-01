import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sunland_ai_core.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'captcha_page.dart';

const bool debugMode = false;

// ⭐ 全局 token 存储
String? _authToken;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://klyrasrqgxijwrxuoevj.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtseXJhc3JxZ3hpandyeHVvZXZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI4ODUyMzcsImV4cCI6MjA2ODQ2MTIzN30.qjeTrLp_QquSwvF09HrrQd-stPtgu6H51-Zdb4JUeSM',
  );
  final savedTheme = await loadThemeMode();

  themeNotifier.value = savedTheme;
  runApp(const MyApp());
}

class _BounceScrollBehavior extends ScrollBehavior {
  const _BounceScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

ValueNotifier<User?> currentUserNotifier = ValueNotifier(null);
ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
Future<void> saveThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();

  await prefs.setString('theme_mode', mode.name);
}

Future<ThemeMode> loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();

  final value = prefs.getString('theme_mode');

  switch (value) {
    case 'light':
      return ThemeMode.light;

    case 'dark':
      return ThemeMode.dark;

    default:
      return ThemeMode.system;
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, mode, _) {
        return ScrollConfiguration(
          behavior: const _BounceScrollBehavior(),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: '霜蓝AI',
            themeMode: mode,
            theme: ThemeData.light(),
            darkTheme: ThemeData.dark().copyWith(
              scaffoldBackgroundColor: const Color(0xFF0B0F1A),
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                foregroundColor: Colors.white,
              ),
            ),
            home: const RootPage(),
          ),
        );
      },
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  @override
  void initState() {
    super.initState();
    _restoreLogin();
  }

  Future<void> _restoreLogin() async {
    final store = SunlandSessionStore();
    final token = await store.readToken();
    final user = await store.readUser();

    if (token != null && user != null) {
      _authToken = token;

      currentUserNotifier.value = User.fromJson({
        "id": user.id,
        "email": user.email,
        "aud": "authenticated",
        "created_at": DateTime.now().toIso8601String(),
        "app_metadata": <String, dynamic>{},
        "user_metadata": Map<String, dynamic>.from(user.toJson()),
      });

      final prefs = await SharedPreferences.getInstance();
      final chosen = prefs.getBool('theme_chosen') ?? false;

      if (!chosen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showThemeDialog();
        });
      }
    }
  }

  void _showThemeDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: const Text("选择主题"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("浅色模式"),
                onTap: () async {
                  themeNotifier.value = ThemeMode.light;
                  await saveThemeMode(ThemeMode.light);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('theme_chosen', true);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text("深色模式"),
                onTap: () async {
                  themeNotifier.value = ThemeMode.dark;
                  await saveThemeMode(ThemeMode.dark);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('theme_chosen', true);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text("跟随系统"),
                onTap: () async {
                  themeNotifier.value = ThemeMode.system;
                  await saveThemeMode(ThemeMode.system);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('theme_chosen', true);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ValueListenableBuilder<User?>(
      valueListenable: currentUserNotifier,
      builder: (context, user, _) {
        if (user == null) {
          return const LoginPage();
        }
        return const SplashPage();
      },
    );
  }
}

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scale = Tween<double>(
      begin: 0.6,
      end: 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    _splashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, _, _) => const ChatPage(),
          transitionsBuilder: (_, animation, _, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      body: Center(
        child: ScaleTransition(
          scale: _scale,
          child: Image.asset('assets/ailogo.png', width: 120),
        ),
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final api = const SunlandAuthApi();
  final store = SunlandSessionStore();

  final emailController = TextEditingController();
  final codeController = TextEditingController();

  bool sending = false;
  bool verifying = false;
  bool agreed = false;
  int countdown = 0;
  bool get canLogin {
    return emailController.text.trim().isNotEmpty &&
        codeController.text.trim().isNotEmpty &&
        agreed &&
        !verifying;
  }

  Timer? countdownTimer;

  late AnimationController _animController;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  void sendCode() async {
    if (sending || countdown > 0) return;

    final email = emailController.text.trim().toLowerCase();

    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请输入正确邮箱")));
      return;
    }

    // ===== 🚨 先做人机验证 =====
    final token = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CaptchaPage()),
    );

    if (token == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("验证失败")));
      return;
    }

    setState(() => sending = true);

    try {
      await api.requestCode(email, captchaToken: token);

      startCountdown();

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("验证码已发送")));

      FocusScope.of(context).nextFocus();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("发送失败: $e")));
    }

    if (mounted) setState(() => sending = false);
  }

  void startCountdown() {
    countdownTimer?.cancel();
    setState(() => countdown = 60);

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (countdown <= 1) {
        timer.cancel();
        setState(() => countdown = 0);
      } else {
        setState(() => countdown--);
      }
    });
  }

  void login() async {
    final email = emailController.text.trim().toLowerCase();
    final code = codeController.text.replaceAll(RegExp(r"\s"), "").trim();

    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(email)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请输入正确邮箱")));
      return;
    }

    if (email.isEmpty || code.isEmpty) return;

    if (!agreed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先同意用户协议与隐私政策")));
      return;
    }

    setState(() => verifying = true);

    try {
      final result = await api.verifyCode(
        email: email,
        code: code,
        captchaToken: "", // 登录阶段不再二次验证
      );

      _authToken = result.token;
      await store.saveSession(token: result.token, user: result.user);

      currentUserNotifier.value = User.fromJson({
        "id": result.user.id,
        "email": result.user.email,
        "aud": "authenticated",
        "created_at": DateTime.now().toIso8601String(),
        "app_metadata": <String, dynamic>{},
        "user_metadata": Map<String, dynamic>.from(result.user.toJson()),
      });

      // ✅ 清空输入
      emailController.clear();
      codeController.clear();

      if (!mounted) return;

      // ✅ 主动跳转（关键！）
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SplashPage()),
      );

      // ⭐ 首次登录弹出主题选择
      final prefs = await SharedPreferences.getInstance();
      final chosen = prefs.getBool('theme_chosen') ?? false;

      if (!chosen && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) {
              return AlertDialog(
                title: const Text("选择主题"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text("浅色模式"),
                      onTap: () async {
                        themeNotifier.value = ThemeMode.light;
                        await saveThemeMode(ThemeMode.light);
                        await prefs.setBool('theme_chosen', true);
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: const Text("深色模式"),
                      onTap: () async {
                        themeNotifier.value = ThemeMode.dark;
                        await saveThemeMode(ThemeMode.dark);
                        await prefs.setBool('theme_chosen', true);
                        Navigator.pop(context);
                      },
                    ),
                    ListTile(
                      title: const Text("跟随系统"),
                      onTap: () async {
                        themeNotifier.value = ThemeMode.system;
                        await saveThemeMode(ThemeMode.system);
                        await prefs.setBool('theme_chosen', true);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              );
            },
          );
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("登录失败: $e")));
    }

    if (mounted) setState(() => verifying = false);
  }

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fade = CurvedAnimation(parent: _animController, curve: Curves.easeOut);

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    countdownTimer?.cancel();
    emailController.dispose();
    codeController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0B0F1A), Color(0xFF111827)]
                : const [Color(0xFFEAF4FF), Color(0xFFF7FBFF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // --- Header Section ---
                    Column(
                      children: [
                        Image.asset('assets/ailogo.png', width: 90),
                        const SizedBox(height: 32),

                        Text(
                          "霜蓝 AI",
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),

                        const SizedBox(height: 6),

                        Text(
                          "你的专属智能助手 ✨",
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black54,
                            fontSize: 14,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          "登录后即可开始对话、创作与探索",
                          style: TextStyle(
                            color: isDark ? Colors.white38 : Colors.black38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 30),

                    // --- 输入框卡片背景 ---
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withAlpha(13)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withAlpha(20)
                              : Colors.black12,
                        ),
                      ),
                      child: Column(
                        children: [
                          TextField(
                            controller: emailController,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: "邮箱",
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              border: InputBorder.none,
                            ),
                          ),

                          Divider(
                            color: isDark ? Colors.white12 : Colors.black12,
                          ),

                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: codeController,
                                  onChanged: (_) => setState(() {}),
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: "验证码",
                                    hintStyle: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                    border: InputBorder.none,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: (sending || countdown > 0)
                                    ? null
                                    : sendCode,
                                child: Text(
                                  sending
                                      ? "发送中..."
                                      : countdown > 0
                                      ? "${countdown}s"
                                      : "发送",
                                  style: TextStyle(
                                    color: (sending || countdown > 0)
                                        ? (isDark
                                              ? Colors.white38
                                              : Colors.black38)
                                        : const Color(0xFF3B82F6),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // --- 登录按钮增强（渐变） ---
                    Container(
                      width: double.infinity,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                        ),
                        onPressed: canLogin ? login : null,
                        child: verifying
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                "登录",
                                style: TextStyle(
                                  color: canLogin
                                      ? Colors.white
                                      : Colors.white54,
                                ),
                              ),
                      ),
                    ),

                    // --- 底部提示 ---
                    const SizedBox(height: 12),

                    GestureDetector(
                      onTap: () {
                        setState(() {
                          agreed = !agreed;
                        });
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            value: agreed,
                            activeColor: const Color(0xFF22D3EE),
                            checkColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            onChanged: (v) {
                              setState(() {
                                agreed = v ?? false;
                              });
                            },
                          ),
                          Expanded(
                            child: Wrap(
                              children: [
                                Text(
                                  "我已阅读并同意 ",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                    fontSize: 11,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    launchUrl(
                                      Uri.parse(
                                        "https://sunland.dev/xukexieyi",
                                      ),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  child: const Text(
                                    "用户协议",
                                    style: TextStyle(
                                      color: Color(0xFF22D3EE),
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text(" "),
                                Text(
                                  "和 ",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                    fontSize: 11,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    launchUrl(
                                      Uri.parse("https://sunland.dev/privacy"),
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  child: const Text(
                                    "隐私政策",
                                    style: TextStyle(
                                      color: Color(0xFF22D3EE),
                                      fontSize: 11,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      "未注册会自动创建账号",
                      style: TextStyle(
                        color: isDark ? Colors.white60 : Colors.black54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  int compareVersion(String v1, String v2) {
    List<String> split(String v) {
      return v.replaceAll("beta", "-beta.").split(RegExp(r'[.-]'));
    }

    final a = split(v1);
    final b = split(v2);

    for (int i = 0; i < 4; i++) {
      final x = i < a.length ? a[i] : "0";
      final y = i < b.length ? b[i] : "0";

      if (x == "beta" && y != "beta") return -1;
      if (x != "beta" && y == "beta") return 1;

      final xi = int.tryParse(x) ?? 0;
      final yi = int.tryParse(y) ?? 0;

      if (xi != yi) return xi.compareTo(yi);
    }

    return 0;
  }

  void cancelGeneration() {
    print("🛑 cancelGeneration 被调用");
    if (!isGenerating) return;

    _cancelRequested = true;

    setState(() {
      isGenerating = false;
    });

    // 👇 防止残留“思考中...”
    if (messages.isNotEmpty &&
        (messages.last["text"] == "思考中..." ||
            messages.last["text"] == "深度思考中...")) {
      messages.removeLast();
    }
  }

  void _showThemeDialogInChat() {
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("选择主题"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text("浅色模式"),
                onTap: () async {
                  themeNotifier.value = ThemeMode.light;
                  await saveThemeMode(ThemeMode.light);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text("深色模式"),
                onTap: () async {
                  themeNotifier.value = ThemeMode.dark;
                  await saveThemeMode(ThemeMode.dark);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text("跟随系统"),
                onTap: () async {
                  themeNotifier.value = ThemeMode.system;
                  await saveThemeMode(ThemeMode.system);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget buildMessageContent(
    Map<String, dynamic> msg,
    bool isUser,
    bool isDark,
  ) {
    if (isUser) {
      return Text(
        msg["text"],
        style: const TextStyle(fontSize: 15, color: Colors.white),
      );
    }

    if (msg["isReasoning"] == true) {
      return GestureDetector(
        onTap: () {
          setState(() {
            msg["expanded"] = !(msg["expanded"] ?? false);
          });
        },
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.grey.withAlpha(25),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.psychology, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text(
                    "思考过程",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
              if (msg["expanded"] == true) ...[
                const SizedBox(height: 6),
                MarkdownBody(data: msg["text"] ?? ""),
              ],
            ],
          ),
        ),
      );
    }

    if (msg["text"] == "思考中..." || msg["text"] == "深度思考中...") {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(msg["text"]),
        ],
      );
    }

    return MarkdownBody(data: msg["text"] ?? "");
  }

  late final SunlandApiClient apiClient;
  late final SupabaseAiRepository repo;
  final supabase = Supabase.instance.client;
  bool useReasoner = false;
  bool isActivated = false;
  int _remainingCount = freeDailyLimit;
  String? _lastUserText;
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> conversations = [];
  final Map<String, List<Map<String, dynamic>>> localConversationMessages = {};
  String? currentConversationId;
  bool isGenerating = false;
  bool _cancelRequested = false;
  List<String> pickedImages = [];
  bool isUploadingAvatar = false;

  bool isLocalConversation(String? id) => id?.startsWith('local_') ?? false;

  void rememberLocalMessages() {
    final id = currentConversationId;
    if (id == null || !isLocalConversation(id)) return;

    localConversationMessages[id] = messages
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    // 限制缓存数量，防止内存增长
    if (localConversationMessages.length > 20) {
      localConversationMessages.remove(localConversationMessages.keys.first);
    }
  }

  void createLocalConversation(String firstMessage) {
    final id = 'local_${DateTime.now().microsecondsSinceEpoch}';
    currentConversationId = id;
    conversations.insert(0, {
      'id': id,
      'title': buildConversationTitle(firstMessage),
      'is_local': true,
    });
  }

  // (loadMessages removed)

  Future<void> loadConversations() async {
    final user = currentUserNotifier.value;
    if (user == null) return;

    final data = await supabase
        .from('conversations')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false);

    setState(() {
      conversations = List<Map<String, dynamic>>.from(data);
    });
  }

  @override
  void initState() {
    super.initState();
    apiClient = SunlandApiClient(tokenProvider: () async => _authToken);
    repo = SupabaseAiRepository();
    _initData();
  }

  void showProfileSetupDialog() {
    final nameController = TextEditingController();
    String? avatarPath;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("完善资料"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () async {
                      final picker = ImagePicker();
                      final picked = await picker.pickImage(
                        source: ImageSource.gallery,
                      );
                      if (picked != null) {
                        setStateDialog(() {
                          avatarPath = picked.path;
                        });
                      }
                    },
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: const Color(0xFF22D3EE),
                      backgroundImage: avatarPath != null
                          ? FileImage(File(avatarPath!))
                          : null,
                      child: avatarPath == null
                          ? const Icon(Icons.camera_alt, color: Colors.white)
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      hintText: "输入昵称",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    final user = currentUserNotifier.value;
                    if (user == null) return;

                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text("请输入昵称")));
                      return;
                    }

                    String? avatarUrl;

                    if (avatarPath != null) {
                      final file = File(avatarPath!);
                      final fileName = '${user.id}.png';

                      await supabase.storage
                          .from('avatars')
                          .upload(
                            fileName,
                            file,
                            fileOptions: const FileOptions(upsert: true),
                          );

                      avatarUrl = supabase.storage
                          .from('avatars')
                          .getPublicUrl(fileName);
                    }

                    final current = currentUserNotifier.value;
                    if (current != null) {
                      final updated = User.fromJson({
                        "id": current.id,
                        "email": current.email,
                        "aud": "authenticated",
                        "created_at": current.createdAt,
                        "app_metadata": <String, dynamic>{},
                        "user_metadata": Map<String, dynamic>.from({
                          ...(current.userMetadata ?? <String, dynamic>{}),
                          "avatar_url": avatarUrl,
                          "name": name,
                        }),
                      });

                      currentUserNotifier.value = updated;
                    }

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    if (!mounted) return;
                    setState(() {});
                  },
                  child: const Text("保存"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _initData() async {
    final user = currentUserNotifier.value;
    if (user == null) return;
    await loadConversations();
    await _checkActivation();

    if (conversations.isNotEmpty) {
      final convo = conversations.first;
      currentConversationId = convo["id"];

      final msgs = await supabase
          .from('messages')
          .select()
          .eq('conversation_id', currentConversationId!)
          .order('created_at');

      if (!mounted) return;

      setState(() {
        messages = (msgs as List)
            .map((e) => {"text": e['content'], "isUser": e['is_user']})
            .toList();
      });
    }
    await checkUpdate();
  }

  Future<void> checkUpdate() async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse("https://sunland.dev/version.json"),
      );
      final response = await request.close();

      if (response.statusCode != 200) return;

      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);

      final latestVersion = data["version"];
      final updateUrl = data["url"];

      const currentVersion = "1.0.0 beta5"; // ⭐ 记得改成你当前版本

      if (compareVersion(latestVersion, currentVersion) > 0 && mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text("发现新版本"),
            content: Text("当前版本 $currentVersion\n最新版本 $latestVersion"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("稍后"),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final uri = Uri.parse(updateUrl);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  }
                },
                child: const Text("立即更新"),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print("更新检测失败: $e");
    }
  }

  Future<void> _checkActivation() async {
    final user = currentUserNotifier.value;
    if (user == null) return;

    final activated = await repo.isActivated(user.id);

    if (mounted) {
      setState(() {
        isActivated = activated;
      });
    }

    // ✅ 加上剩余次数
    if (!activated) {
      final count = await repo.usageCount(user.id);
      if (mounted) {
        setState(() => _remainingCount = freeDailyLimit - count);
      }
    }
  }

  Future<void> sendMessage() async {
    print("⚡ sendMessage 被调用");
    _cancelRequested = false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_authToken ?? 'NULL'),
        duration: Duration(seconds: 30),
      ),
    );
    FocusScope.of(context).unfocus();

    // ===== 使用次数检查 =====
    final user = currentUserNotifier.value;
    if (user != null && !isActivated) {
      final count = await repo.usageCount(user.id);
      if (count >= freeDailyLimit) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("今日使用次数已达上限（20次），升级 Pro 可无限使用")),
          );
        }
        return;
      }
    }
    // 防并发触发（允许重生但防乱点）
    if (isGenerating && messages.isNotEmpty) return;
    final text = controller.text.trim();
    final isRegenerate = (text == _lastUserText);
    if (text.isEmpty) return;

    // ✅ 内容审核
    final modResult = InputModerator.check(text);
    if (modResult != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(InputModerator.refusalText)));
      }
      return;
    }

    // ✅ 记录最后一条用户消息（用于重新生成）
    _lastUserText = text;

    setState(() {
      isGenerating = true;
      if (!isRegenerate) {
        messages.add({"text": text, "isUser": true});
      }
      messages.add({
        "text": useReasoner ? "深度思考中..." : "思考中...",
        "isUser": false,
        "isStreaming": true,
      });
    });

    // Insert conversation and user message if needed
    rememberLocalMessages(); // ⭐ 防止新建对话前丢失当前内容

    if (currentConversationId == null) {
      if (user != null) {
        final convo = await supabase
            .from('conversations')
            .insert({'user_id': user.id, 'title': buildConversationTitle(text)})
            .select()
            .single();

        currentConversationId = convo['id'];
        loadConversations();
      } else {
        setState(() {
          createLocalConversation(text);
        });
      }
    }

    if (user != null) {
      await supabase.from('messages').insert({
        'user_id': user.id,
        'conversation_id': currentConversationId,
        'content': text,
        'is_user': true,
      });
    } else {
      rememberLocalMessages();
    }

    controller.clear();
    setState(() {
      final idx = conversations.indexWhere(
        (c) => c['id'] == currentConversationId,
      );
      if (idx > 0) {
        final convo = conversations.removeAt(idx);
        conversations.insert(0, convo);
      }
    });
    scrollToBottom();

    try {
      // ===== 使用 Core 构建并发送 =====
      print("🚀 开始请求 AI");
      print("当前 TOKEN: $_authToken");
      if (pickedImages.isNotEmpty) {
        setState(() => pickedImages.clear());
      }

      setState(() {
        if (messages.isNotEmpty) messages.removeLast();
        messages.add({"text": "", "isUser": false, "isStreaming": true});
      });

      String? reasoning;
      await for (final chunk in sendSmartChatStream(
        client: apiClient,
        rawMessages: messages,
        pickedImages: [],
        deep: useReasoner,
      )) {
        if (_cancelRequested) break;

        if (chunk.reasoning != null && chunk.reasoning!.isNotEmpty) {
          reasoning = chunk.reasoning;
        }

        setState(() {
          messages.last["text"] = chunk.content;
        });
        scrollToBottom();
      }

      if (reasoning != null && reasoning.isNotEmpty) {
        final finalText = messages.last["text"];
        setState(() {
          messages.removeLast();
          messages.add({
            "text": reasoning,
            "isUser": false,
            "isReasoning": true,
            "expanded": false,
          });
          messages.add({"text": finalText, "isUser": false});
        });
      }

      if (user != null) {
        // Save assistant message
        await supabase.from('messages').insert({
          'user_id': user.id,
          'conversation_id': currentConversationId,
          'content': messages.last["text"],
          'is_user': false,
        });
      } else {
        rememberLocalMessages();
      }

      // ===== 成功后计数 =====
      if (user != null && !isActivated) {
        await repo.incrementUsage(user.id);

        if (mounted) {
          setState(() {
            _remainingCount = (_remainingCount - 1).clamp(0, freeDailyLimit);
          });
        }
      }

      setState(() {
        isGenerating = false;
      });

      // ⭐ AI 自动生成对话标题（仅第一次）
      try {
        final convoId = currentConversationId;
        if (convoId != null) {
          final index = conversations.indexWhere((c) => c['id'] == convoId);
          if (index != -1) {
            final currentTitle = conversations[index]['title'] ?? '';
            // 只在默认标题时更新
            final userMsgCount = messages
                .where((m) => m["isUser"] == true)
                .length;
            if (userMsgCount == 1) {
              // ⭐ 异步生成标题，不阻塞 UI
              Future(() async {
                String? aiTitle;
                try {
                  aiTitle = await apiClient.generateTitle(
                    userMessage: text,
                    aiMessage: messages.last["text"],
                  );
                } catch (_) {}

                final newTitle = (aiTitle != null && aiTitle.trim().isNotEmpty)
                    ? (aiTitle.length > 15
                          ? "${aiTitle.substring(0, 15)}..."
                          : aiTitle)
                    : buildConversationTitle(text);

                if (mounted) {
                  setState(() {
                    conversations[index]['title'] = newTitle;
                  });
                }

                // 云端同步
                if (user != null) {
                  await supabase
                      .from('conversations')
                      .update({'title': newTitle})
                      .eq('id', convoId);
                }
              });
            }
          }
        }
      } catch (_) {
        // 忽略标题生成失败
      }
      scrollToBottom();
    } catch (e) {
      print("❌ AI 请求异常: $e");
      if (e is AuthExpiredException) {
        final store = SunlandSessionStore();
        await store.clearSession();
        _authToken = null;
        currentUserNotifier.value = null;
        return;
      }

      setState(() {
        if (messages.isNotEmpty) {
          messages.removeLast();
        }
        messages.add({"text": "请求失败：$e", "isUser": false});
        isGenerating = false;
      });

      rememberLocalMessages();
    } finally {
      print("🔚 请求结束（finally）");
      if (mounted) {
        setState(() {
          isGenerating = false;
          print("🔥 sendMessage 被调用, isGenerating=$isGenerating");
          _cancelRequested = false;
          // 防止“思考中...”卡住
          if (messages.isNotEmpty &&
              (messages.last["text"] == "思考中..." ||
                  messages.last["text"] == "深度思考中...")) {
            messages.removeLast();
            messages.add({"text": "请求超时或失败，请重试", "isUser": false});
          }
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget buildQuickBtn(String text) {
    return GestureDetector(
      onTap: () {
        controller.text = text.replaceAll(
          RegExp(r'^[^ ]+ '),
          '',
        ); // 去掉 emoji 前缀
        sendMessage();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  Future<void> pickImage() async {
    // 📱 移动端：使用 image_picker
    if (Platform.isAndroid || Platform.isIOS) {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage();

      if (picked.isEmpty) return;

      setState(() {
        for (var img in picked) {
          pickedImages.add(img.path);
        }
      });
      return;
    }

    // 💻 桌面端：使用 file_picker
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      for (var file in result.files) {
        if (file.path != null) {
          pickedImages.add(file.path!);
        }
      }
    });
  }

  Future<void> pickAndUploadAvatar() async {
    final user = currentUserNotifier.value;
    if (user == null) return;

    setState(() {
      isUploadingAvatar = true;
    });

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      setState(() {
        isUploadingAvatar = false;
      });
      return;
    }

    final file = File(picked.path);
    final fileName = '${user.id}.png';

    // 上传到 Supabase Storage（bucket: avatars）
    String? publicUrl;
    try {
      await supabase.storage
          .from('avatars')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("头像上传失败")));
      }
    } finally {
      if (mounted) {
        setState(() {
          isUploadingAvatar = false;
        });
      }
    }

    if (publicUrl == null) return;

    // 写入用户 metadata
    final current = currentUserNotifier.value;
    if (current != null) {
      final updated = User.fromJson({
        "id": current.id,
        "email": current.email,
        "aud": "authenticated",
        "created_at": current.createdAt,
        "app_metadata": <String, dynamic>{},
        "user_metadata": Map<String, dynamic>.from({
          ...(current.userMetadata ?? <String, dynamic>{}),
          "avatar_url": publicUrl,
        }),
      });

      currentUserNotifier.value = updated;
    }
    if (!mounted) return;
  }

  void showUserMenu() {
    final user = currentUserNotifier.value;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 顶部拖拽条
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // 用户信息卡片
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFF22D3EE),
                          backgroundImage:
                              (user?.userMetadata?['avatar_url'] != null)
                              ? NetworkImage(user!.userMetadata!['avatar_url'])
                              : null,
                          child: (user?.userMetadata?['avatar_url'] == null)
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            user?.email ?? "开发模式（免登录）",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 功能按钮（卡片风）
                  _menuItem(
                    icon: Icons.refresh,
                    text: user == null ? "保留本地对话" : "重新加载对话",
                    onTap: () {
                      Navigator.pop(context);
                      if (user != null) loadConversations();
                    },
                  ),

                  _menuItem(
                    icon: Icons.palette,
                    text: "主题设置",
                    onTap: () {
                      Navigator.pop(context);
                      _showThemeDialogInChat();
                    },
                  ),

                  if (user != null && user.userMetadata?['avatar_url'] == null)
                    _menuItem(
                      icon: Icons.image,
                      text: "更换头像",
                      onTap: () async {
                        Navigator.pop(context);
                        if (isUploadingAvatar) return;

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("头像上传中...")),
                        );

                        await pickAndUploadAvatar();

                        if (!mounted) return;
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(const SnackBar(content: Text("头像已更新")));
                      },
                    ),

                  if (user != null)
                    _menuItem(
                      icon: Icons.logout,
                      text: "退出登录",
                      color: Colors.red,
                      onTap: () async {
                        final navigator = Navigator.of(context);

                        _authToken = null;
                        final store = SunlandSessionStore();
                        await store.clearSession();

                        // ⭐ 强制回到登录页，而不是进入开发模式
                        currentUserNotifier.value = null;

                        navigator.pop();

                        if (!mounted) return;

                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                        );
                      },
                    ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
    Color? color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.grey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: color ?? (isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(width: 12),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: color ?? (isDark ? Colors.white : Colors.black87),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      drawer: Drawer(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo + 标题
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, color: Color(0xFFFF8A3D)),
                    const SizedBox(width: 8),
                    Text(
                      "霜蓝 AI",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 新建对话按钮（Claude 风格）
                GestureDetector(
                  onTap: () {
                    final currentMsgs = currentConversationId != null
                        ? (localConversationMessages[currentConversationId] ??
                              messages)
                        : messages;
                    final hasUserMsg = currentMsgs.any(
                      (m) => m["isUser"] == true,
                    );

                    if (!hasUserMsg && currentConversationId != null) {
                      Navigator.pop(context);
                      return;
                    }

                    rememberLocalMessages();
                    Navigator.pop(context);

                    setState(() {
                      final id =
                          'local_${DateTime.now().microsecondsSinceEpoch}';

                      currentConversationId = id;
                      messages.clear();

                      conversations.insert(0, {
                        'id': id,
                        'title': buildConversationTitle(""),
                        'is_local': true,
                      });

                      localConversationMessages[id] = [];

                      controller.clear();
                      pickedImages.clear();
                      isGenerating = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1A1A1A)
                          : Colors.grey.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add,
                            color: Colors.white70,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            "新建对话",
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // === Conversation List UI (insertion) ===
                const SizedBox(height: 16),

                Expanded(
                  child: ListView.builder(
                    itemCount: conversations.length,
                    itemBuilder: (context, index) {
                      final convo = conversations[index];
                      final isActive = convo['id'] == currentConversationId;

                      return GestureDetector(
                        onTap: () async {
                          rememberLocalMessages();
                          final id = convo['id'];

                          // 本地缓存优先
                          if (localConversationMessages.containsKey(id)) {
                            setState(() {
                              currentConversationId = id;
                              messages = List<Map<String, dynamic>>.from(
                                localConversationMessages[id]!,
                              );
                            });
                            return;
                          }

                          // 本地没有 → 从 Supabase 拉取
                          setState(() {
                            currentConversationId = id;
                            messages = [];
                          });
                          Navigator.pop(context);

                          if (!isLocalConversation(id)) {
                            final msgs = await supabase
                                .from('messages')
                                .select()
                                .eq('conversation_id', id)
                                .order('created_at');

                            if (!mounted) return;
                            setState(() {
                              messages = (msgs as List)
                                  .map(
                                    (e) => {
                                      "text": e['content'],
                                      "isUser": e['is_user'],
                                    },
                                  )
                                  .toList();
                              localConversationMessages[id] = List.from(
                                messages,
                              );
                            });
                            scrollToBottom();
                          }
                        },
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) {
                              return SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.edit),
                                      title: const Text("重命名"),
                                      onTap: () {
                                        Navigator.pop(context);

                                        final renameController =
                                            TextEditingController(
                                              text: convo['title'],
                                            );

                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text("重命名对话"),
                                            content: TextField(
                                              controller: renameController,
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text("取消"),
                                              ),
                                              TextButton(
                                                onPressed: () {
                                                  setState(() {
                                                    convo['title'] =
                                                        renameController.text
                                                            .trim();
                                                  });
                                                  Navigator.pop(context);
                                                },
                                                child: const Text("确定"),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      title: const Text(
                                        "删除对话",
                                        style: TextStyle(color: Colors.red),
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);

                                        showDialog(
                                          context: context,
                                          builder: (_) => AlertDialog(
                                            title: const Text("确认删除？"),
                                            content: const Text("这个对话将无法恢复"),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                                child: const Text("取消"),
                                              ),
                                              TextButton(
                                                onPressed: () async {
                                                  final deletedId = convo['id'];
                                                  Navigator.pop(context);

                                                  setState(() {
                                                    conversations.removeAt(
                                                      index,
                                                    );
                                                    localConversationMessages
                                                        .remove(deletedId);

                                                    if (currentConversationId ==
                                                        deletedId) {
                                                      currentConversationId =
                                                          null;
                                                      messages.clear();
                                                    }
                                                  });

                                                  if (!isLocalConversation(
                                                    deletedId,
                                                  )) {
                                                    await supabase
                                                        .from('conversations')
                                                        .delete()
                                                        .eq('id', deletedId);

                                                    supabase
                                                        .from('messages')
                                                        .delete()
                                                        .eq(
                                                          'conversation_id',
                                                          deletedId,
                                                        )
                                                        .catchError((_) {});
                                                  }
                                                },
                                                child: const Text(
                                                  "删除",
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? const Color(0xFF1A1A1A)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            convo['title'] ?? '新对话',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // === End Conversation List UI ===
                const Spacer(),

                // 底部用户（弱化版）
                Builder(
                  builder: (_) {
                    final user = currentUserNotifier.value;
                    final name =
                        user?.userMetadata?['name'] ??
                        user?.email?.split('@')[0] ??
                        '用户';

                    final initial = name.isNotEmpty
                        ? name.substring(0, 1)
                        : '?';

                    return Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.black,
                          child: Text(
                            initial,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          name,
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.transparent,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.transparent,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            );
          },
        ),
        title: Row(
          children: [
            // 左侧：标题 + 深度思考
            Expanded(
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "霜蓝AI",
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      if (!isActivated)
                        Text(
                          "今日剩余 $_remainingCount 次",
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        )
                      else
                        const Text(
                          "💎 Pro · 无限使用",
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF22D3EE),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        useReasoner = !useReasoner;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: useReasoner
                            ? const Color(0xFF22D3EE)
                            : Colors.grey.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "深度思考",
                        style: TextStyle(
                          fontSize: 12,
                          color: useReasoner ? Colors.white : Colors.black54,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 右侧：用户
            Builder(
              builder: (_) {
                final user = currentUserNotifier.value;
                return GestureDetector(
                  onTap: showUserMenu,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 10,
                        backgroundColor: const Color(0xFF22D3EE),
                        backgroundImage:
                            (user?.userMetadata?['avatar_url'] != null)
                            ? NetworkImage(user!.userMetadata!['avatar_url'])
                            : null,
                        child: (user?.userMetadata?['avatar_url'] == null)
                            ? const Icon(
                                Icons.person,
                                size: 14,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 80),
                        child: Text(
                          user?.userMetadata?['name'] ??
                              user?.email?.split('@')[0] ??
                              "开发模式",
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            // 背景渐变（更高级）
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? const [Color(0xFF0B0F1A), Color(0xFF111827)]
                      : const [Color(0xFFF3F8FF), Color(0xFFE6F2FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
            Column(
              children: [
                // Insert padding at the very top to offset for AppBar when extendBodyBehindAppBar is true
                SizedBox(
                  height:
                      MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                ),
                if (messages.where((m) => m["isUser"] == true).isEmpty) ...[
                  const Spacer(),
                  Builder(
                    builder: (_) {
                      final user = currentUserNotifier.value;
                      final displayName =
                          user?.userMetadata?['name'] ??
                          user?.email?.split('@')[0];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 40, 20, 0),
                            child: Text(
                              displayName != null ? "$displayName 👋" : "你好 👋",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                            child: ShaderMask(
                              shaderCallback: (bounds) {
                                return const LinearGradient(
                                  colors: [
                                    Color(0xFF22D3EE),
                                    Color(0xFF3B82F6),
                                  ],
                                ).createShader(bounds);
                              },
                              child: const Text(
                                "今天想做点什么？",
                                style: TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                buildQuickBtn("🧠 激发我的活力"),
                                buildQuickBtn("✨ 给我一点灵感"),
                                buildQuickBtn("📄 随便聊聊"),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                ],
                // 聊天区
                if (messages.isNotEmpty)
                  Expanded(
                    child: ListView.builder(
                      key: ValueKey(currentConversationId),
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      // Changed padding to prevent extra top spacing
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final isUser = msg["isUser"];
                        return AnimatedSlide(
                          offset: const Offset(0, 0.1),
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                          child: AnimatedOpacity(
                            opacity: 1,
                            duration: const Duration(milliseconds: 250),
                            child: GestureDetector(
                              onLongPress: () {
                                if (!isUser) {
                                  Clipboard.setData(
                                    ClipboardData(text: msg["text"]),
                                  );
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("已复制"),
                                      duration: Duration(milliseconds: 1200),
                                    ),
                                  );
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                alignment: isUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  constraints: BoxConstraints(
                                    maxWidth:
                                        MediaQuery.of(context).size.width *
                                        0.65,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isUser
                                        ? const Color(0xFF22D3EE)
                                        : (isDark
                                              ? const Color(0xFF1F2937)
                                              : Colors.white),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: buildMessageContent(
                                    msg,
                                    isUser,
                                    isDark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                // 输入区
                SafeArea(
                  top: false,
                  child: AnimatedPadding(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.of(context).viewInsets.bottom,
                    ),
                    child: Container(
                      color: Colors.transparent,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: controller,
                              minLines: 1,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: "输入内容...",
                                filled: true,
                                fillColor: isDark
                                    ? const Color(0xFF1F2937)
                                    : Colors.white,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 16,
                              ),
                              onSubmitted: (_) {
                                FocusScope.of(context).unfocus();
                                sendMessage();
                              },
                              textInputAction: TextInputAction.send,
                              keyboardType: TextInputType.multiline,
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              Icons.image,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            onPressed: pickImage,
                            tooltip: "添加图片",
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              isGenerating ? Icons.stop : Icons.send,

                              color: isGenerating
                                  ? Colors.red
                                  : (isDark
                                        ? Colors.white
                                        : const Color(0xFF3B82F6)),
                            ),

                            onPressed: () {
                              if (isGenerating) {
                                cancelGeneration();
                              } else {
                                sendMessage();
                              }
                            },

                            tooltip: isGenerating ? "停止生成" : "发送",
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
