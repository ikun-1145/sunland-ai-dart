import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'sunland_ai_core.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'captcha_page.dart';
import 'settings_page.dart';
import 'update_service.dart';

// ⭐ 全局 token 存储
String? _authToken;
Completer<String?>? _tokenRefreshInProgress;
final SunlandSessionStore _sessionStore = SunlandSessionStore();

User _buildSupabaseUser(SunlandUser user) {
  final metadata = <String, dynamic>{};
  if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
    metadata['avatar_url'] = user.avatarUrl;
  }
  if (user.avatarPath != null && user.avatarPath!.isNotEmpty) {
    metadata['avatar_path'] = user.avatarPath;
  }

  return User.fromJson({
    "id": user.id,
    "email": user.email,
    "aud": "authenticated",
    "created_at": DateTime.now().toIso8601String(),
    "app_metadata": <String, dynamic>{},
    "user_metadata": metadata,
  })!;
}

Future<String?> _readFreshAuthToken({bool notify = true}) async {
  var token = _authToken ?? await _sessionStore.readToken();
  if (token == null || token.isEmpty) return null;

  if (isJwtExpired(token, skew: const Duration(seconds: 30))) {
    // 如果已有刷新在进行，等待结果
    if (_tokenRefreshInProgress != null) {
      return _tokenRefreshInProgress!.future;
    }

    _tokenRefreshInProgress = Completer<String?>();
    try {
      final refreshed = await const SunlandAuthApi().refreshToken(token);
      if (refreshed == null) {
        await _sessionStore.clearSession();
        _authToken = null;
        if (notify) currentUserNotifier.value = null;
        _tokenRefreshInProgress!.complete(null);
        return null;
      }
      token = refreshed.token;
      try {
        await _sessionStore.saveSession(token: token, user: refreshed.user);
      } catch (e) {
        debugPrint('Failed to save session during token refresh: $e');
        rethrow;
      }
      // 只有在saveSession成功后才更新内存状态
      _authToken = token;
      if (notify) {
        currentUserNotifier.value = _buildSupabaseUser(refreshed.user);
      }
      _tokenRefreshInProgress!.complete(token);
      return token;
    } catch (e) {
      debugPrint('Token refresh failed: $e');
      // 对于临时错误（网络），不清除session，让下次重试
      // 对于permanent错误（401），才登出
      if (e.toString().contains('401') || e.toString().contains('Unauthorized')) {
        await _sessionStore.clearSession();
        if (notify) currentUserNotifier.value = null;
      }
      _tokenRefreshInProgress!.completeError(e);
      rethrow;
    } finally {
      _tokenRefreshInProgress = null;
    }
  }

  _authToken = token;
  return token;
}

