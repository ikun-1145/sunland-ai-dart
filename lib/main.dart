import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
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
import 'furry_event_api.dart';
import 'sunland_remote_provider.dart';
import 'database_token_provider.dart';
import 'ban_page.dart';
import 'maintenance_page.dart';
import 'network_unavailable_page.dart';
import 'services/ai_haptic_service.dart';
import 'services/app_config_service.dart';
import 'services/background_execution_service.dart';
import 'services/image_attachment_service.dart';
import 'services/network_connectivity_service.dart';
import 'services/user_status_service.dart';

// ⭐ 全局 token 存储
String? _authToken;
Completer<String?>? _tokenRefreshInProgress;
int? _tokenRefreshGeneration;
int _authSessionGeneration = 0;
final SunlandSessionStore _sessionStore = SunlandSessionStore();
late final DatabaseTokenProvider _databaseTokenProvider;

User _buildSupabaseUser(SunlandUser user) {
  final metadata = <String, dynamic>{};
  if (user.avatarUrl != null && user.avatarUrl!.isNotEmpty) {
    metadata['avatar_url'] = user.avatarUrl;
  }
  if (user.avatarPath != null && user.avatarPath!.isNotEmpty) {
    metadata['avatar_path'] = user.avatarPath;
  }
  if (user.name != null && user.name!.isNotEmpty) {
    metadata['name'] = user.name;
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

Future<String?> _readFreshAuthToken({
  bool notify = true,
  bool forceRefresh = false,
}) async {
  var token = _authToken ?? await _sessionStore.readToken();
  if (token == null || token.isEmpty) return null;

  if (forceRefresh || isJwtExpired(token, skew: const Duration(seconds: 30))) {
    final requestGeneration = _authSessionGeneration;
    final requestUserId = userFromJwt(token)?.id;
    if (requestUserId == null) return null;
    // 如果已有刷新在进行，等待结果
    if (_tokenRefreshInProgress != null) {
      return _tokenRefreshGeneration == requestGeneration
          ? _tokenRefreshInProgress!.future
          : token;
    }

    _tokenRefreshInProgress = Completer<String?>();
    _tokenRefreshGeneration = requestGeneration;
    try {
      final refreshed = await const SunlandAuthApi().refreshToken(token);
      if (_authSessionGeneration != requestGeneration) {
        _tokenRefreshInProgress!.complete(null);
        return null;
      }
      if (refreshed == null) {
        await _sessionStore.clearSession();
        _authToken = null;
        if (notify) currentUserNotifier.value = null;
        _tokenRefreshInProgress!.complete(null);
        return null;
      }
      if (refreshed.user.id != requestUserId) {
        throw const AuthExpiredException();
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
      _databaseTokenProvider.clear();
      if (notify) {
        currentUserNotifier.value = _buildSupabaseUser(refreshed.user);
      }
      _tokenRefreshInProgress!.complete(token);
      return token;
    } catch (e) {
      debugPrint('Token refresh failed: $e');
      // 对于临时错误（网络），不清除session，让下次重试
      // 对于permanent错误（401），才登出
      if (_authSessionGeneration == requestGeneration &&
          (e.toString().contains('401') ||
              e.toString().contains('Unauthorized'))) {
        await _sessionStore.clearSession();
        _authToken = null;
        if (notify) currentUserNotifier.value = null;
      }
      _tokenRefreshInProgress!.completeError(e);
      rethrow;
    } finally {
      _tokenRefreshInProgress = null;
      _tokenRefreshGeneration = null;
    }
  }

  _authToken = token;
  return token;
}

Future<String?> readFreshAuthToken({bool forceRefresh = false}) =>
    _readFreshAuthToken(forceRefresh: forceRefresh);

void clearDatabaseAccessToken() => _databaseTokenProvider.clear();

void clearApplicationAuthState() {
  _authSessionGeneration++;
  _authToken = null;
  _databaseTokenProvider.clear();
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

  _databaseTokenProvider = DatabaseTokenProvider(
    appTokenProvider: ({bool forceRefresh = false}) =>
        _readFreshAuthToken(forceRefresh: forceRefresh),
  );

  await Supabase.initialize(
    url: 'https://klyrasrqgxijwrxuoevj.supabase.co',
    publishableKey: supabasePublishableKey,
    accessToken: () => _databaseTokenProvider.getToken(),
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

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.appConfigService,
    this.networkConnectivityService,
    this.userStatusService,
    this.resumeCheckInterval = const Duration(seconds: 45),
  });

  final AppConfigService? appConfigService;
  final NetworkConnectivityService? networkConnectivityService;
  final UserStatusService? userStatusService;
  final Duration resumeCheckInterval;

  @override
  State<MyApp> createState() => _MyAppState();
}

enum _StartupState { loading, offline, maintenance, banned, ready }

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  late final AppConfigService _appConfigService;
  late final NetworkConnectivityService _networkConnectivityService;
  late final UserStatusService _userStatusService;
  AppConfig _appConfig = AppConfig.defaults;
  UserStatus _userStatus = UserStatus.active;
  _StartupState _startupState = _StartupState.loading;
  Future<void>? _startupCheckInProgress;
  Future<void>? _resumeNetworkCheckInProgress;
  DateTime? _lastStartupCheckAt;
  String? _observedUserId;
  int _userIdentityGeneration = 0;
  bool _pendingIdentityRecheck = false;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _appConfigService = widget.appConfigService ?? AppConfigService();
    _networkConnectivityService =
        widget.networkConnectivityService ?? NetworkConnectivityService();
    _userStatusService =
        widget.userStatusService ??
        UserStatusService(
          currentUserIdLoader: () async {
            final token = await _readFreshAuthToken(notify: false);
            return token == null ? null : userFromJwt(token)?.id;
          },
        );
    _observedUserId = currentUserNotifier.value?.id;
    currentUserNotifier.addListener(_handleCurrentUserChanged);
    WidgetsBinding.instance.addObserver(this);
    unawaited(_checkStartupState());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    currentUserNotifier.removeListener(_handleCurrentUserChanged);
    super.dispose();
  }

  void _handleCurrentUserChanged() {
    final userId = currentUserNotifier.value?.id;
    if (userId == _observedUserId) return;

    _observedUserId = userId;
    _userIdentityGeneration++;
    unawaited(_checkStartupState(identityChanged: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final lastCheckAt = _lastStartupCheckAt;
    if (lastCheckAt != null &&
        DateTime.now().difference(lastCheckAt) < widget.resumeCheckInterval) {
      unawaited(_checkNetworkAfterResume());
      return;
    }
    unawaited(_checkStartupState());
  }

  Future<void> _checkNetworkAfterResume() {
    final startupCheck = _startupCheckInProgress;
    if (startupCheck != null) return startupCheck;

    final inProgress = _resumeNetworkCheckInProgress;
    if (inProgress != null) return inProgress;

    late final Future<void> request;
    request = _performResumeNetworkCheck().whenComplete(() {
      if (identical(_resumeNetworkCheckInProgress, request)) {
        _resumeNetworkCheckInProgress = null;
      }
    });
    _resumeNetworkCheckInProgress = request;
    return request;
  }

  Future<void> _performResumeNetworkCheck() async {
    final hasInternetConnection = await _networkConnectivityService
        .hasInternetConnection();
    if (!mounted || _startupCheckInProgress != null) return;

    if (!hasInternetConnection) {
      setState(() => _startupState = _StartupState.offline);
      return;
    }

    if (_startupState == _StartupState.offline) {
      await _checkStartupState();
    }
  }

  Future<void> _checkStartupState({
    bool showProgress = false,
    bool identityChanged = false,
  }) {
    final inProgress = _startupCheckInProgress;
    if (inProgress != null) {
      if (identityChanged) {
        _pendingIdentityRecheck = true;
      }
      return showProgress ? _waitWithProgress(inProgress) : inProgress;
    }

    late final Future<void> request;
    request = _runStartupChecks().whenComplete(() {
      if (identical(_startupCheckInProgress, request)) {
        _startupCheckInProgress = null;
      }
    });
    _startupCheckInProgress = request;
    return showProgress ? _waitWithProgress(request) : request;
  }

  Future<void> _waitWithProgress(Future<void> request) async {
    if (mounted && !_isChecking) {
      setState(() => _isChecking = true);
    }
    try {
      await request;
    } finally {
      if (mounted && _isChecking) {
        setState(() => _isChecking = false);
      }
    }
  }

  Future<void> _runStartupChecks() async {
    do {
      _pendingIdentityRecheck = false;
      await _performStartupCheck();
    } while (mounted && _pendingIdentityRecheck);
  }

  Future<void> _performStartupCheck() async {
    _lastStartupCheckAt = DateTime.now();
    final identityGeneration = _userIdentityGeneration;

    try {
      final hasInternetConnection = await _networkConnectivityService
          .hasInternetConnection();
      if (!mounted || identityGeneration != _userIdentityGeneration) return;
      if (!hasInternetConnection) {
        setState(() => _startupState = _StartupState.offline);
        return;
      }

      AppConfig config;
      try {
        config = await _appConfigService.fetchAppConfig();
      } catch (error) {
        debugPrint(
          'Unexpected app config error; continuing in fail-open mode: $error',
        );
        config = AppConfig.defaults;
      }
      if (!mounted) return;
      if (config.maintenanceEnabled) {
        setState(() {
          _appConfig = config;
          _startupState = _StartupState.maintenance;
        });
        return;
      }

      if (identityGeneration != _userIdentityGeneration) return;

      UserStatus status;
      try {
        status = await _userStatusService.fetchCurrentUserStatus();
      } catch (error) {
        debugPrint(
          'Unexpected user status error; continuing in fail-open mode: $error',
        );
        status = UserStatus.active;
      }
      if (!mounted || identityGeneration != _userIdentityGeneration) return;
      setState(() {
        _appConfig = config;
        _userStatus = status;
        _startupState = status.isBanned
            ? _StartupState.banned
            : _StartupState.ready;
      });
    } catch (error) {
      debugPrint(
        'Unexpected startup check error; continuing in fail-open mode: $error',
      );
      if (!mounted || identityGeneration != _userIdentityGeneration) return;
      setState(() {
        _appConfig = AppConfig.defaults;
        _userStatus = UserStatus.active;
        _startupState = _StartupState.ready;
      });
    }
  }

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
            builder: (context, child) {
              switch (_startupState) {
                case _StartupState.loading:
                  return const _StartupLoadingPage();
                case _StartupState.offline:
                  return NetworkUnavailablePage(
                    isChecking: _isChecking,
                    onRetry: () => _checkStartupState(showProgress: true),
                  );
                case _StartupState.maintenance:
                  return MaintenancePage(
                    config: _appConfig,
                    isChecking: _isChecking,
                    onRetry: () => _checkStartupState(showProgress: true),
                  );
                case _StartupState.banned:
                  return BanPage(
                    status: _userStatus,
                    isChecking: _isChecking,
                    onRetry: () => _checkStartupState(showProgress: true),
                  );
                case _StartupState.ready:
                  return child ?? const SizedBox.shrink();
              }
            },
            home: const RootPage(),
          ),
        );
      },
    );
  }
}