/// 全局主题选择弹框，避免三处重复定义
Future<void> showThemeSelectionDialog(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (!context.mounted) return;
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
}

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
            theme: ThemeData(
              brightness: Brightness.light,
              scaffoldBackgroundColor: const Color(0xFFF6F8FC),
              cardColor: Colors.white,
              dividerColor: Colors.black12,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: Colors.black87,
              ),
              textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 15)),
            ),
            darkTheme: ThemeData(
              brightness: Brightness.dark,
              scaffoldBackgroundColor: const Color(0xFF0B0F1A),
              cardColor: const Color(0xFF111827),
              dividerColor: Colors.white12,
              appBarTheme: const AppBarTheme(
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: Colors.white,
              ),
              textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 15)),
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
    final token = await _readFreshAuthToken(notify: false);
    final user = await _sessionStore.readUser();

    if (!mounted) return;

    SunlandUser? updatedUser = user;
    if (token != null && user != null) {
      _authToken = token;

      // ⭐ 每次启动重新拉取头像/用户信息
      try {
        final repo = SupabaseAiRepository();
        final profile = await repo.loadProfile(user.id);

        if (!mounted) return;

        if (profile != null) {
          final updated = SunlandUser(
            id: user.id,
            email: user.email,
            avatarUrl: profile.avatarUrl ?? user.avatarUrl,
            avatarPath: user.avatarPath,
          );
          updatedUser = updated;
        }
      } catch (e) {
        debugPrint('fetch profile failed: $e');
      }

      if (updatedUser != null) {
        currentUserNotifier.value = _buildSupabaseUser(updatedUser);
      }
    }

    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    final chosen = prefs.getBool('theme_chosen') ?? false;

    // ⭐ 确保 UI 刷新
    currentUserNotifier.notifyListeners();

    if (!chosen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showThemeDialog();
      });
    }
  }

  void _showThemeDialog() {
    showThemeSelectionDialog(context);
  }

  @override
  Widget build(BuildContext context) {
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
  late Animation<double> _opacity;
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

    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

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
        child: FadeTransition(
          opacity: _opacity,
          child: ScaleTransition(
            scale: _scale,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.95, end: 1.0),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(scale: value, child: child);
              },
              child: Image.asset('assets/ailogo.png', width: 120),
            ),
          ),
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

  final emailController = TextEditingController();
  final codeController = TextEditingController();
  final FocusNode emailFocus = FocusNode();
  final FocusNode codeFocus = FocusNode();

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
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const CaptchaPage()),
    );

    if (!mounted) return;
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
      if (!mounted) return;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ 请先勾选用户协议与隐私政策"),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => verifying = true);

    try {
      final result = await api.verifyCode(
        email: email,
        code: code,
        captchaToken: '',
      );

      // ✅ 先保存到存储，再更新内存状态（确保原子性）
      try {
        await _sessionStore.saveSession(token: result.token, user: result.user);
      } catch (e) {
        debugPrint('Session save failed: $e');
        throw Exception('登录数据保存失败，请重试');
      }

      // ✅ 只有存储成功才更新内存
      _authToken = result.token;

      // ✅ 更新全局用户状态
      if (mounted) {
        currentUserNotifier.value = _buildSupabaseUser(result.user);
      }

      // ⭐ 自动创建 profile（关键）
      if (mounted) {
        final repo = SupabaseAiRepository();
        try {
          await repo.ensureProfile(result.user.id);
        } catch (e) {
          debugPrint('Failed to create user profile: $e');
          // 视为关键错误，回滚登录状态
          await _sessionStore.clearSession();
          _authToken = null;
          if (mounted) {
            currentUserNotifier.value = null;
          }
          rethrow;  // 让UI显示登录失败
        }
      }

      // ✅ 清空输入
      emailController.clear();
      codeController.clear();

      if (!mounted) return;

      // ✅ 主动跳转（关键！）
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const SplashPage()),
      );
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
    api.close();
    emailController.dispose();
    codeController.dispose();
    emailFocus.dispose();
    codeFocus.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0B0F1A), Color(0xFF020617)]
                : const [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              left: -80,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF22D3EE).withOpacity(0.2),
                ),
              ),
            ),
            Positioned(
              bottom: -120,
              right: -80,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF6366F1).withOpacity(0.2),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  0,
                  24,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: AnimatedScale(
                      scale: 1,
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      child: AnimatedOpacity(
                        opacity: 1,
                        duration: const Duration(milliseconds: 500),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // --- Header Section ---
                            Column(
                              children: [
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.8, end: 1.0),
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.easeOutBack,
                                  builder: (_, value, child) {
                                    return Transform.scale(
                                      scale: value,
                                      child: child,
                                    );
                                  },
                                  child: Image.asset(
                                    'assets/ailogo.png',
                                    width: 90,
                                  ),
                                ),
                                const SizedBox(height: 32),

                                Text(
                                  "霜蓝 AI",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),

                                const SizedBox(height: 6),

                                Text(
                                  "你的专属智能助手 ✨",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                    fontSize: 14,
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Text(
                                  "登录后即可开始对话、创作与探索",
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 30),

                            // --- 输入框卡片背景 ---
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.06)
                                    : Colors.white.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.08)
                                      : Colors.black.withOpacity(0.05),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(
                                      isDark ? 0.4 : 0.08,
                                    ),
                                    blurRadius: 30,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 16,
                                      sigmaY: 16,
                                    ),
                                    child: Column(
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                            border: Border.all(
                                              color: emailFocus.hasFocus
                                                  ? const Color(0xFF22D3EE)
                                                  : Colors.transparent,
                                              width: 1.6,
                                            ),
                                          ),
                                          child: TextField(
                                            focusNode: emailFocus,
                                            controller: emailController,
                                            onChanged: (_) => setState(() {}),
                                            style: TextStyle(
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: "邮箱",
                                              hintStyle: TextStyle(
                                                color: isDark
                                                    ? Colors.white38
                                                    : Colors.black38,
                                              ),
                                              border: InputBorder.none,
                                            ),
                                          ),
                                        ),

                                        Divider(
                                          color: isDark
                                              ? Colors.white12
                                              : Colors.black12,
                                        ),

                                        Row(
                                          children: [
                                            Expanded(
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                  milliseconds: 200,
                                                ),
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: codeFocus.hasFocus
                                                        ? const Color(
                                                            0xFF6366F1,
                                                          )
                                                        : Colors.transparent,
                                                    width: 1.6,
                                                  ),
                                                ),
                                                child: TextField(
                                                  focusNode: codeFocus,
                                                  controller: codeController,
                                                  onChanged: (_) =>
                                                      setState(() {}),
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
                                            ),
                                            TextButton(
                                              onPressed:
                                                  (sending || countdown > 0)
                                                  ? null
                                                  : sendCode,
                                              child: Text(
                                                sending
                                                    ? "发送中..."
                                                    : countdown > 0
                                                    ? "${countdown}s"
                                                    : "发送",
                                                style: TextStyle(
                                                  color:
                                                      (sending || countdown > 0)
                                                      ? (isDark
                                                            ? Colors.white38
                                                            : Colors.black38)
                                                      : const Color(0xFF22D3EE),
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            const SizedBox(height: 24),

                            // --- 登录按钮增强（渐变） ---
                            AnimatedBuilder(
                              animation: _animController,
                              builder: (_, child) {
                                final scale = 1 + (0.03 * (1 - _fade.value));
                                return Transform.scale(
                                  scale: canLogin ? scale : 0.97,
                                  child: child,
                                );
                              },
                              child: Container(
                                width: double.infinity,
                                height: 48,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF22D3EE),
                                      Color(0xFF6366F1),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFF22D3EE,
                                      ).withOpacity(0.4),
                                      blurRadius: 18,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    splashColor: Colors.white.withOpacity(0.25),
                                    onTap: canLogin ? login : null,
                                    child: Center(
                                      child: verifying
                                          ? Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                          Color
                                                        >(Colors.white),
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                const Text(
                                                  "加载中...",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : const Text(
                                              "登录",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1,
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
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
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          },
                                          child: const Text(
                                            "用户协议",
                                            style: TextStyle(
                                              color: Color(0xFF22D3EE),
                                              fontSize: 11,
                                              decoration:
                                                  TextDecoration.underline,
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
                                              Uri.parse(
                                                "https://sunland.dev/privacy",
                                              ),
                                              mode: LaunchMode
                                                  .externalApplication,
                                            );
                                          },
                                          child: const Text(
                                            "隐私政策",
                                            style: TextStyle(
                                              color: Color(0xFF22D3EE),
                                              fontSize: 11,
                                              decoration:
                                                  TextDecoration.underline,
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
            ),
          ],
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
  // Normalize messages: combine "reasoning" + next assistant message into one
  List<Map<String, dynamic>> normalizeMessages(
    List<Map<String, dynamic>> msgs,
  ) {
    final result = <Map<String, dynamic>>[];

    for (int i = 0; i < msgs.length; i++) {
      final msg = msgs[i];

      if (msg["isReasoning"] == true && i + 1 < msgs.length) {
        final next = msgs[i + 1];

        if (next["isUser"] == false) {
          result.add({
            "text": next["text"],
            "reasoning": msg["text"],
            "isUser": false,
          });
          i++;
          continue;
        }
      }

      result.add(msg);
    }

    return result;
  }

  String _searchKeyword = "";

  bool _isThinkingPhase(Map<String, dynamic> msg) {
    final text = (msg['text'] ?? '').toString();
    if (text == '思考中...' || text == '深度思考中...') return true;
    return text.trim().isEmpty;
  }

  Widget _stoppedHintWidget(Map<String, dynamic> msg, bool isDark) {
    final hint = (msg['stoppedHint'] ?? '').toString();
    if (hint.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        hint,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white38 : Colors.grey,
        ),
      ),
    );
  }

  void cancelGeneration() {
    if (!isGenerating) return;

    // ✅ 直接取消stream，防止幽灵请求
    _currentStreamSubscription?.cancel();
    _currentStreamSubscription = null;

    _cancelRequested = true;
    _generationSerial++;

    setState(() {
      isGenerating = false;
      if (messages.isNotEmpty && messages.last['isUser'] != true) {
        final last = messages.last;
        final isThinking = _isThinkingPhase(last);
        if (last['text'] == '思考中...' || last['text'] == '深度思考中...') {
          last['text'] = '';
        }
        last['isStreaming'] = false;
        last['stoppedHint'] = isThinking ? '已停止思考' : '已停止回答';
      }
    });
    rememberLocalMessages();
  }

  void _showThemeDialogInChat() {
    showThemeSelectionDialog(context);
  }

  Widget buildMessageContent(
    Map<String, dynamic> msg,
    bool isUser,
    bool isDark,
  ) {
    if (isUser) {
      final imagePaths = msg['imagePaths'];
      final paths = imagePaths is List
          ? imagePaths.map((e) => e.toString()).where((p) => p.isNotEmpty).toList()
          : <String>[];
      final displayText = (msg['text'] ?? '').toString();

      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF22D3EE).withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (paths.isNotEmpty)
                  SizedBox(
                    height: 64,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      shrinkWrap: true,
                      itemCount: paths.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, index) {
                        final path = paths[index];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 64,
                              height: 64,
                              child: Icon(Icons.broken_image, size: 20),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                if (paths.isNotEmpty && displayText.isNotEmpty)
                  const SizedBox(height: 8),
                if (displayText.isNotEmpty)
                  Text(
                    displayText,
                    style: const TextStyle(fontSize: 14, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (msg["text"] == "思考中..." || msg["text"] == "深度思考中...") {
      final isDeep = msg["text"] == "深度思考中...";
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDeep
                ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE0F2FE))
                : (isDark
                      ? const Color(0xFF111827).withOpacity(0.6)
                      : Colors.white.withOpacity(0.6)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🌟 呼吸动画 Logo（去掉旋转，只保留呼吸效果）
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.8, end: 1.2),
                duration: const Duration(milliseconds: 1200),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(opacity: 0.7 + (value - 0.8), child: child),
                  );
                },
                onEnd: () {
                  if (mounted) setState(() {});
                },
                child: Image.asset('assets/ailogo.png', width: 40, height: 40),
              ),
              const SizedBox(width: 10),
              // ✨ 动态思考文字（波浪感）
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: 3),
                duration: const Duration(milliseconds: 900),
                builder: (context, value, child) {
                  final dots = '.' * value;
                  return Row(
                    children: [
                      Text(
                        isDeep ? "深度思考中" : "思考中",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isDeep
                              ? FontWeight.w500
                              : FontWeight.normal,
                          color: isDeep
                              ? const Color(0xFF22D3EE)
                              : (isDark ? Colors.white70 : Colors.black54),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: value == 0 ? 0.2 : 1,
                        duration: const Duration(milliseconds: 300),
                        child: Text(
                          dots,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        "加载中",
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  );
                },
                onEnd: () {
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(0, 8, 0, 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.06),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Builder(
            builder: (_) {
              var text = (msg["text"] ?? "").toString();
              var reasoning = (msg["reasoning"] ?? "").toString();

              if (reasoning.isEmpty && text.startsWith("🧠 ")) {
                final parts = text.split("\n\n");
                reasoning = parts.first.replaceFirst("🧠 ", "");
                text = parts.length > 1 ? parts.sublist(1).join("\n\n") : "";
              }

              if (reasoning.trim().isNotEmpty) {
                final content = text;

                bool expanded = msg["expanded"] == true;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🧠 折叠卡片（带状态持久）
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          msg["expanded"] = !expanded;
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.black.withOpacity(0.04),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              expanded
                                  ? Icons.keyboard_arrow_down
                                  : Icons.keyboard_arrow_right,
                              size: 16,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "思考过程",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 150),
                            child: SingleChildScrollView(
                              physics: expanded
                                  ? const BouncingScrollPhysics()
                                  : const NeverScrollableScrollPhysics(),
                              child: Text(
                                reasoning,
                                maxLines: expanded ? null : 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (content.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      MarkdownBody(data: content),
                    ],
                    _stoppedHintWidget(msg, isDark),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (text.isNotEmpty) MarkdownBody(data: text),
                  _stoppedHintWidget(msg, isDark),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  late final SunlandApiClient apiClient;
  late final SupabaseAiRepository repo;
  late final SunlandSessionStore store;
  final supabase = Supabase.instance.client;
  bool useReasoner = false;
  String currentModel = 'deepseek-v4-flash';
  bool useDeep = false;
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
  int _generationSerial = 0;
  StreamSubscription<AiResponse>? _currentStreamSubscription;
  List<String> pickedImages = [];
  bool _ocrPrivacyTipShown = false;
  bool isUploadingAvatar = false;

  bool isLocalConversation(String? id) => id?.startsWith('local_') ?? false;

  Map<String, dynamic> _messageToCloud(Map<String, dynamic> message) {
    final rawText = (message['apiContent'] ?? message['text'] ?? '').toString();
    var content = rawText;
    var reasoning = (message['reasoning'] ?? '').toString().trim();
    if (rawText.startsWith('🧠 ')) {
      final parts = rawText.split('\n\n');
      reasoning = parts.first.replaceFirst('🧠 ', '').trim();
      content = parts.length > 1 ? parts.sublist(1).join('\n\n') : '';
    }

    return {
      'role': message['isUser'] == true ? 'user' : 'assistant',
      'content': content.trim(),
      if (reasoning.isNotEmpty) 'reasoning': reasoning,
    };
  }

  Map<String, dynamic> _messageFromCloud(Map message) {
    final role = message['role']?.toString() ?? 'assistant';
    final content = (message['content'] ?? '').toString();
    final reasoning = (message['reasoning'] ?? message['reasoning_content'])
        ?.toString()
        .trim();
    return {
      'text': content,
      if (reasoning != null && reasoning.isNotEmpty) 'reasoning': reasoning,
      'isUser': role == 'user',
      'expanded': false,
    };
  }

  List<Conversation> _buildConversationModels() {
    return conversations
        .where((convo) => !isLocalConversation(convo['id']?.toString()))
        .map((convo) {
          final id = convo['id']?.toString() ?? '';
          final msgs = localConversationMessages[id] ?? [];
          return Conversation(
            id: id,
            title: (convo['title'] ?? '新对话').toString(),
            history: [
              const ChatMessage(role: 'system', content: sunlandSystemPrompt),
              ...msgs.map(
                (message) => ChatMessage.fromJson(_messageToCloud(message)),
              ),
            ],
            updatedAt:
                int.tryParse((convo['updatedAt'] ?? '').toString()) ??
                DateTime.now().millisecondsSinceEpoch,
            autoTitle: convo['titleGenerated'] ?? false,
          );
        })
        .where((convo) => convo.id.isNotEmpty)
        .toList();
  }

  void _applyConversationModels(List<Conversation> models) {
    final convos = <Map<String, dynamic>>[];
    localConversationMessages.clear();

    for (final item in models) {
      convos.add({
        'id': item.id,
        'title': item.title,
        'updatedAt': item.updatedAt,
        'titleGenerated': item.autoTitle ?? false,
      });
      localConversationMessages[item.id] = item.history
          .where((message) => !message.isSystem)
          .map((message) => _messageFromCloud(message.toJson()))
          .toList();
    }

    conversations = convos;
  }

  void rememberLocalMessages() {
    final id = currentConversationId;
    if (id == null) return;
    // ✅ 限制单对话消息数，防止无限增长
    final limited = messages.length > 100
        ? messages.sublist(messages.length - 100)
        : messages;
    localConversationMessages[id] = limited
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    // 限制缓存对话数量，防止内存增长
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

    try {
      final cached = await store.readConversations(user.id);
      if (cached.isNotEmpty && mounted) {
        setState(() => _applyConversationModels(cached));
      }

      final data = await supabase
          .from('conversations')
          .select('data')
          .eq('user_id', user.id)
          .maybeSingle();

      if (data == null || data['data'] == null) {
        if (cached.isEmpty && mounted) {
          setState(() => conversations = []);
        }
        return;
      }

      final rawList = data['data'] as List;
      final cloudModels = conversationsFromCloudRows(rawList);
      final merged = mergeConversations(cached, cloudModels);
      await store.saveConversations(user.id, merged);
      if (!mounted) return;
      setState(() => _applyConversationModels(merged));
    } catch (e) {
      debugPrint('loadConversations error: $e');
    }
  }

  Future<void> _saveToCloud() async {
    final user = currentUserNotifier.value;
    if (user == null) return;

    try {
      final models = _buildConversationModels();

      // ✅ 改为基于时间戳的CRDT合并
      final existing = await supabase
          .from('conversations')
          .select('data')
          .eq('user_id', user.id)
          .maybeSingle();

      final merged = <String, Map<String, dynamic>>{};

      // 先加载云端数据
      if (existing?['data'] is List) {
        for (final item in existing!['data'] as List) {
          if (item is Map && item['id'] != null) {
            merged[item['id'].toString()] = Map<String, dynamic>.from(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
        }
      }

      // 再用本地数据（只有时间戳更新的才覆盖）
      for (final model in models) {
        final cloudVersion = merged[model.id];
        if (cloudVersion == null ||
            model.updatedAt > (switch (cloudVersion['updatedAt']) {
              final int v => v,
              final double v => v.toInt(),
              final String v => int.tryParse(v) ?? 0,
              _ => 0,
            })) {
          merged[model.id] = {
            'id': model.id,
            'title': model.title,
            'history': model.history.map((m) => m.toJson()).toList(),
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          };
        }
      }

      // ✅ 保存合并后的结果
      await supabase.from('conversations').upsert({
        'user_id': user.id,
        'data': merged.values.toList(),
      }, onConflict: 'user_id');

      // 同步本地缓存
      final mergedModels =
          merged.values.map((json) => Conversation.fromJson(json)).toList()
            ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await store.saveConversations(user.id, mergedModels);
    } catch (e) {
      debugPrint('_saveToCloud error: $e');
    }
  }

  Future<void> deleteConversation(String id) async {
    final user = currentUserNotifier.value;

    setState(() {
      conversations.removeWhere((c) => c['id'] == id);
      localConversationMessages.remove(id);

      if (currentConversationId == id) {
        currentConversationId = null;
        messages.clear();
      }
    });

    // ⭐ 同步到云端
    if (user != null) {
      await _saveToCloud();
    }
  }

  @override
  void initState() {
    super.initState();
    apiClient = SunlandApiClient(tokenProvider: _readFreshAuthToken);
    repo = SupabaseAiRepository();
    store = SunlandSessionStore();
    _initData();
    unawaited(_loadOcrPrivacyTipFlag());
  }

  Future<void> _loadOcrPrivacyTipFlag() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ocrPrivacyTipShown = prefs.getBool('ocr_privacy_tip_shown') ?? false;
    });
  }

  Future<void> _initData() async {
    final user = currentUserNotifier.value;
    if (user == null) return;
    await repo.ensureProfile(user.id); // ⭐ 再保险一层
    await loadConversations();
    await _checkActivation();

    if (!mounted) return;

    if (conversations.isNotEmpty) {
      final convo = conversations.first;
      currentConversationId = convo["id"];
      setState(() {
        messages = normalizeMessages(
          List<Map<String, dynamic>>.from(
            localConversationMessages[currentConversationId] ?? [],
          ),
        );
      });
    }
    await _loadModelPrefs();
    if (!mounted) return;
    await UpdateService.check(context);
    // (profile setup dialog auto-popup removed)
  }

  Future<void> _loadModelPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final savedModel = prefs.getString('currentModel');
    final savedDeep = prefs.getBool('useDeep');
    if (mounted) {
      setState(() {
        if (savedModel != null && savedModel.isNotEmpty) {
          currentModel = savedModel;
        }
        if (savedDeep != null) {
          useDeep = savedDeep;
        }
        if (!isActivated) {
          currentModel = 'deepseek-v4-flash';
          useDeep = false;
        }
      });
    }
  }

  Future<void> _saveModelPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currentModel', currentModel);
    await prefs.setBool('useDeep', useDeep);
  }

  String _resolveModel() {
    // Pro 权限校验：非 Pro 用户强制 flash
    if (!isActivated) return 'deepseek-v4-flash';

    // 深度思考模式强制 pro
    if (useDeep) return 'deepseek-v4-pro';

    return currentModel;
  }

  Future<void> _checkActivation() async {
    final user = currentUserNotifier.value;
    if (user == null) return;

    try {
      final activated = await repo.isActivated(user.id);
      final remainingCount = await store.readRemainingCount(user.id);
      if (mounted) {
        setState(() {
          isActivated = activated;
          _remainingCount = activated ? freeDailyLimit : remainingCount;
          if (!activated) {
            currentModel = 'deepseek-v4-flash';
            useDeep = false;
          }
        });
      }
    } catch (e) {
      debugPrint('_checkActivation error: $e');
    }
  }

  Future<void> sendMessage() async {
    if (isGenerating) return; // prevent concurrent triggers early
    if (_cancelRequested) {
      // Still cleaning up from a cancel; give brief feedback rather than silently swallowing the tap
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('请稍等…'),
            duration: Duration(milliseconds: 600),
          ),
        );
      }
      return;
    }
    // ⭐ 优先拦截 Pro 权限（避免被当成免费额度用尽）
    if (!isActivated && (currentModel == 'deepseek-v4-pro' || useDeep)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠️ Pro 功能需要激活后才能使用"),
            duration: Duration(seconds: 2),
          ),
        );
      }
      setState(() => isGenerating = false);
      return;
    }
    setState(() => isGenerating = true); // 立即锁定，防止并发
    _cancelRequested = false;
    final generationId = ++_generationSerial;
    if (mounted) FocusScope.of(context).unfocus();

    // ✅ 新增：免费用户额度检查
    if (!isActivated && _remainingCount <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("今日免费次数已用完，请升级到Pro或明天再试"),
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() => isGenerating = false);
      return;
    }

    final user = currentUserNotifier.value;
    final text = controller.text.trim();
    final hasImages = pickedImages.isNotEmpty;
    if (text.isEmpty && !hasImages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请输入内容")));
      setState(() => isGenerating = false);
      return;
    }
    final isRegenerate = text.isNotEmpty && text == _lastUserText;
    final imagePaths = List<String>.from(pickedImages);

    // ===== 本地 OCR（发送前完成）=====
    ImageOcrResult? ocrResult;
    if (hasImages && supportsLocalImageOcr) {
      if (mounted) {
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const PopScope(
            canPop: false,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('正在识别图片文字…'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      try {
        ocrResult = await extractTextFromImages(imagePaths).timeout(
          const Duration(seconds: 12),
        );
      } on TimeoutException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('图片识别超时，请换清晰图片或补充文字说明'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        setState(() => isGenerating = false);
        return;
      } catch (e) {
        debugPrint('OCR error: $e');
        ocrResult = const ImageOcrResult(block: '', hasUsableText: false);
      } finally {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    }

    if (generationId != _generationSerial) {
      if (mounted) setState(() => isGenerating = false);
      return;
    }

    final ocrBlock =
        ocrResult?.hasUsableText == true ? ocrResult!.block : null;
    final apiContent = buildApiMessageWithOcr(
      userText: text,
      ocrBlock: ocrBlock,
    );

    if (hasImages && !supportsLocalImageOcr && text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '当前平台不支持本地识图，请补充文字说明，或使用移动端发送图片',
            ),
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() => isGenerating = false);
      return;
    }

    if (hasImages &&
        supportsLocalImageOcr &&
        !ocrBlockHasUsableText(ocrBlock) &&
        text.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未识别到图片文字，请换清晰图片或输入文字说明'),
            duration: Duration(seconds: 3),
          ),
        );
      }
      setState(() => isGenerating = false);
      return;
    }

    if (hasImages &&
        supportsLocalImageOcr &&
        ocrResult != null &&
        ocrResult.hasUsableText &&
        ocrBlock != null &&
        mounted) {
      final block = ocrBlock;
      final preview = block.length > 120
          ? '${block.characters.take(120)}…'
          : block;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认识别内容'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  preview,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 12),
                Text(
                  kOcrPrivacyTip,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('发送'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        setState(() => isGenerating = false);
        return;
      }
    }

    if (generationId != _generationSerial) {
      if (mounted) setState(() => isGenerating = false);
      return;
    }

    // ✅ 内容审核（含 OCR 合并后的全文）
    final modResult = InputModerator.check(apiContent);
    if (modResult != null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(InputModerator.refusalText)));
      }
      setState(() => isGenerating = false);
      return;
    }

    // ✅ 记录最后一条用户消息（用于重新生成）
    _lastUserText = text;
    final displayedUserText = text.isNotEmpty
        ? text
        : '已发送 ${imagePaths.length} 张图片';

    setState(() {
      if (!isRegenerate) {
        messages.add({
          "text": displayedUserText,
          "isUser": true,
          if (apiContent.isNotEmpty) "apiContent": apiContent,
          if (imagePaths.isNotEmpty) "imagePaths": List<String>.from(imagePaths),
        });
      }
      final isDeepMode = isActivated && useDeep;
      messages.add({
        "text": isDeepMode ? "深度思考中..." : "思考中...",
        "isUser": false,
        "isStreaming": true,
        "expanded": false,
      });
    });

    // Insert conversation and user message if needed
    rememberLocalMessages(); // ⭐ 防止新建对话前丢失当前内容

    if (currentConversationId == null) {
      final newId = DateTime.now().millisecondsSinceEpoch.toString();
      currentConversationId = newId;
      conversations.insert(0, {
        'id': newId,
        'title': buildConversationTitle(displayedUserText),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'titleGenerated': false,
      });
      localConversationMessages[newId] = [];
    }

    rememberLocalMessages();

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
      setState(() {
        if (messages.isNotEmpty) messages.removeLast();
        messages.add({
          "text": "",
          "reasoning": "",
          "isUser": false,
          "isStreaming": true,
          "expanded": false, // ✅ 保持一致
        });
      });

      String responseContent = "";
      String responseReasoning = "";
      int contentFlushTs = DateTime.now().millisecondsSinceEpoch;
      int reasoningFlushTs = contentFlushTs;
      var pendingFlush = false;
      var streamActive = true;
      var streamTimedOut = false;

      void flushStreamingMessage({bool force = false}) {
        if (!mounted ||
            _cancelRequested ||
            generationId != _generationSerial ||
            messages.isEmpty ||
            (!force && !streamActive)) {
          return;
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        final shouldFlushContent = force || now - contentFlushTs >= 50;
        final shouldFlushReasoning = force || now - reasoningFlushTs >= 90;
        if (!shouldFlushContent && !shouldFlushReasoning) {
          if (!pendingFlush) {
            pendingFlush = true;
            Future<void>.delayed(const Duration(milliseconds: 50), () {
              if (!mounted) return;
              pendingFlush = false;
              flushStreamingMessage();
            });
          }
          return;
        }

        if (shouldFlushContent) contentFlushTs = now;
        if (shouldFlushReasoning) reasoningFlushTs = now;

        setState(() {
          final last = messages.last;
          if (last["isUser"] == true) return;
          last["text"] = responseContent;
          last["reasoning"] = responseReasoning;
          last["isStreaming"] = !force;
        });
      }

      // ===== 自动模型策略 + Pro 权限校验 =====
      String requestModel = _resolveModel();
      if (!isActivated) {
        useDeep = false;
      }

      // 自动策略：长文本/关键词触发 pro（仅 Pro 用户生效）
      if (isActivated && requestModel != 'deepseek-v4-pro') {
        final lower = text.toLowerCase();
        final needsPro =
            text.length > 300 ||
            lower.contains('bug') ||
            lower.contains('报错') ||
            lower.contains('代码') ||
            lower.contains('优化');
        if (needsPro) {
          requestModel = 'deepseek-v4-pro';
        }
      }

      // Pro 降级提示
      if (!isActivated && (currentModel == 'deepseek-v4-pro' || useDeep)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Pro 模型需激活后才能使用，已自动切换为 Flash 模式"),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // ====== Streaming with retry wrapper ======
      Future<void> runStream() {
        responseContent = '';
        responseReasoning = '';
        final completer = Completer<void>();
        _currentStreamSubscription =
            sendSmartChatStream(
                  client: apiClient,
                  rawMessages: messages,
                  model: requestModel,
                  deep: isActivated ? useDeep : false,
                  onRemainUpdated: (remain) {
                    final normalized = remain < 0
                        ? freeDailyLimit
                        : remain.clamp(0, freeDailyLimit).toInt();
                    if (user != null) {
                      unawaited(store.saveRemainingCount(user.id, normalized));
                    }
                    if (!mounted || generationId != _generationSerial) return;
                    setState(() => _remainingCount = normalized);
                  },
                )
                .timeout(
                  const Duration(seconds: 30),
                  onTimeout: (sink) {
                    streamTimedOut = true;
                    sink.close();
                  },
                )
                .listen(
                  (chunk) {
                    if (_cancelRequested || generationId != _generationSerial) {
                      _currentStreamSubscription?.cancel();
                      _currentStreamSubscription = null;
                      if (!completer.isCompleted) completer.complete();
                      return;
                    }

                    responseContent = chunk.content;
                    if (useDeep &&
                        chunk.reasoning != null &&
                        chunk.reasoning!.isNotEmpty) {
                      responseReasoning = chunk.reasoning!;
                    }
                    flushStreamingMessage();
                    scrollToBottom();
                  },
                  onError: (e) {
                    _currentStreamSubscription?.cancel();
                    _currentStreamSubscription = null;
                    if (!completer.isCompleted) completer.completeError(e);
                  },
                  onDone: () {
                    _currentStreamSubscription = null;
                    if (!completer.isCompleted) completer.complete();
                  },
                  cancelOnError: true,
                );
        return completer.future;
      }

      try {
        await runStream();
      } catch (e) {
        if (e is AuthExpiredException ||
            e is UsageLimitException ||
            e is ApiException) {
          rethrow;
        }
        // retry once
        if (_cancelRequested || generationId != _generationSerial) return;
        await Future.delayed(const Duration(milliseconds: 800));
        await runStream();
      }

      streamActive = false;
      if (_cancelRequested || generationId != _generationSerial) {
        return;
      }
      if (streamTimedOut) {
        throw const ApiException('请求超时，请重试');
      }
      flushStreamingMessage(force: true);
      await Future.delayed(const Duration(milliseconds: 30));
      flushStreamingMessage(force: true); // ensure last chunk flushed

      // ⭐ 图片发送完成后安全清空
      if (pickedImages.isNotEmpty) {
        setState(() => pickedImages.clear());
      }

      final activeIndex = conversations.indexWhere(
        (c) => c['id'] == currentConversationId,
      );
      if (activeIndex != -1) {
        conversations[activeIndex]['updatedAt'] =
            DateTime.now().millisecondsSinceEpoch;
      }

      rememberLocalMessages();
      if (user != null) await _saveToCloud();

      setState(() {
        isGenerating = false;
      });

      // ⭐ AI 自动生成对话标题（仅第一次）
      try {
        final convoId = currentConversationId;
        if (convoId != null) {
          final index = conversations.indexWhere((c) => c['id'] == convoId);
          if (index != -1) {
            final titleGenerated =
                conversations[index]['titleGenerated'] ?? false;
            final userMsgCount = messages
                .where((m) => m["isUser"] == true)
                .length;
            if (userMsgCount == 1 && !titleGenerated) {
              setState(() {
                conversations[index]['title'] = buildConversationTitle(
                  displayedUserText,
                );
                conversations[index]['titleGenerated'] = true;
              });
              if (user != null) unawaited(_saveToCloud());
            }
          }
        }
      } catch (_) {
        // 忽略标题生成失败
      }
      scrollToBottom();
    } catch (e) {
      if (e is AuthExpiredException) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Auth过期: $e"),
              duration: const Duration(seconds: 10),
            ),
          );
        }
        setState(() => isGenerating = false);
        return;
      }

      if (e is UsageLimitException) {
        final normalized = e.remain.clamp(0, freeDailyLimit).toInt();
        if (user != null) {
          unawaited(store.saveRemainingCount(user.id, normalized));
        }
        setState(() {
          _remainingCount = normalized;
          isGenerating = false;
        });
        if (mounted) {
          _showLimitSheet();
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e.toString().contains("timeout")
                  ? "请求超时了，稍后再试一下 ⏳"
                  : e.toString().contains("SocketException")
                  ? "网络好像断了，检查一下连接 🌐"
                  : "请求失败了，试试重新发送",
            ),
            duration: const Duration(seconds: 4),
          ),
        );
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
      if (mounted) {
        setState(() {
          // 防止"思考中..."卡住（用户主动停止时跳过）
          if (!_cancelRequested &&
              messages.isNotEmpty &&
              (messages.last["text"] == "思考中..." ||
                  messages.last["text"] == "深度思考中...")) {
            messages.removeLast();
            messages.add({"text": "请求超时或失败，请重试", "isUser": false});
          }
          isGenerating = false;
          _cancelRequested = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _currentStreamSubscription?.cancel();
    apiClient.close();
    controller.dispose();
    scrollController.dispose();
    super.dispose();
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      final max = scrollController.position.maxScrollExtent;
      final current = scrollController.offset;

      // only auto-scroll if near bottom
      if (max - current < 120) {
        scrollController.animateTo(
          max,
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

  Future<void> _markOcrPrivacyTipShown() async {
    if (_ocrPrivacyTipShown) return;
    _ocrPrivacyTipShown = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('ocr_privacy_tip_shown', true);
  }

  Future<void> pickImage() async {
    if (!_ocrPrivacyTipShown && mounted) {
      await _markOcrPrivacyTipShown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(kOcrPrivacyTip),
          duration: Duration(seconds: 4),
        ),
      );
    }

    // 📱 移动端：使用 image_picker
    if (Platform.isAndroid || Platform.isIOS) {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage();

      if (picked.isEmpty) return;

      setState(() {
        for (var img in picked) {
          if (pickedImages.length < 4) {
            pickedImages.add(img.path);
          }
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
          if (pickedImages.length < 4) {
            pickedImages.add(file.path!);
          }
        }
      }
    });
  }

  Future<void> pickAndUploadAvatar() async {
    final user = currentUserNotifier.value;
    if (user == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (picked == null) return;

    final file = File(picked.path);

    // ⭐ 预览 + 确认弹窗
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("预览头像"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(radius: 40, backgroundImage: FileImage(file)),
              const SizedBox(height: 12),
              const Text("确认使用这张图片作为头像？"),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("取消"),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("确认"),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;
    if (!mounted) return;

    setState(() {
      isUploadingAvatar = true;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("头像上传中...")));

    final fileName = '${user.id}.png';

    try {
      await supabase.storage
          .from('avatars')
          .upload(fileName, file, fileOptions: const FileOptions(upsert: true));

      final publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName);

      final current = currentUserNotifier.value;
      if (current != null) {
        final updated = User.fromJson({
          "id": current.id,
          "email": current.email,
          "aud": "authenticated",
          "created_at": current.createdAt,
          "app_metadata": <String, dynamic>{},
          "user_metadata": {
            if (current.userMetadata?["name"] != null)
              "name": current.userMetadata?["name"],
            "avatar_url": publicUrl,
          },
        });

        currentUserNotifier.value = updated;
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("头像更新成功")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("上传失败: $e")));
    } finally {
      if (mounted) {
        setState(() {
          isUploadingAvatar = false;
        });
      }
    }
  }

  Future<void> _openSettings({bool openActivation = false}) async {
    final result = await Navigator.push<SettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsPage(openActivationOnStart: openActivation),
      ),
    );

    if (!mounted) return;
    if (result?.loggedOut == true || currentUserNotifier.value == null) {
      _authToken = null;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const RootPage()),
        (_) => false,
      );
      return;
    }

    await _checkActivation();
    await loadConversations();
    if (mounted) setState(() {});
  }

  void _showLimitSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22D3EE).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.workspace_premium,
                        color: Color(0xFF0891B2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "今日免费次数已用完",
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  "免费用户每天 20 次。升级 Pro 后可永久无限使用，并解锁 DeepSeek V4 Pro 与深度思考。",
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.black54,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _openSettings(openActivation: true);
                        },
                        child: const Text("输入激活码"),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _openSettings(openActivation: true);
                        },
                        child: const Text("升级 Pro"),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _modelItem({
    required String name,
    bool selected = false,
    bool locked = false,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF22D3EE).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Image.asset(
              'assets/deepseek.png',
              width: 18,
              height: 18,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "DeepSeek $name",
                  style: TextStyle(
                    fontSize: 13,
                    color: locked ? Colors.grey : null,
                  ),
                ),
                Text(
                  name == "Pro" ? "更强推理能力" : "更快响应速度",
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const Spacer(),
            if (locked)
              const Icon(Icons.lock, size: 14, color: Colors.grey)
            else if (selected)
              const Icon(Icons.check, size: 14),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      onDrawerChanged: (isOpened) {
        if (isOpened) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      drawer: Drawer(
        backgroundColor: isDark ? const Color(0xFF0F0F0F) : Colors.white,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- Richer header card ---
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF111827)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Image.asset('assets/ailogo.png', width: 52, height: 52),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "霜蓝 AI",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "你的智能助手",
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black45,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // --- Search TextField ---
                TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchKeyword = value.toLowerCase();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: "搜索对话",
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchKeyword.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              setState(() {
                                _searchKeyword = "";
                              });
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF111827)
                        : Colors.grey.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                GestureDetector(
                  onTap: () {
                    // ✅ 如果已经是新对话（没有ID + 没消息）就不创建
                    if (currentConversationId == null && messages.isEmpty) {
                      Navigator.pop(context);
                      return;
                    }

                    Navigator.pop(context);

                    setState(() {
                      final newId = DateTime.now().millisecondsSinceEpoch
                          .toString();

                      currentConversationId = newId;

                      conversations.insert(0, {
                        'id': newId,
                        'title': '新对话',
                        'updatedAt': DateTime.now().millisecondsSinceEpoch,
                      });

                      messages.clear();
                      localConversationMessages[newId] = [];
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF22D3EE), Color(0xFF3B82F6)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        "新建对话",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                Expanded(
                  child: Builder(
                    builder: (context) {
                      final filteredConversations = conversations.where((c) {
                        if (_searchKeyword.isEmpty) return true;
                        final title = (c['title'] ?? '')
                            .toString()
                            .toLowerCase();
                        return title.contains(_searchKeyword);
                      }).toList();
                      if (filteredConversations.isEmpty) {
                        return Center(
                          child: Text(
                            "没有找到相关对话",
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: filteredConversations.length,
                        itemBuilder: (context, index) {
                          final convo = filteredConversations[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(
                              color: currentConversationId == convo['id']
                                  ? const Color(
                                      0xFF22D3EE,
                                    ).withOpacity(isDark ? 0.25 : 0.18)
                                  : (isDark
                                        ? const Color(0xFF111827)
                                        : Colors.grey.withOpacity(0.08)),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child:
                                (convo['title'] == '新对话' ||
                                    (localConversationMessages[convo['id']]
                                            ?.isEmpty ??
                                        true))
                                ? ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    title: Text(
                                      convo['title'] ?? '新对话',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight:
                                            currentConversationId == convo['id']
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    leading: Icon(
                                      Icons.chat_bubble_outline,
                                      size: 18,
                                      color:
                                          currentConversationId == convo['id']
                                          ? const Color(0xFF22D3EE)
                                          : null,
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      if (currentConversationId !=
                                          convo['id']) {
                                        rememberLocalMessages();
                                        setState(() {
                                          currentConversationId = convo['id'];
                                          messages = normalizeMessages(
                                            List<Map<String, dynamic>>.from(
                                              localConversationMessages[currentConversationId] ??
                                                  [],
                                            ),
                                          );
                                        });
                                      }
                                    },
                                  )
                                : Dismissible(
                                    key: ValueKey(convo['id']),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(
                                        right: 16,
                                        top: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.delete,
                                        color: Colors.white,
                                      ),
                                    ),
                                    onDismissed: (_) {
                                      deleteConversation(convo['id']);
                                    },
                                    child: ListTile(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      title: Text(
                                        convo['title'] ?? '新对话',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontWeight:
                                              currentConversationId ==
                                                  convo['id']
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                      leading: Icon(
                                        Icons.chat_bubble_outline,
                                        size: 18,
                                        color:
                                            currentConversationId == convo['id']
                                            ? const Color(0xFF22D3EE)
                                            : null,
                                      ),
                                      onTap: () {
                                        Navigator.pop(context);
                                        if (currentConversationId !=
                                            convo['id']) {
                                          rememberLocalMessages();
                                          setState(() {
                                            currentConversationId = convo['id'];
                                            messages = normalizeMessages(
                                              List<Map<String, dynamic>>.from(
                                                localConversationMessages[currentConversationId] ??
                                                    [],
                                              ),
                                            );
                                          });
                                        }
                                      },
                                    ),
                                  ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.transparent,
      resizeToAvoidBottomInset: true,
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
                FocusScope.of(context).unfocus(); // ⭐ 关闭键盘
                Scaffold.of(context).openDrawer();
              },
            );
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：标题 + 用户
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "霜蓝AI",
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isActivated)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: () => _openSettings(openActivation: true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: const Color(0xFF7C3AED),
                        backgroundColor: const Color(
                          0xFF7C3AED,
                        ).withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      icon: const Icon(Icons.diamond_outlined, size: 14),
                      label: const Text(
                        "Pro",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                // 用户头像
                Builder(
                  builder: (_) {
                    final user = currentUserNotifier.value;
                    return GestureDetector(
                      onTap: _openSettings,
                      child: CircleAvatar(
                        radius: 17,
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
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 第二行：状态信息
            Text(
              !isActivated ? "今日剩余 $_remainingCount 次" : "💎 Pro · 无限使用",
              style: TextStyle(
                fontSize: 11,
                color: !isActivated
                    ? (isDark ? Colors.white54 : Colors.black45)
                    : const Color(0xFF22D3EE),
              ),
            ),
            const SizedBox(height: 6),
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
                      ? const [Color(0xFF0B0F1A), Color(0xFF0F172A)]
                      : const [Color(0xFFF8FAFF), Color(0xFFEAF2FF)],
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
                      // Increased bottom padding to prevent input overlap
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final isUser = msg["isUser"] == true;
                        return KeyedSubtree(
                          key: ValueKey(
                            i.toString() +
                                (msg["isReasoning"] == true ? "_r" : "_n"),
                          ),
                          child: AnimatedSlide(
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
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 6,
                                  ),
                                  alignment: isUser
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
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
                // 输入区（上下两层）
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0F172A).withOpacity(0.92)
                                : Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : Colors.black.withOpacity(0.08),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 40,
                                offset: const Offset(0, -5),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // ===== ① 图片预览区 =====
                              if (pickedImages.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  height: 70,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: pickedImages.length,
                                    itemBuilder: (_, i) {
                                      final path = pickedImages[i];
                                      return Stack(
                                        children: [
                                          Container(
                                            margin: const EdgeInsets.only(
                                              right: 8,
                                            ),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Image.file(
                                                File(path),
                                                width: 70,
                                                height: 70,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 2,
                                            right: 10,
                                            child: GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  pickedImages.removeAt(i);
                                                });
                                              },
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.black54,
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  size: 14,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ),

                              // ===== ② 输入框 =====
                              TextField(
                                controller: controller,
                                minLines: 1,
                                maxLines: 3,
                                style: TextStyle(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: "输入消息...",
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),

                              const SizedBox(height: 8),

                              // ===== ③ 功能按钮区 =====
                              Row(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.image),
                                    onPressed: pickImage,
                                  ),

                                  GestureDetector(
                                    onTap: () {
                                      if (!isActivated) {
                                        _showLimitSheet();
                                        return;
                                      }

                                      setState(() {
                                        useDeep = !useDeep;
                                      });

                                      _saveModelPrefs();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: useDeep
                                            ? const Color(
                                                0xFF22D3EE,
                                              ).withOpacity(0.2)
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        border: useDeep
                                            ? Border.all(
                                                color: const Color(0xFF22D3EE),
                                                width: 1.5,
                                              )
                                            : null,
                                      ),
                                      child: Image.asset(
                                        isDark
                                            ? 'assets/ailogo_dark.png'
                                            : 'assets/ailogo.png',
                                        width: 28,
                                        height: 28,
                                        color: !isActivated
                                            ? Colors.grey
                                            : (useDeep
                                                  ? const Color(0xFF22D3EE)
                                                  : null),
                                      ),
                                    ),
                                  ),

                                  const Spacer(),

                                  GestureDetector(
                                    onTap: () {
                                      showDialog(
                                        context: context,
                                        barrierColor: Colors.black.withOpacity(
                                          0.3,
                                        ),
                                        builder: (dialogContext) {
                                          final isDarkDialog =
                                              Theme.of(
                                                dialogContext,
                                              ).brightness ==
                                              Brightness.dark;

                                          return Center(
                                            child: Material(
                                              color: Colors.transparent,
                                              child: Container(
                                                width: 260,
                                                padding: const EdgeInsets.all(
                                                  14,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isDarkDialog
                                                      ? const Color(0xFF111827)
                                                      : Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withOpacity(0.2),
                                                      blurRadius: 20,
                                                    ),
                                                  ],
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Text(
                                                      "选择模型",
                                                      style: TextStyle(
                                                        fontSize: 14,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),

                                                    const SizedBox(height: 10),

                                                    _modelItem(
                                                      name: "Flash",
                                                      selected: currentModel
                                                          .contains('flash'),
                                                      onTap: () {
                                                        setState(
                                                          () => currentModel =
                                                              'deepseek-v4-flash',
                                                        );
                                                        _saveModelPrefs();
                                                        Navigator.pop(
                                                          dialogContext,
                                                        );
                                                      },
                                                    ),

                                                    _modelItem(
                                                      name: "Pro",
                                                      locked: !isActivated,
                                                      selected: currentModel
                                                          .contains('pro'),
                                                      onTap: () {
                                                        if (!isActivated) {
                                                          Navigator.pop(
                                                            dialogContext,
                                                          );
                                                          _showLimitSheet();
                                                          return;
                                                        }

                                                        setState(
                                                          () => currentModel =
                                                              'deepseek-v4-pro',
                                                        );
                                                        _saveModelPrefs();
                                                        Navigator.pop(
                                                          dialogContext,
                                                        );
                                                      },
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.1)
                                            : Colors.black.withOpacity(0.05),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        currentModel.contains('pro')
                                            ? "Pro"
                                            : "Flash",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 8),

                                  IconButton(
                                    icon: Icon(
                                      isGenerating
                                          ? Icons.stop_circle
                                          : Icons.send,
                                    ),
                                    onPressed: isGenerating
                                        ? cancelGeneration
                                        : () {
                                            final text = controller.text.trim();

                                            if (text.isEmpty &&
                                                pickedImages.isEmpty) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text("请输入内容"),
                                                ),
                                              );
                                              return;
                                            }

                                            if (text.isEmpty &&
                                                pickedImages.isNotEmpty &&
                                                !supportsLocalImageOcr) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    '当前平台不支持仅发图片，请补充文字说明',
                                                  ),
                                                ),
                                              );
                                              return;
                                            }

                                            sendMessage();
                                          },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