class _StartupLoadingPage extends StatelessWidget {
  const _StartupLoadingPage();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/ailogo.png', width: 88),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF22D3EE),
              ),
            ),
          ],
        ),
      ),
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
            name: profile.name,
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
      _authSessionGeneration++;
      _databaseTokenProvider.clear();
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
          rethrow; // 让UI显示登录失败
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

enum _ImageAttachmentSource { camera, gallery, files }

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  // 🧠 当前对话ID（核心）
  String? currentConversationId = DateTime.now().millisecondsSinceEpoch
      .toString();

  // 🧠 无感上下文缓存
  Map<String, dynamic>? _lastQueryContext;
  // Normalize messages: combine "reasoning" + next assistant message into one
  void newConversation() {
    setState(() {
      currentConversationId = DateTime.now().millisecondsSinceEpoch.toString();

      messages.clear(); // ⚠️ 你这里有 messages，这个是OK的
      _lastQueryContext = null;
      _pendingProvider = deepSeekProviderId;
      useDeep = false;
      pickedImages.clear();
    });
  }

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
    sunlandProvider.cancelCurrent();

    _cancelRequested = true;
    _generationSerial++;
    unawaited(_endGenerationBackgroundTask());

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
          ? imagePaths
                .map((e) => e.toString())
                .where((p) => p.isNotEmpty)
                .toList()
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

    if (msg["isFurryCard"] == true) {
      if (msg["isLoading"] == true) return _buildFurryCardLoading(isDark);

      final events = msg['furryEvents'] ?? [];

      if (events is List) {
        return _buildFurryEventCards(events, isDark);
      }

      // 👇 fallback（防止结构异常）
      return _buildFurryEventCards([], isDark);
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

    final mdStyle = _assistantMarkdownStyle(isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 16, 6),
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
                  MarkdownBody(data: content, styleSheet: mdStyle),
                ],
                if (msg['furryEvents'] != null)
                  _buildFurryEventCards(msg['furryEvents'] as List, isDark),
                _stoppedHintWidget(msg, isDark),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty)
                MarkdownBody(data: text, styleSheet: mdStyle),
              if (msg['furryEvents'] != null)
                _buildFurryEventCards(msg['furryEvents'] as List, isDark),
              _stoppedHintWidget(msg, isDark),
            ],
          );
        },
      ),
    );
  }

  // ── AI 回复 Markdown 样式（按主题缓存，避免流式期间每帧重建）─────────────
  MarkdownStyleSheet? _mdStyleDark;
  MarkdownStyleSheet? _mdStyleLight;

  MarkdownStyleSheet _assistantMarkdownStyle(bool isDark) {
    final cached = isDark ? _mdStyleDark : _mdStyleLight;
    if (cached != null) return cached;
    final sheet = MarkdownStyleSheet(
      h1: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black87,
        height: 1.4,
      ),
      h2: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black87,
        height: 1.4,
      ),
      h3: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black87,
        height: 1.4,
      ),
      p: TextStyle(
        fontSize: 15,
        height: 1.65,
        color: isDark ? Colors.white.withOpacity(0.9) : Colors.black87,
      ),
      strong: const TextStyle(fontWeight: FontWeight.bold),
      em: const TextStyle(fontStyle: FontStyle.italic),
      tableHead: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 14,
        color: isDark ? Colors.white : Colors.black87,
      ),
      tableBody: TextStyle(
        fontSize: 14,
        color: isDark ? Colors.white.withOpacity(0.85) : Colors.black87,
      ),
      tableBorder: TableBorder.all(
        color: isDark
            ? Colors.white.withOpacity(0.12)
            : Colors.black.withOpacity(0.1),
        width: 0.8,
      ),
      tableHeadAlign: TextAlign.left,
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      codeblockDecoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F2E) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(8),
      ),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: isDark ? const Color(0xFF88DDFF) : const Color(0xFF1A56DB),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: isDark
                ? Colors.white.withOpacity(0.3)
                : Colors.black.withOpacity(0.2),
            width: 3,
          ),
        ),
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.03),
      ),
    );
    if (isDark) {
      _mdStyleDark = sheet;
    } else {
      _mdStyleLight = sheet;
    }
    return sheet;
  }

  // ── 兽聚查询辅助 ─────────────────────────────────────────────────────────

  bool _isFurryEventQuery(String text) =>
      text.contains('兽聚') ||
      text.contains('毛展') ||
      text.contains('兽展') ||
      text.contains('furry') ||
      text.contains('Furry') ||
      text.contains('兽人聚会') ||
      text.contains('兽人活动') ||
      text.contains('兽人展');

  Map<String, dynamic>? get _latestFurryCard {
    for (final message in messages.reversed) {
      if (message['isFurryCard'] == true && message['isLoading'] != true) {
        return message;
      }
    }
    return null;
  }

  bool _shouldSearchFurryEvents(String text) {
    if (_isFurryEventQuery(text)) return true;
    if (_latestFurryCard == null) return false;
    final hasFollowUpCue = RegExp(
      r'那|换|改|查|看看|呢|还有|其他|别的|范围|时间|城市|月份|年份',
    ).hasMatch(text);
    final hasTimeOrScopeChange = RegExp(
      r'本月|这个月|下个月|下下个月|今年|明年|后年|20\d{2}\s*年?|\d{1,2}\s*月|[一二三四五六七八九十]{1,2}月|全国|所有|全部|不限|任意|最近|近期|未来',
    ).hasMatch(text);
    if (_extractCity(text) != null && hasFollowUpCue) return true;
    return hasTimeOrScopeChange && hasFollowUpCue;
  }

  bool _shouldAnswerFromFurryContext(String text) {
    if (_latestFurryCard == null) return false;
    if (_isFurryEventQuery(text)) return true;
    return RegExp(
      r'兽聚|毛展|兽展|这(?:些|个|场)|它们?|第[一二三四五六七八九十\d]+场|哪(?:个|场)|几个|几场|多少|最早|最晚|最近|时间|日期|什么时候|地点|地址|哪里|在哪|城市|天气|酒店|住宿|门票|票价|链接|详情',
      caseSensitive: false,
    ).hasMatch(text);
  }

  String? _extractCity(String text) {
    const cities = [
      '北京',
      '上海',
      '广州',
      '深圳',
      '成都',
      '杭州',
      '武汉',
      '南京',
      '西安',
      '重庆',
      '天津',
      '长沙',
      '哈尔滨',
      '昆明',
      '福州',
      '厦门',
      '郑州',
      '苏州',
      '大连',
      '青岛',
      '宁波',
      '温州',
      '佛山',
      '东莞',
      '南宁',
      '海口',
      '长春',
      '沈阳',
      '贵阳',
      '拉萨',
      '兰州',
      '西宁',
      '乌鲁木齐',
      '新北',
      '台北',
      '高雄',
      '香港',
      '澳门',
    ];
    for (final city in cities) {
      if (text.contains(city)) return city;
    }
    return null;
  }

  int? _extractMonth(String text) {
    final now = DateTime.now();
    if (text.contains('下下个月')) {
      return DateTime(now.year, now.month + 2, 1).month;
    }
    if (text.contains('下个月')) {
      return DateTime(now.year, now.month + 1, 1).month;
    }
    if (text.contains('本月') || text.contains('这个月')) return now.month;
    final m = RegExp(r'(\d{1,2})\s*月').firstMatch(text);
    if (m != null) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v >= 1 && v <= 12) return v;
    }
    const cnMap = {
      '十二': 12,
      '十一': 11,
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
    };
    for (final e in cnMap.entries) {
      if (text.contains('${e.key}月')) return e.value;
    }
    return null;
  }

  int? _extractYear(String text) {
    final now = DateTime.now();
    if (text.contains('后年')) return now.year + 2;
    if (text.contains('明年')) return now.year + 1;
    if (text.contains('今年')) return now.year;
    final m = RegExp(r'(20\d{2})\s*年?').firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  /// 由 AI 解析兽聚查询范围：结合"上一次查询范围"+本次消息，让模型直接输出
  /// 本次最终的 {city, year, month}（自带继承/覆盖/放宽判断）。
  /// 使用 flash 模型（最快最省，不动 Pro）；任何失败都回退到本地正则提取
  /// + 上下文补全，保证卡片始终可用、不退化。
  Future<({String? city, int? month, int? year})> _resolveFurryQueryParams(
    String text,
  ) async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 上一次查询范围（供模型做上下文继承）
    final ctx = _lastQueryContext;
    final String ctxDesc;
    if (ctx == null ||
        (ctx['city'] == null && ctx['month'] == null && ctx['year'] == null)) {
      ctxDesc = '无（本对话首次兽聚查询）';
    } else {
      ctxDesc =
          '城市=${ctx['city'] ?? '未指定'}，年=${ctx['year'] ?? '未指定'}，月=${ctx['month'] ?? '未指定'}';
    }

    try {
      final result = await apiClient
          .sendChat(
            model: 'deepseek-v4-flash',
            deep: false,
            messages: [
              ChatMessage(
                role: 'system',
                content:
                    '你是兽聚查询范围解析器。结合"上一次查询范围"和用户这句话，'
                    '输出用户【本次】想查询的最终范围。'
                    '只输出一个 JSON 对象，不要任何解释、前后缀或 markdown 代码块。'
                    '字段：city（中文城市名字符串，无则 null）、'
                    'year（整数年份，如 2026，无则 null）、'
                    'month（整数 1-12，无则 null）。'
                    '今天是 $today，仅用于换算相对时间。'
                    '规则：'
                    '1) 用户本次未提到的维度，沿用"上一次查询范围"里的值'
                    '（例：上次=上海，本次"明年的"→ city=上海 且 year=次年）；'
                    '2) 用户本次明确改了某维度，用新值覆盖'
                    '（例："那北京呢"→ city 改成北京）；'
                    '3) 用户表达"全部/所有/不限/任意时间/任何城市/都行/再看看别的"等放宽意图时，'
                    '把对应维度清成 null；'
                    '4) 相对时间换算："今年"→当年 year，"明年"→次年 year，'
                    '"下个月"→下一个自然月 month（跨年时 year 相应 +1）；'
                    '5) 不要凭空猜测：用户没提到、也无法从上一次继承的维度，保持 null。'
                    '示例（无上下文）："上海有什么兽聚"→{"city":"上海","year":null,"month":null}；'
                    '"12月的兽展"→{"city":null,"year":null,"month":12}。',
              ),

              ChatMessage(role: 'system', content: '上一次查询范围：$ctxDesc'),

              ChatMessage(role: 'user', content: text),
            ],
          )
          .timeout(const Duration(seconds: 12));

      // 容错抽取 JSON（兼容模型可能附带的代码块或多余文字）
      final raw = result.content;
      final match = RegExp(r'\{[\s\S]*\}').firstMatch(raw);
      if (match == null) return _fallbackResolve(text);
      final decoded = jsonDecode(match.group(0)!);
      if (decoded is! Map) return _fallbackResolve(text);

      String? city = decoded['city']?.toString().trim();
      if (city == null || city.isEmpty || city.toLowerCase() == 'null') {
        city = null;
      }

      int? toIntOrNull(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString());
      }

      int? month = toIntOrNull(decoded['month']);
      if (month != null && (month < 1 || month > 12)) month = null;

      int? year = toIntOrNull(decoded['year']);

      // 模型已完成上下文合并，直接采用其输出作为本次范围并写回上下文
      _lastQueryContext = {'city': city, 'month': month, 'year': year};

      return (city: city, month: month, year: year);
    } catch (_) {
      // 网络错误、429 限额、解析失败等 → 回退本地正则 + 上下文补全
      return _fallbackResolve(text);
    }
  }

  /// AI 解析失败时的兜底：本地正则提取 + 上一次查询范围 null 补全，
  /// 并同样写回上下文，保证后续追问仍能继承。
  ({String? city, int? month, int? year}) _fallbackResolve(String text) {
    var city = _extractCity(text) ?? _lastQueryContext?['city'] as String?;
    var month = _extractMonth(text) ?? _lastQueryContext?['month'] as int?;
    var year = _extractYear(text) ?? _lastQueryContext?['year'] as int?;

    if (RegExp(r'全国|所有城市|全部城市|任何城市|不限城市|城市不限').hasMatch(text)) {
      city = null;
    }
    if (RegExp(r'任意时间|不限时间|所有时间|全部时间|时间不限').hasMatch(text)) {
      month = null;
      year = null;
    } else if (RegExp(r'最近|近期|未来').hasMatch(text) &&
        !RegExp(
          r'\d{1,2}\s*月|[一二三四五六七八九十]{1,2}月|今年|明年|后年|20\d{2}',
        ).hasMatch(text)) {
      month = null;
      year = null;
    }
    if (text.contains('下下个月')) {
      final shifted = DateTime(DateTime.now().year, DateTime.now().month + 2);
      month = shifted.month;
      year = shifted.year;
    } else if (text.contains('下个月')) {
      final shifted = DateTime(DateTime.now().year, DateTime.now().month + 1);
      month = shifted.month;
      year = shifted.year;
    } else if (text.contains('本月') || text.contains('这个月')) {
      month = DateTime.now().month;
      year = DateTime.now().year;
    }

    _lastQueryContext = {'city': city, 'month': month, 'year': year};
    return (city: city, month: month, year: year);
  }

  String _answerFurryEventQuestion(
    String text,
    FurryEventSearchResult? result,
  ) {
    if (result == null) {
      return '这次兽聚数据暂时没有成功取回来，先别急着按空结果做计划，稍后再查一次会更稳妥 🐾';
    }
    return _answerFurryEventMaps(
      text,
      result.events.map((event) => event.toMap()).toList(),
      query: _lastQueryContext,
    );
  }

  String _furryQueryDescription(Map<String, dynamic>? rawQuery) {
    final pieces = <String>[];
    final city = rawQuery?['city']?.toString().trim() ?? '';
    final year = int.tryParse(rawQuery?['year']?.toString() ?? '');
    final month = int.tryParse(rawQuery?['month']?.toString() ?? '');
    if (city.isNotEmpty) pieces.add(city);
    if (year != null && year >= 2000 && year <= 2100) {
      pieces.add('$year年');
    }
    if (month != null && month >= 1 && month <= 12) {
      pieces.add('$month月');
    }
    return pieces.isEmpty ? '近期全部城市' : pieces.join(' · ');
  }

  String _answerFurryEventMaps(
    String text,
    List<dynamic> rawEvents, {
    Map<String, dynamic>? query,
  }) {
    final events =
        rawEvents
            .whereType<Map>()
            .map((raw) {
              final event = Map<String, dynamic>.from(
                raw.map((key, value) => MapEntry(key.toString(), value)),
              );
              return <String, dynamic>{
                'name': (event['name'] ?? '').toString(),
                'startAt': (event['startAt'] ?? event['start_at'] ?? '')
                    .toString(),
                'endAt': (event['endAt'] ?? event['end_at'] ?? '').toString(),
                'city': (event['city'] ?? '').toString(),
                'venue': (event['venue'] ?? event['address'] ?? '').toString(),
                'weather': event['weather'],
              };
            })
            .where(
              (event) =>
                  event['name'].toString().isNotEmpty &&
                  event['startAt'].toString().isNotEmpty,
            )
            .toList()
          ..sort((a, b) {
            final byDate = a['startAt'].toString().compareTo(
              b['startAt'].toString(),
            );
            return byDate != 0
                ? byDate
                : a['name'].toString().compareTo(b['name'].toString());
          });
    if (events.isEmpty) {
      return '我按“${_furryQueryDescription(query)}”查过了，目前没有符合条件的兽聚活动。你可以换个城市或月份，我再继续找找。';
    }

    Map<String, dynamic> selected = events.first;
    const numberWords = {
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
      '十': 10,
    };
    final ordinal = RegExp(r'第\s*([一二三四五六七八九十]|\d+)\s*场?').firstMatch(text);
    final named = events.where(
      (event) => text.contains(event['name'].toString()),
    );
    if (named.isNotEmpty) {
      selected = named.first;
    } else if (ordinal != null) {
      final value = ordinal.group(1) ?? '';
      final index = (int.tryParse(value) ?? numberWords[value] ?? 1) - 1;
      selected = events[index.clamp(0, events.length - 1)];
    } else if (text.contains('最后') || text.contains('最晚')) {
      selected = events.last;
    }

    final name = selected['name'].toString();
    final location = [selected['city'], selected['venue']]
        .map((value) => value.toString())
        .where((value) => value.isNotEmpty)
        .join(' · ');
    final start = _formatEventDate(selected['startAt'].toString());
    final end = _formatEventDate(selected['endAt'].toString());
    final date = end.isEmpty || end == start ? start : '$start–$end';

    if (RegExp(r'多少|几场|几个').hasMatch(text)) {
      return '这次一共查到 ${events.length} 场，完整信息都放在上面的卡片里啦 🐾';
    }
    if (RegExp(r'哪里|在哪|地点|地址|城市').hasMatch(text)) {
      return '$name在${location.isEmpty ? '地点暂未公布' : location}，具体位置和详情链接可以直接点上面的卡片查看。';
    }
    if (RegExp(r'什么时候|时间|日期|几月|哪天').hasMatch(text)) {
      return '$name的活动时间是$date，出发前也建议再点卡片确认主办方的最新安排。';
    }
    if (text.contains('天气')) {
      final weather = selected['weather'];
      if (weather is Map) {
        final label = (weather['label'] ?? '未知').toString();
        final min = weather['tempMin'] ?? weather['temp_min'] ?? '?';
        final max = weather['tempMax'] ?? weather['temp_max'] ?? '?';
        return '$name目前的天气预报是$label，$min~$max°C；临近出发时再看一次会更准。';
      }
      return '$name的日期还不在可靠预报范围内，卡片暂时没有天气数据，临近出发时再查会更准。';
    }
    if (RegExp(r'酒店|住宿').hasMatch(text)) {
      return '$name在${location.isEmpty ? '地点暂未公布' : location}，我已经把住宿搜索入口放进卡片里了，可以直接比较携程和美团。';
    }
    if (RegExp(r'最早|最近|第一场').hasMatch(text)) {
      return '时间最近的是$name，$date，地点在${location.isEmpty ? '地点暂未公布' : location}。详情和住宿入口都可以点卡片查看。';
    }

    final preview = events.take(3).map((event) => event['name']).join('、');
    return '我按“${_furryQueryDescription(query)}”查到 ${events.length} 场，最近几场有$preview${events.length > 3 ? '等' : ''}。完整时间、地点和链接都在上面的卡片里～';
  }

  String _formatEventDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}月${dt.day}日';
    } catch (_) {
      return iso.length >= 10 ? iso.substring(0, 10) : iso;
    }
  }

  Widget _buildFurryCardLoading(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.25, end: 0.65),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          onEnd: () {
            if (mounted) setState(() {});
          },
          builder: (_, opacity, _) {
            final baseColor = (isDark ? Colors.white : Colors.black)
                .withOpacity(opacity * 0.12);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.pets,
                      size: 13,
                      color: Colors.grey.withOpacity(opacity + 0.1),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '正在获取兽聚活动...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.withOpacity(opacity + 0.1),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 骨架卡片
                ...List.generate(
                  2,
                  (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      width: 260,
                      height: 72,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Container(
                            width: 140,
                            height: 10,
                            decoration: BoxDecoration(
                              color: baseColor,
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                          Container(
                            width: 100,
                            height: 8,
                            decoration: BoxDecoration(
                              color: baseColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFurryEventCards(List<dynamic> events, bool isDark) {
    if (events.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          "🐾 没有找到相关兽聚活动",
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      );
    }
    return _FurryEventCarousel(
      events: events,
      isDark: isDark,
      cardBuilder: _buildFurryEventCard,
    );
  }

  Widget _buildFurryEventCard(Map<String, dynamic> event, bool isDark) {
    final name = (event['name'] ?? '').toString();
    // 兼容新字段名（coverUrl/startAt）和旧字段名（cover/start_at）
    final startAt = (event['startAt'] ?? event['start_at'] ?? '').toString();
    final endAt = (event['endAt'] ?? event['end_at'] ?? '').toString();
    final city = (event['city'] ?? '').toString();
    final venue = (event['venue'] ?? event['address'] ?? '').toString();

    // 直接使用后端返回的代理图片（Worker 已处理防盗链）
    String? coverUrl = (event['coverUrl'] ?? event['cover'])?.toString();

    if (coverUrl != null) {
      coverUrl = coverUrl.trim();
      if (coverUrl.isEmpty) coverUrl = null;

      // 如果是相对路径（/proxy?...），补全 Worker 域名，避免双斜杠 bug
      if (coverUrl != null && coverUrl.startsWith('/proxy')) {
        coverUrl =
            'https://sunland-data-worker.liuxizekali.workers.dev$coverUrl';
      }
      print("最终图片URL = $coverUrl");
    }

    final sourceUrl = (event['sourceUrl'] ?? event['source_url'])?.toString();

    final rawStatus = (event['raw_status'] ?? '').toString();
    final daysUntil = event['days_until'];

    // ✅ 调试用：看看真实返回的封面地址
    print("coverUrl = $coverUrl");
    final weather = (event['weather'] is Map)
        ? Map<String, dynamic>.from(event['weather'])
        : null;
    // 调试天气
    print("weather = $weather");

    final hotels = (event['hotels'] is Map)
        ? Map<String, dynamic>.from(event['hotels'])
        : null;

    String formatShort(String s) {
      if (s.isEmpty) return '';
      try {
        final dt = DateTime.parse(s).toLocal();
        return '${dt.month}月${dt.day}日';
      } catch (_) {
        return s;
      }
    }

    final startShort = formatShort(startAt);
    final endShort = formatShort(endAt);

    final dateStr = (endShort.isEmpty || startShort == endShort)
        ? startShort
        : '$startShort-$endShort';

    final cardBg = isDark ? const Color(0xFF1E2738) : const Color(0xFFF8F9FC);
    final borderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.06);

    return GestureDetector(
      onTap: (sourceUrl != null && sourceUrl.isNotEmpty)
          ? () => launchUrl(
              Uri.parse(sourceUrl),
              mode: LaunchMode.externalApplication,
            )
          : null,
      onLongPress: () {
        showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: "event",
          barrierColor: Colors.black.withOpacity(0.4),
          transitionDuration: const Duration(milliseconds: 250),
          pageBuilder: (_, _, _) {
            return Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.9, end: 1.0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                builder: (context, scale, child) {
                  return Transform.scale(scale: scale, child: child);
                },
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(context).size.width * 0.85,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E2738) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (coverUrl != null)
                          Image.network(
                            coverUrl,
                            height: 180,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(dateStr),
                              const SizedBox(height: 6),
                              Text(city.isNotEmpty ? city : "未知城市"),
                              const SizedBox(height: 6),
                              if (venue.isNotEmpty) Text(venue),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          transitionBuilder: (_, anim, _, child) {
            return FadeTransition(opacity: anim, child: child);
          },
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF1E2738), const Color(0xFF111827)]
                : [Colors.white, const Color(0xFFF3F6FB)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.5 : 0.08),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图片区块（有图片时显示图片，没图片时显示占位符）
            if (coverUrl != null && coverUrl.isNotEmpty)
              Stack(
                children: [
                  SizedBox(
                    height: 130,
                    width: double.infinity,
                    child: Image.network(
                      coverUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.black.withOpacity(0.05),
                          child: const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      },
                      errorBuilder: (_, error, stack) {
                        print("图片加载失败: $coverUrl");
                        return Container(
                          height: 130,
                          color: isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.black.withOpacity(0.05),
                          child: const Center(
                            child: Icon(Icons.broken_image, size: 28),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              )
            else
              Container(
                height: 130,
                width: double.infinity,
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : Colors.black.withOpacity(0.05),
                child: const Center(
                  child: Icon(Icons.image_not_supported, size: 28),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.location_on_outlined,
                        size: 12,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          city.isNotEmpty && venue.isNotEmpty
                              ? '$city · $venue'
                              : city.isNotEmpty
                              ? city
                              : venue,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // 新增：状态 + 倒计时
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (rawStatus.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            rawStatus,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.blue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      if (rawStatus.isNotEmpty && daysUntil != null)
                        const SizedBox(width: 8),
                      if (daysUntil != null)
                        Text(
                          daysUntil is int
                              ? (daysUntil > 0 ? '还有 $daysUntil 天' : '进行中/已结束')
                              : '',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 替换天气Row为FutureBuilder
                  FutureBuilder<FurryEventWeather?>(
                    future: WeatherApi.fetch(
                      city.isEmpty ? "上海" : city,
                      startAt,
                    ),
                    builder: (context, snapshot) {
                      final w = snapshot.data;

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Row(
                          children: [
                            Icon(
                              Icons.wb_sunny_outlined,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              "加载天气中...",
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        );
                      }

                      if (w == null) {
                        return Row(
                          children: [
                            Icon(
                              Icons.help_outline,
                              size: 12,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            const Text(
                              "暂无天气信息",
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        );
                      }

                      final label = (w.label ?? "").toString();
                      final min = w.tempMin;
                      final max = w.tempMax;

                      final text = (min != null && max != null)
                          ? "$label ${min.toStringAsFixed(0)}~${max.toStringAsFixed(0)}°C"
                          : (label.isNotEmpty ? label : "暂无天气信息");

                      return Row(
                        children: [
                          Icon(
                            _weatherIcon(label),
                            size: 12,
                            color: _weatherColor(label, isDark),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            text,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  if (venue.isNotEmpty &&
                      hotels != null &&
                      (hotels['ctripUrl'] != null ||
                          hotels['meituanUrl'] != null ||
                          hotels['ctrip_url'] != null ||
                          hotels['meituan_url'] != null)) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (hotels['ctripUrl'] != null ||
                            hotels['ctrip_url'] != null)
                          _hotelButton(
                            '携程',
                            (hotels['ctripUrl'] ?? hotels['ctrip_url'])
                                .toString(),
                            isDark,
                            const Color(0xFF0086F6),
                          ),
                        if ((hotels['ctripUrl'] != null ||
                                hotels['ctrip_url'] != null) &&
                            (hotels['meituanUrl'] != null ||
                                hotels['meituan_url'] != null))
                          const SizedBox(width: 8),
                        if (hotels['meituanUrl'] != null ||
                            hotels['meituan_url'] != null)
                          _hotelButton(
                            '美团',
                            (hotels['meituanUrl'] ?? hotels['meituan_url'])
                                .toString(),
                            isDark,
                            const Color(0xFFF9A825),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _weatherIcon(String label) {
    final l = label.toLowerCase();
    if (l.contains('雨')) return Icons.umbrella_outlined;
    if (l.contains('雪')) return Icons.ac_unit;
    if (l.contains('阴')) return Icons.cloud_outlined;
    if (l.contains('云')) return Icons.cloud;
    if (l.contains('雷')) return Icons.flash_on;
    return Icons.wb_sunny_outlined;
  }

  Color _weatherColor(String label, bool isDark) {
    final l = label.toLowerCase();
    if (l.contains('雨')) return Colors.blueAccent;
    if (l.contains('雪')) return Colors.lightBlueAccent;
    if (l.contains('阴') || l.contains('云')) {
      return isDark ? Colors.white54 : Colors.grey;
    }
    if (l.contains('雷')) return Colors.deepPurpleAccent;
    return isDark ? Colors.amber.shade300 : Colors.orange;
  }

  Widget _hotelButton(String label, String url, bool isDark, Color accent) {
    return GestureDetector(
      onTap: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hotel_outlined, size: 11, color: accent),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: accent,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  late final SunlandApiClient apiClient;
  late final SunlandRemoteProvider sunlandProvider;
  late final SupabaseAiRepository repo;
  late final SunlandSessionStore store;
  final supabase = Supabase.instance.client;
  String currentModel = 'deepseek-v4-flash';
  String _pendingProvider = deepSeekProviderId;
  bool useDeep = false;
  bool isActivated = false;
  int _remainingCount = freeDailyLimit;
  String? _lastUserText;
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<Map<String, dynamic>> messages = [];
  List<Map<String, dynamic>> conversations = [];
  final Map<String, List<Map<String, dynamic>>> localConversationMessages = {};
  bool isGenerating = false;
  bool _cancelRequested = false;
  int _generationSerial = 0;
  StreamSubscription<AiResponse>? _currentStreamSubscription;
  List<String> pickedImages = [];
  final ImagePicker _imagePicker = ImagePicker();
  final BackgroundExecutionService _backgroundExecution =
      const BackgroundExecutionService();
  final AiHapticService _aiHaptics = AiHapticService();
  int? _generationBackgroundTaskId;
  bool _ocrPrivacyTipShown = false;
  bool isUploadingAvatar = false;

  Future<void> _beginGenerationBackgroundTask() async {
    if (!Platform.isIOS || _generationBackgroundTaskId != null) return;
    final taskId = await _backgroundExecution.begin(
      name: 'Complete active AI response',
    );
    if (!mounted || !isGenerating) {
      await _backgroundExecution.end(taskId);
      return;
    }
    _generationBackgroundTaskId = taskId;
  }

  Future<void> _endGenerationBackgroundTask() async {
    final taskId = _generationBackgroundTaskId;
    _generationBackgroundTaskId = null;
    await _backgroundExecution.end(taskId);
  }

  Map<String, dynamic>? get _currentConversation {
    final id = currentConversationId;
    if (id == null) return null;
    for (final conversation in conversations) {
      if (conversation['id']?.toString() == id) return conversation;
    }
    return null;
  }

  String get _activeProvider {
    return _currentConversation?['provider'] == sunlandProviderId
        ? sunlandProviderId
        : _currentConversation == null
        ? _pendingProvider
        : deepSeekProviderId;
  }

  bool get _isSunlandConversation => _activeProvider == sunlandProviderId;

  bool get _hasCurrentConversationStarted {
    return messages.any(
      (message) =>
          message['isUser'] == true ||
          (message['isFurryCard'] != true &&
              message['isUser'] != true &&
              (message['text'] ?? '').toString().trim().isNotEmpty &&
              message['text'] != '思考中...' &&
              message['text'] != '深度思考中...'),
    );
  }

  void _applyProviderStateForConversation(Map<String, dynamic>? conversation) {
    final provider = conversation?['provider'] == sunlandProviderId
        ? sunlandProviderId
        : deepSeekProviderId;
    _pendingProvider = provider;
    if (provider == sunlandProviderId) {
      useDeep = false;
      pickedImages.clear();
      _restoreFurryQueryContext();
      return;
    }
    currentModel = conversation?['model'] == 'deepseek-v4-pro'
        ? 'deepseek-v4-pro'
        : 'deepseek-v4-flash';
    _restoreFurryQueryContext();
  }

  void _restoreFurryQueryContext() {
    final query = _latestFurryCard?['furryQuery'];
    _lastQueryContext = query is Map
        ? Map<String, dynamic>.from(
            query.map((key, value) => MapEntry(key.toString(), value)),
          )
        : null;
  }

  Future<bool> _selectConversationProvider({
    required String provider,
    required String model,
  }) async {
    if (provider == sunlandProviderId && !sunlandProvider.isSupported) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sunland AI 服务暂时不可用')));
      }
      return false;
    }

    var conversation = _currentConversation;
    if (conversation == null) {
      final id =
          currentConversationId ??
          DateTime.now().millisecondsSinceEpoch.toString();
      final created = <String, dynamic>{
        'id': id,
        'title': '新对话',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'titleGenerated': false,
        'provider': deepSeekProviderId,
        'model': currentModel,
        'userId': currentUserNotifier.value?.id,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
      };
      setState(() {
        currentConversationId = id;
        conversations.insert(0, created);
        localConversationMessages[id] = <Map<String, dynamic>>[];
      });
      conversation = created;
    }
    final targetConversation = conversation;
    final existingProvider = targetConversation['provider'] == sunlandProviderId
        ? sunlandProviderId
        : deepSeekProviderId;
    if (_hasCurrentConversationStarted && existingProvider != provider) {
      if (mounted) {
        final name = existingProvider == sunlandProviderId
            ? 'Sunland AI'
            : 'DeepSeek';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('当前对话已绑定 $name，请新建对话后切换模型。')));
      }
      return false;
    }

    final userId = currentUserNotifier.value?.id;
    setState(() {
      _pendingProvider = provider;
      targetConversation['provider'] = provider;
      targetConversation['model'] = model;
      targetConversation['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
      targetConversation['userId'] ??= userId;
      targetConversation['createdAt'] ??=
          int.tryParse(targetConversation['id']?.toString() ?? '') ??
          DateTime.now().millisecondsSinceEpoch;
      if (provider != sunlandProviderId) {
        currentModel = model;
      }
      if (provider == sunlandProviderId) {
        useDeep = false;
        pickedImages.clear();
      }
    });
    await _saveModelPrefs();
    rememberLocalMessages();
    unawaited(_saveToCloud());
    return true;
  }

  bool isLocalConversation(String? id) => id?.startsWith('local_') ?? false;

  Map<String, dynamic>? _messageToCloud(Map<String, dynamic> message) {
    // 加载中的兽聚卡片占位符不持久化（临时状态）
    if (message['isFurryCard'] == true && message['isLoading'] == true) {
      return null;
    }
    // 已加载的兽聚卡片独立保存
    if (message['isFurryCard'] == true) {
      return {
        'role': 'assistant',
        'content': '',
        'isFurryCard': true,
        'furryEvents': message['furryEvents'] is List
            ? message['furryEvents']
            : <dynamic>[],
        if (message['furryQuery'] is Map) 'furryQuery': message['furryQuery'],
        if (message['furryError'] != null)
          'furryError': message['furryError'].toString(),
        if (message['isEmpty'] == true) 'isEmpty': true,
      };
    }

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
      if (message['furryEvents'] != null) 'furryEvents': message['furryEvents'],
    };
  }

  Map<String, dynamic> _messageFromCloud(Map message) {
    final role = message['role']?.toString() ?? 'assistant';
    final content = (message['content'] ?? '').toString();
    final reasoning = (message['reasoning'] ?? message['reasoning_content'])
        ?.toString()
        .trim();
    if (message['isFurryCard'] == true) {
      // 从缓存恢复时，把旧字段名转换成新字段名
      List<dynamic> normalizedEvents = [];
      if (message['furryEvents'] is List) {
        normalizedEvents = (message['furryEvents'] as List).map((e) {
          if (e is! Map) return e;
          final m = Map<String, dynamic>.from(
            e.map((k, v) => MapEntry(k.toString(), v)),
          );
          return {
            'name': m['name'] ?? '',
            'startAt': m['startAt'] ?? m['start_at'] ?? '',
            'endAt': m['endAt'] ?? m['end_at'] ?? '',
            'city': m['city'] ?? '',
            'venue': m['venue'] ?? m['address'] ?? '',
            'coverUrl': (m['coverUrl'] ?? m['cover'])?.toString(),
            'sourceUrl': m['sourceUrl'] ?? m['source_url'],
            'weather': m['weather'],
            'hotels': m['hotels'],
          };
        }).toList();
      }
      return {
        'isFurryCard': true,
        'isLoading': false,
        'isUser': false,
        'furryEvents': normalizedEvents,
        if (message['furryQuery'] is Map)
          'furryQuery': Map<String, dynamic>.from(
            (message['furryQuery'] as Map).map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          ),
        if (message['furryError'] != null)
          'furryError': message['furryError'].toString(),
        'isEmpty': message['isEmpty'] == true || normalizedEvents.isEmpty,
      };
    }
    return {
      'text': content,
      if (reasoning != null && reasoning.isNotEmpty) 'reasoning': reasoning,
      'isUser': role == 'user',
      'expanded': false,
      if (message['furryEvents'] is List) 'furryEvents': message['furryEvents'],
    };
  }

  List<Conversation> _buildConversationModels() {
    final activeUserId = currentUserNotifier.value?.id;
    return conversations
        .where((convo) => !isLocalConversation(convo['id']?.toString()))
        .map((convo) {
          final id = convo['id']?.toString() ?? '';
          final msgs = localConversationMessages[id] ?? [];
          final provider = convo['provider'] == sunlandProviderId
              ? sunlandProviderId
              : deepSeekProviderId;
          return Conversation(
            id: id,
            title: (convo['title'] ?? '新对话').toString(),
            history: [
              if (provider == deepSeekProviderId)
                const ChatMessage(
                  role: 'system',
                  content: deepSeekSystemPrompt,
                ),
              ...msgs
                  .map(_messageToCloud)
                  .whereType<Map<String, dynamic>>()
                  .map(ChatMessage.fromJson),
            ],
            updatedAt:
                int.tryParse((convo['updatedAt'] ?? '').toString()) ??
                DateTime.now().millisecondsSinceEpoch,
            provider: provider,
            model: provider == sunlandProviderId
                ? sunlandModelId
                : (convo['model'] == 'deepseek-v4-pro'
                      ? 'deepseek-v4-pro'
                      : 'deepseek-v4-flash'),
            userId: (convo['userId'] ?? activeUserId)?.toString(),
            createdAt:
                int.tryParse((convo['createdAt'] ?? id).toString()) ??
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
      final conversation = <String, dynamic>{
        'id': item.id,
        'title': item.title,
        'updatedAt': item.updatedAt,
        'titleGenerated': item.autoTitle,
        'provider': item.provider,
        'model': item.model,
        if (item.userId != null) 'userId': item.userId,
        'createdAt': item.createdAt,
      };
      convos.add(conversation);
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
      'provider': _activeProvider,
      'model': _activeProvider == sunlandProviderId
          ? sunlandModelId
          : currentModel,
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

      // ✅ 分开拉取，避免 Future.wait 类型推断问题
      final data = await supabase
          .from('conversations')
          .select('data')
          .eq('user_id', user.id)
          .maybeSingle();

      final tombstoneRows = await supabase
          .from('deleted_conversations')
          .select('conv_id')
          .eq('user_id', user.id);
      final deletedIds = <String>{
        for (final row in tombstoneRows) (row['conv_id'] ?? '').toString(),
      };

      if (data == null || data['data'] == null) {
        if (cached.isEmpty && mounted) {
          setState(() => conversations = []);
        }
        return;
      }

      final rawList = data['data'] as List;
      // ✅ 过滤掉已删除的对话再做合并
      final filteredList = rawList
          .whereType<Map>()
          .where((item) => !deletedIds.contains(item['id']?.toString()))
          .toList();

      final cloudModels = conversationsFromCloudRows(filteredList);

      // 本地缓存也过滤一次
      final filteredCached = cached
          .where((c) => !deletedIds.contains(c.id))
          .toList();

      final merged = mergeConversations(filteredCached, cloudModels);
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

      // ✅ 拉取墓碑列表（已删除的对话 ID）
      final tombstoneRows = await supabase
          .from('deleted_conversations')
          .select('conv_id')
          .eq('user_id', user.id);
      final deletedIds = <String>{
        for (final row in tombstoneRows) (row['conv_id'] ?? '').toString(),
      };

      // ✅ 基于时间戳的 CRDT 合并
      final merged = <String, Map<String, dynamic>>{};

      // 先加载云端数据
      final existing = await supabase
          .from('conversations')
          .select('data')
          .eq('user_id', user.id)
          .maybeSingle();

      if (existing?['data'] is List) {
        for (final item in existing!['data'] as List) {
          if (item is Map && item['id'] != null) {
            final itemId = item['id'].toString();
            // ✅ 跳过已删除的对话
            if (deletedIds.contains(itemId)) continue;
            merged[itemId] = Map<String, dynamic>.from(
              item.map((k, v) => MapEntry(k.toString(), v)),
            );
          }
        }
      }

      // 再用本地数据（只有时间戳更新的才覆盖，已删除的跳过）
      for (final model in models) {
        // ✅ 跳过已删除的对话
        if (deletedIds.contains(model.id)) continue;
        final cloudVersion = merged[model.id];
        if (cloudVersion == null ||
            model.updatedAt >
                (switch (cloudVersion['updatedAt']) {
                  final int v => v,
                  final double v => v.toInt(),
                  final String v => int.tryParse(v) ?? 0,
                  _ => 0,
                })) {
          final cloudConversation = <String, dynamic>{
            'id': model.id,
            'title': model.title,
            'history': model.history.map((m) => m.toJson()).toList(),
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
            'provider': model.provider,
            'model': model.model,
            if (model.userId != null) 'userId': model.userId,
            'createdAt': model.createdAt,
          };
          merged[model.id] = cloudConversation;
        }
      }

      // ✅ 保存合并后的结果（不含已删除对话）
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
    Map<String, dynamic>? target;
    for (final conversation in conversations) {
      if (conversation['id']?.toString() == id) {
        target = conversation;
        break;
      }
    }
    if (target?['provider'] == sunlandProviderId) {
      if (user == null) return;
      try {
        await sunlandProvider.deleteConversationContext(
          userId: user.id,
          conversationId: id,
        );
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('暂时无法清理 AI 上下文，请稍后再试')));
        }
        return;
      }
    }

    setState(() {
      conversations.removeWhere((c) => c['id'] == id);
      localConversationMessages.remove(id);

      if (currentConversationId == id) {
        currentConversationId = null;
        messages.clear();
        _lastQueryContext = null;
        _pendingProvider = deepSeekProviderId;
        useDeep = false;
        pickedImages.clear();
      }
    });

    // ⭐ 先写墓碑，再同步对话列表
    if (user != null) {
      try {
        await supabase.from('deleted_conversations').upsert({
          'user_id': user.id,
          'conv_id': id,
          'deleted_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id,conv_id');
      } catch (e) {
        debugPrint('Write tombstone error: $e');
      }
      await _saveToCloud();
    }
  }

  @override
  void initState() {
    super.initState();
    apiClient = SunlandApiClient(tokenProvider: _readFreshAuthToken);
    sunlandProvider = SunlandRemoteProvider(
      tokenProvider: ({bool forceRefresh = false}) =>
          _readFreshAuthToken(forceRefresh: forceRefresh),
    );
    repo = SupabaseAiRepository(
      tokenProvider: ({bool forceRefresh = false}) =>
          _readFreshAuthToken(forceRefresh: forceRefresh),
    );
    store = SunlandSessionStore();
    _initData();
    unawaited(_loadOcrPrivacyTipFlag());
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_recoverLostImagePickerData());
      });
    }
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
    await sunlandProvider.preserveLegacyState(user.id);
    await repo.ensureProfile(user.id); // ⭐ 再保险一层
    await loadConversations();
    await _checkActivation();

    if (!mounted) return;

    if (conversations.isNotEmpty) {
      final convo = conversations.first;
      setState(() {
        currentConversationId = convo["id"]?.toString();
        messages = normalizeMessages(
          List<Map<String, dynamic>>.from(
            localConversationMessages[currentConversationId] ?? [],
          ),
        );
        _applyProviderStateForConversation(convo);
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
        if (_isSunlandConversation) {
          useDeep = false;
          pickedImages.clear();
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
    final isSunlandRequest = _isSunlandConversation;
    if (isSunlandRequest && pickedImages.isNotEmpty) {
      setState(() => pickedImages.clear());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sunland AI 暂不支持图片或文件上传')));
    }
    // ⭐ 优先拦截 Pro 权限（避免被当成免费额度用尽）
    if (!isSunlandRequest &&
        !isActivated &&
        (currentModel == 'deepseek-v4-pro' || useDeep)) {
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
    if (!isSunlandRequest && !isActivated && _remainingCount <= 0) {
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
    final hasImages = !isSunlandRequest && pickedImages.isNotEmpty;
    if (text.isEmpty && !hasImages) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请输入内容")));
      setState(() => isGenerating = false);
      return;
    }
    final conversationAtStart = _currentConversation;
    if (isSunlandRequest) {
      if (user == null || conversationAtStart == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录状态好像出了点问题，请重新登录后再试一下。')),
        );
        setState(() => isGenerating = false);
        return;
      }
      conversationAtStart['userId'] ??= user.id;
      if (conversationAtStart['userId']?.toString() != user.id) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前对话不属于这个账户，请重新登录后再试。')));
        setState(() => isGenerating = false);
        return;
      }
    }
    final isRegenerate = text.isNotEmpty && text == _lastUserText;
    final imagePaths = List<String>.from(pickedImages);

    // ===== DeepSeek 视觉图片准备 + 可选本地 OCR（发送前完成）=====
    List<String> deepSeekImageDataUrls = const <String>[];
    ImageOcrResult? ocrResult;
    var preparationDialogShown = false;
    if (hasImages) {
      if (mounted) {
        preparationDialogShown = true;
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
                      Text('正在准备图片…'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }
      try {
        deepSeekImageDataUrls = await prepareDeepSeekVisionImages(
          imagePaths: imagePaths,
        ).timeout(const Duration(seconds: 20));

        if (supportsLocalImageOcr) {
          try {
            ocrResult = await extractTextFromImages(imagePaths)
                .timeout(const Duration(seconds: 8));
          } catch (e) {
            debugPrint('Optional OCR skipped: $e');
            ocrResult = const ImageOcrResult(block: '', hasUsableText: false);
          }
        }
      } on TimeoutException {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('图片处理超时，请减少图片数量后重试'),
              duration: Duration(seconds: 3),
            ),
          );
          setState(() => isGenerating = false);
        }
        return;
      } on ImagePreparationException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
          setState(() => isGenerating = false);
        }
        return;
      } catch (e) {
        debugPrint('Image preparation error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('图片处理失败，请重新选择后再试')));
          setState(() => isGenerating = false);
        }
        return;
      } finally {
        if (mounted && preparationDialogShown) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      }
    }

    if (!mounted || generationId != _generationSerial) {
      if (mounted) setState(() => isGenerating = false);
      return;
    }

    final ocrBlock = ocrResult?.hasUsableText == true ? ocrResult!.block : null;
    final mergedApiContent = buildApiMessageWithOcr(
      userText: text,
      ocrBlock: ocrBlock,
    );
    final apiContent = mergedApiContent.isNotEmpty
        ? mergedApiContent
        : '请分析这些图片。';

    if (hasImages &&
        supportsLocalImageOcr &&
        ocrResult != null &&
        ocrResult.hasUsableText &&
        ocrBlock != null &&
        mounted) {
      final block = ocrBlock;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认识别内容'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(block, style: const TextStyle(fontSize: 13, height: 1.4)),
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
        if (mounted) setState(() => isGenerating = false);
        return;
      }
    }

    if (!mounted || generationId != _generationSerial) {
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
    final requestUsesDeepThinking = !hasImages && isActivated && useDeep;
    final hapticRequest = _aiHaptics.beginRequest(
      deepThinking: requestUsesDeepThinking,
    );

    // ── 兽聚查询：与 AI 并行获取活动数据 ─────────────────────────────────
    // 查询范围由 AI 解析（_resolveFurryQueryParams），失败自动回退本地正则。
    final latestFurryCardBeforeSend = _latestFurryCard;
    final furryContextFollowUp =
        isSunlandRequest && _shouldAnswerFromFurryContext(text);
    Future<FurryEventSearchResult?>? furryFuture;
    if (_shouldSearchFurryEvents(text)) {
      furryFuture = () async {
        try {
          final params = isSunlandRequest
              ? _fallbackResolve(text)
              : await _resolveFurryQueryParams(text);
          return await FurryEventSearchApi.search(
            city: params.city,
            month: params.month,
            year: params.year,
          );
        } catch (_) {
          return null;
        }
      }();
    }

    final displayedUserText = text.isNotEmpty
        ? text
        : '已发送 ${imagePaths.length} 张图片';

    setState(() {
      if (!isRegenerate) {
        messages.add({
          "text": displayedUserText,
          "isUser": true,
          if (apiContent.isNotEmpty) "apiContent": apiContent,
          if (imagePaths.isNotEmpty)
            "imagePaths": List<String>.from(imagePaths),
        });
      }
      // 兽聚卡片占位符先于 AI 消息插入，数据到达后就地更新
      if (furryFuture != null) {
        messages.add({"isFurryCard": true, "isLoading": true, "isUser": false});
      }
      final isDeepMode = requestUsesDeepThinking;
      messages.add({
        "text": isDeepMode ? "深度思考中..." : "思考中...",
        "isUser": false,
        "isStreaming": true,
        "expanded": false,
      });
    });

    // 兽聚数据到达时立即更新占位符（与 AI 流并行，不阻塞）
    if (furryFuture != null) {
      unawaited(
        furryFuture.then((result) {
          if (!mounted || generationId != _generationSerial) return;
          final idx = messages.indexWhere(
            (m) => m["isFurryCard"] == true && m["isLoading"] == true,
          );
          if (idx == -1) return;
          setState(() {
            if (result != null) {
              final furryMaps = result.events.map((e) => e.toMap()).toList();
              debugPrint('furry count: ${furryMaps.length}');
              debugPrint(
                'first coverUrl: ${furryMaps.isNotEmpty ? furryMaps.first['coverUrl'] : 'empty'}',
              );
              messages[idx]['furryEvents'] = furryMaps;
              messages[idx]['furryQuery'] = Map<String, dynamic>.from(
                _lastQueryContext ?? const <String, dynamic>{},
              );

              messages[idx]['isEmpty'] = result.events.isEmpty;
              messages[idx]['isLoading'] = false;
            } else {
              messages[idx] = {
                "isFurryCard": true,
                "isEmpty": true,
                "isUser": false,
                "furryError": "兽聚查询失败",
                "furryQuery": Map<String, dynamic>.from(
                  _lastQueryContext ?? const <String, dynamic>{},
                ),
              };
            }
          });
          // 卡片渲染后高度变化，滚到底部避免被输入框遮住
          scrollToBottom();
        }),
      );
    }

    // Insert conversation and user message if needed
    rememberLocalMessages(); // ⭐ 防止新建对话前丢失当前内容

    if (currentConversationId == null) {
      final newId = DateTime.now().millisecondsSinceEpoch.toString();
      currentConversationId = newId;
      final provider = _pendingProvider == sunlandProviderId
          ? sunlandProviderId
          : deepSeekProviderId;
      conversations.insert(0, {
        'id': newId,
        'title': '新对话',
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'titleGenerated': false,
        'provider': provider,
        'model': provider == sunlandProviderId ? sunlandModelId : currentModel,
        'userId': user?.id,
        'createdAt': DateTime.now().millisecondsSinceEpoch,
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

    await _beginGenerationBackgroundTask();
    if (!mounted || generationId != _generationSerial) {
      await _endGenerationBackgroundTask();
      return;
    }

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
      unawaited(hapticRequest.aiStarted());

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

      if (isSunlandRequest) {
        if (furryFuture != null) {
          final furryResult = await furryFuture;
          if (_cancelRequested || generationId != _generationSerial) return;
          responseContent = _answerFurryEventQuestion(text, furryResult);
        } else if (furryContextFollowUp && latestFurryCardBeforeSend != null) {
          if ((latestFurryCardBeforeSend['furryError'] ?? '')
              .toString()
              .isNotEmpty) {
            responseContent = '这次兽聚数据暂时没有成功取回来，先别急着按空结果做计划，稍后再查一次会更稳妥 🐾';
          } else {
            responseContent = _answerFurryEventMaps(
              text,
              latestFurryCardBeforeSend['furryEvents'] is List
                  ? latestFurryCardBeforeSend['furryEvents'] as List<dynamic>
                  : const <dynamic>[],
              query: latestFurryCardBeforeSend['furryQuery'] is Map
                  ? Map<String, dynamic>.from(
                      (latestFurryCardBeforeSend['furryQuery'] as Map).map(
                        (key, value) => MapEntry(key.toString(), value),
                      ),
                    )
                  : null,
            );
          }
        } else {
          final activeConversation = conversationAtStart!;
          final result = await sunlandProvider.send(
            userId: user!.id,
            conversationUserId: activeConversation['userId'].toString(),
            conversationId: activeConversation['id'].toString(),
            input: text,
            turnId: '$generationId-${DateTime.now().microsecondsSinceEpoch}',
          );
          if (_cancelRequested || generationId != _generationSerial) return;
          responseContent = result.content;
          if (result.migrationWarning != null && mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(result.migrationWarning!)));
          }
        }
        if (responseContent.trim().isNotEmpty) {
          unawaited(hapticRequest.answerStarted());
        }
        streamActive = false;
        flushStreamingMessage(force: true);
      } else {
        // ===== 自动模型策略 + Pro 权限校验 =====
        String requestModel = hasImages ? 'deepseek-v4-flash' : _resolveModel();
        if (!isActivated) {
          useDeep = false;
        }

        // 自动策略：长文本/关键词触发 pro（仅 Pro 用户生效）
        if (!hasImages && isActivated && requestModel != 'deepseek-v4-pro') {
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
                    deep: requestUsesDeepThinking,
                    imageDataUrls: deepSeekImageDataUrls,
                    onRemainUpdated: (remain) {
                      final normalized = remain < 0
                          ? freeDailyLimit
                          : remain.clamp(0, freeDailyLimit).toInt();
                      if (user != null) {
                        unawaited(
                          store.saveRemainingCount(user.id, normalized),
                        );
                      }
                      if (!mounted || generationId != _generationSerial) return;
                      setState(() => _remainingCount = normalized);
                    },
                  )
                  .timeout(
                    Duration(seconds: hasImages ? 60 : 30),
                    onTimeout: (sink) {
                      streamTimedOut = true;
                      sink.close();
                    },
                  )
                  .listen(
                    (chunk) {
                      if (_cancelRequested ||
                          generationId != _generationSerial) {
                        _currentStreamSubscription?.cancel();
                        _currentStreamSubscription = null;
                        if (!completer.isCompleted) completer.complete();
                        return;
                      }

                      responseContent = chunk.content;
                      if (responseContent.trim().isNotEmpty) {
                        unawaited(hapticRequest.answerStarted());
                      }
                      if (requestUsesDeepThinking &&
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
          if (e is AuthExpiredException || e is UsageLimitException) {
            rethrow;
          }
          // 4xx 客户端错误（含 429）不重试，直接抛出；5xx 服务端瞬时错误允许重试一次
          if (e is ApiException &&
              (e.statusCode == null || e.statusCode! < 500)) {
            rethrow;
          }
          // retry once
          if (_cancelRequested || generationId != _generationSerial) return;
          // 重试等待期间恢复"思考中..."动画，避免用户看到空白
          if (mounted && messages.isNotEmpty) {
            setState(() {
              final last = messages.last;
              if (last["isUser"] != true) {
                last["text"] = requestUsesDeepThinking ? "深度思考中..." : "思考中...";
                last["reasoning"] = "";
              }
            });
          }
          await Future.delayed(const Duration(milliseconds: 800));
          // 重试开始前清空，准备接收流式内容
          if (mounted && messages.isNotEmpty && !_cancelRequested) {
            setState(() {
              final last = messages.last;
              if (last["isUser"] != true) last["text"] = "";
            });
          }
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
      }

      // ⭐ 图片发送完成后安全清空
      if (mounted && pickedImages.isNotEmpty) {
        setState(() => pickedImages.clear());
      }

      final activeIndex = conversations.indexWhere(
        (c) => c['id'] == currentConversationId,
      );
      if (activeIndex != -1) {
        conversations[activeIndex]['updatedAt'] =
            DateTime.now().millisecondsSinceEpoch;

        // ⭐ 自动更新对话标题（仅第一次，在保存前完成，避免 CRDT 竞争）
        final titleGenerated =
            conversations[activeIndex]['titleGenerated'] ?? false;
        final userMsgCount = messages.where((m) => m["isUser"] == true).length;
        if (userMsgCount == 1 && !titleGenerated) {
          conversations[activeIndex]['title'] = buildConversationTitle(
            displayedUserText,
          );
          conversations[activeIndex]['titleGenerated'] = true;
        }
      }

      rememberLocalMessages();
      if (user != null) await _saveToCloud();

      if (!mounted ||
          _cancelRequested ||
          generationId != _generationSerial) {
        return;
      }
      setState(() {
        isGenerating = false;
      });
      if (responseContent.trim().isNotEmpty) {
        unawaited(hapticRequest.answerCompleted());
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
        if (!mounted) return;
        setState(() => isGenerating = false);
        return;
      }

      if (e is UsageLimitException) {
        final normalized = e.remain.clamp(0, freeDailyLimit).toInt();
        if (user != null) {
          unawaited(store.saveRemainingCount(user.id, normalized));
        }
        if (!mounted) return;
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
              (e is ApiException && e.statusCode == 429)
                  ? "请求太频繁了，稍等片刻再试 ⏳"
                  : (e is ApiException && (e.statusCode ?? 0) >= 500)
                  ? "服务器开小差了，稍后再试试 🔧"
                  : e.toString().contains("timeout")
                  ? "请求超时了，稍后再试一下 ⏳"
                  : e.toString().contains("SocketException")
                  ? "网络好像断了，检查一下连接 🌐"
                  : "请求失败了，试试重新发送",
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }

      if (mounted) {
        setState(() {
          if (messages.isNotEmpty) {
            messages.removeLast();
          }
          messages.add({"text": e.toString(), "isUser": false});
          isGenerating = false;
        });
      }

      rememberLocalMessages();
    } finally {
      await _endGenerationBackgroundTask();
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
    unawaited(_endGenerationBackgroundTask());
    apiClient.close();
    unawaited(sunlandProvider.dispose());
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
    if (pickedImages.length >= maxImageAttachmentCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多添加 4 张图片')),
      );
      return;
    }
    if (!_ocrPrivacyTipShown && mounted) {
      await _markOcrPrivacyTipShown();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(kOcrPrivacyTip),
          duration: Duration(seconds: 4),
        ),
      );
    }

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final source = await showModalBottomSheet<_ImageAttachmentSource>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined),
                  title: const Text('拍照'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    _ImageAttachmentSource.camera,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('从相册选择'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    _ImageAttachmentSource.gallery,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.folder_open_outlined),
                  title: const Text('选择图片文件'),
                  subtitle: const Text('可从系统文件或 iCloud Drive 中选择'),
                  onTap: () => Navigator.pop(
                    sheetContext,
                    _ImageAttachmentSource.files,
                  ),
                ),
              ],
            ),
          ),
        );
        if (!mounted || source == null) return;

        switch (source) {
          case _ImageAttachmentSource.camera:
            final picked = await _imagePicker.pickImage(
              source: ImageSource.camera,
              imageQuality: 90,
              requestFullMetadata: false,
            );
            if (picked != null) {
              await _addImageAttachments([picked.path]);
            }
            break;
          case _ImageAttachmentSource.gallery:
            if (Platform.isIOS) {
              // pickMultiImage uses PHPicker and requires iOS 14+. Keep the
              // repository's iOS 13 deployment target working with single pick.
              final picked = await _imagePicker.pickImage(
                source: ImageSource.gallery,
                imageQuality: 90,
                requestFullMetadata: false,
              );
              if (picked != null) {
                await _addImageAttachments([picked.path]);
              }
            } else {
              final picked = await _imagePicker.pickMultiImage(
                imageQuality: 90,
                limit: maxImageAttachmentCount - pickedImages.length,
                requestFullMetadata: false,
              );
              await _addImageAttachments(picked.map((image) => image.path));
            }
            break;
          case _ImageAttachmentSource.files:
            await _pickImageFiles();
            break;
        }
        return;
      }

      await _pickImageFiles();
    } on PlatformException catch (error) {
      _showImagePickerError(error);
    } on FileSystemException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取所选图片，请将文件下载到本机后重试')),
      );
    }
  }

  Future<void> _pickImageFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    if (result == null || result.files.isEmpty) return;

    await _addImageAttachments(
      result.files.map((file) => file.path).whereType<String>(),
    );
  }

  Future<void> _recoverLostImagePickerData() async {
    try {
      final response = await _imagePicker.retrieveLostData();
      if (response.isEmpty) return;
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        await _addImageAttachments(files.map((file) => file.path));
        return;
      }
      final exception = response.exception;
      if (exception != null) {
        _showImagePickerError(exception);
      }
    } on PlatformException catch (error) {
      _showImagePickerError(error);
    }
  }

  Future<void> _addImageAttachments(Iterable<String> paths) async {
    final validation = await validateImageAttachments(
      candidatePaths: paths,
      existingPaths: pickedImages,
    );
    if (!mounted) return;

    if (validation.acceptedPaths.isNotEmpty) {
      setState(() => pickedImages.addAll(validation.acceptedPaths));
    }
    if (!validation.hasRejectedFiles) return;

    final reasons = <String>[];
    if (validation.limitExceededCount > 0) {
      reasons.add('最多添加 $maxImageAttachmentCount 张图片');
    }
    if (validation.tooLargeCount > 0) {
      reasons.add('单张图片不能超过 20 MB');
    }
    if (validation.unreadableCount > 0) {
      reasons.add('部分图片无法读取');
    }
    if (validation.duplicateCount > 0) {
      reasons.add('已忽略重复图片');
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(reasons.join('；'))));
  }

  void _showImagePickerError(PlatformException error) {
    if (!mounted) return;
    final code = error.code.toLowerCase();
    final message = code.contains('camera_access')
        ? '无法使用相机，请在系统设置中允许霜蓝AI访问相机'
        : code.contains('photo_access')
        ? '无法读取相册，请在系统设置中允许霜蓝AI访问照片'
        : code.contains('camera_unavailable')
        ? '当前设备没有可用相机'
        : '无法打开图片选择器，请稍后重试';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> pickAndUploadAvatar() async {
    final user = currentUserNotifier.value;
    if (user == null) return;

    XFile? picked;
    try {
      picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        requestFullMetadata: false,
      );
    } on PlatformException catch (error) {
      _showImagePickerError(error);
      return;
    }
    if (picked == null) return;
    if (!mounted) return;

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
    final backgroundTaskId = await _backgroundExecution.begin(
      name: 'Upload profile image',
    );
    if (!mounted) {
      await _backgroundExecution.end(backgroundTaskId);
      return;
    }

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
      await _backgroundExecution.end(backgroundTaskId);
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
      clearApplicationAuthState();
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
    String assetPath = 'assets/deepseek.png',
    String? label,
    String? description,
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
              assetPath,
              width: 18,
              height: 18,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label ?? "DeepSeek $name",
                  style: TextStyle(
                    fontSize: 13,
                    color: locked ? Colors.grey : null,
                  ),
                ),
                Text(
                  description ?? (name == "Pro" ? "更强推理能力" : "更快响应速度"),
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
    final isSunlandConversation = _isSunlandConversation;
    final isProviderLocked = _hasCurrentConversationStarted;

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
                      _lastQueryContext = null; // 新建对话：清空兽聚查询上下文
                      _pendingProvider = deepSeekProviderId;
                      useDeep = false;
                      pickedImages.clear();

                      conversations.insert(0, {
                        'id': newId,
                        'title': '新对话',
                        'updatedAt': DateTime.now().millisecondsSinceEpoch,
                        'provider': deepSeekProviderId,
                        'model': currentModel,
                        'userId': currentUserNotifier.value?.id,
                        'createdAt': DateTime.now().millisecondsSinceEpoch,
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
                                          _lastQueryContext =
                                              null; // 切换对话：清空兽聚查询上下文
                                          messages = normalizeMessages(
                                            List<Map<String, dynamic>>.from(
                                              localConversationMessages[currentConversationId] ??
                                                  [],
                                            ),
                                          );
                                          _applyProviderStateForConversation(
                                            convo,
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
                                            _lastQueryContext =
                                                null; // 切换对话：清空兽聚查询上下文
                                            messages = normalizeMessages(
                                              List<Map<String, dynamic>>.from(
                                                localConversationMessages[currentConversationId] ??
                                                    [],
                                              ),
                                            );
                                            _applyProviderStateForConversation(
                                              convo,
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
                                buildQuickBtn("🐾 查找下个月的兽聚"),
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
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 180),
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final isUser = msg["isUser"] == true;
                        return KeyedSubtree(
                          key: ValueKey(
                            i.toString() +
                                (msg["isReasoning"] == true ? "_r" : "_n"),
                          ),
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
                              child: buildMessageContent(msg, isUser, isDark),
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
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                    ),
                                    tooltip: isSunlandConversation
                                        ? 'Sunland AI 暂不支持文件上传'
                                        : '拍照或选择图片',
                                    onPressed: isSunlandConversation
                                        ? null
                                        : pickImage,
                                  ),

                                  GestureDetector(
                                    onTap: isSunlandConversation
                                        ? null
                                        : () {
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
                                        color:
                                            isSunlandConversation ||
                                                !isActivated
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
                                      if (isSunlandConversation &&
                                          isProviderLocked) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              '当前对话已绑定 Sunland AI，请新建对话后切换模型。',
                                            ),
                                          ),
                                        );
                                        return;
                                      }
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
                                                      name: "Sunland",
                                                      label:
                                                          "Sunland AI · Beta",
                                                      description:
                                                          "云端符号推理，不使用 DeepSeek",
                                                      assetPath:
                                                          'assets/studio.png',
                                                      locked: !sunlandProvider
                                                          .isSupported,
                                                      selected:
                                                          _activeProvider ==
                                                          sunlandProviderId,
                                                      onTap: () async {
                                                        final changed =
                                                            await _selectConversationProvider(
                                                              provider:
                                                                  sunlandProviderId,
                                                              model:
                                                                  sunlandModelId,
                                                            );
                                                        if (changed &&
                                                            dialogContext
                                                                .mounted) {
                                                          Navigator.pop(
                                                            dialogContext,
                                                          );
                                                        }
                                                      },
                                                    ),

                                                    _modelItem(
                                                      name: "Flash",
                                                      selected:
                                                          _activeProvider ==
                                                              deepSeekProviderId &&
                                                          currentModel.contains(
                                                            'flash',
                                                          ),
                                                      onTap: () async {
                                                        final changed =
                                                            await _selectConversationProvider(
                                                              provider:
                                                                  deepSeekProviderId,
                                                              model:
                                                                  'deepseek-v4-flash',
                                                            );
                                                        if (changed &&
                                                            dialogContext
                                                                .mounted) {
                                                          Navigator.pop(
                                                            dialogContext,
                                                          );
                                                        }
                                                      },
                                                    ),

                                                    _modelItem(
                                                      name: "Pro",
                                                      locked: !isActivated,
                                                      selected:
                                                          _activeProvider ==
                                                              deepSeekProviderId &&
                                                          currentModel.contains(
                                                            'pro',
                                                          ),
                                                      onTap: () async {
                                                        if (!isActivated) {
                                                          Navigator.pop(
                                                            dialogContext,
                                                          );
                                                          _showLimitSheet();
                                                          return;
                                                        }

                                                        final changed =
                                                            await _selectConversationProvider(
                                                              provider:
                                                                  deepSeekProviderId,
                                                              model:
                                                                  'deepseek-v4-pro',
                                                            );
                                                        if (changed &&
                                                            dialogContext
                                                                .mounted) {
                                                          Navigator.pop(
                                                            dialogContext,
                                                          );
                                                        }
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
                                      child: isSunlandConversation
                                          ? Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(5),
                                                  child: Image.asset(
                                                    'assets/studio.png',
                                                    width: 20,
                                                    height: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                const Text(
                                                  "Sunland AI · Beta",
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                  ),
                                                ),
                                                if (isProviderLocked) ...[
                                                  const SizedBox(width: 4),
                                                  const Icon(
                                                    Icons.lock,
                                                    size: 12,
                                                  ),
                                                ],
                                              ],
                                            )
                                          : Text(
                                              currentModel.contains('pro')
                                                  ? "Pro"
                                                  : "Flash",
                                              style: const TextStyle(
                                                fontSize: 12,
                                              ),
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

void _showEventDetailDialog(
  BuildContext context,
  Map<String, dynamic> event,
  bool isDark,
) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.9, end: 1.0),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          builder: (_, scale, child) {
            return Transform.scale(scale: scale, child: child);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2738) : Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event['name'] ?? '未知活动',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                Text("📍 ${event['city'] ?? ''} ${event['address'] ?? ''}"),
                const SizedBox(height: 6),
                Text(
                  "📅 ${event['startAt'] ?? event['start_at'] ?? ''} ~ ${event['endAt'] ?? event['end_at'] ?? ''}",
                ),
                const SizedBox(height: 10),
                if (event['raw_status'] != null)
                  Text("状态：${event['raw_status']}"),
                if (event['days_until'] != null)
                  Text("倒计时：${event['days_until']} 天"),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("关闭"),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ── 兽聚轮播卡片组件（独立 StatefulWidget，正确管理 PageController 生命周期）─────────────
class _FurryEventCarousel extends StatefulWidget {
  final List<dynamic> events;
  final bool isDark;
  final Widget Function(Map<String, dynamic>, bool) cardBuilder;

  const _FurryEventCarousel({
    required this.events,
    required this.isDark,
    required this.cardBuilder,
  });

  @override
  State<_FurryEventCarousel> createState() => _FurryEventCarouselState();
}

class _FurryEventCarouselState extends State<_FurryEventCarousel> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: 0.9,
      initialPage: 1000, // ⭐ 实现"无限循环"
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = widget.events;
    final isDark = widget.isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          '🐾 相关兽聚活动',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 280,
          child: PageView.builder(
            controller: _pageController,
            itemCount: events.isEmpty ? 0 : 2000, // ⭐ 假无限循环
            itemBuilder: (context, index) {
              final realIndex = index % events.length;
              final e = Map<String, dynamic>.from(events[realIndex] as Map);
              // 动态焦点缩放 + 居中吸附效果
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double scale = 0.95;
                  try {
                    if (_pageController.position.haveDimensions) {
                      final page =
                          _pageController.page ??
                          _pageController.initialPage.toDouble();
                      final diff = (page - index).abs();
                      scale = (1 - diff * 0.12).clamp(0.85, 1.0);
                    }
                  } catch (_) {}

                  final offset =
                      (_pageController.hasClients &&
                          _pageController.position.haveDimensions)
                      ? (_pageController.page! - index)
                      : 0.0;

                  return Transform.translate(
                    offset: Offset(offset * 20, 0), // ⭐ 横向堆叠位移
                    child: Transform.scale(
                      scale: scale,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: child,
                      ),
                    ),
                  );
                },
                child: widget.cardBuilder(e, isDark),
              );
            },
          ),
        ),
      ],
    );
  }
}
