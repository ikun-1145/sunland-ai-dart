import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';

import 'pro_purchase.dart';
import 'sunland_ai_core.dart';

class SettingsResult {
  const SettingsResult({this.user, this.loggedOut = false, this.activated});

  final SunlandUser? user;
  final bool loggedOut;
  final bool? activated;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.openProPurchaseOnStart = false});

  final bool openProPurchaseOnStart;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  late final SunlandSessionStore _store = SunlandSessionStore();
  late final SupabaseAiRepository _repository = SupabaseAiRepository(
    tokenProvider: ({bool forceRefresh = false}) =>
        readFreshAuthToken(forceRefresh: forceRefresh),
  );
  SunlandUser? _user;
  bool _isActivated = false;
  int _usageCount = 0;
  bool _loading = true;
  bool _uploadingAvatar = false;
  String? _avatarStatus;
  String? _nickname;
  bool _openedInitialProPurchase = false;
  String _version = '';
  Timer? _avatarStatusTimer;
  Timer? _proActivationPollingTimer;
  DateTime? _proActivationPollingDeadline;
  bool _awaitingProActivation = false;
  bool _checkingProActivation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final rawUser = currentUserNotifier.value;
    if (rawUser != null) {
      _user = SunlandUser(id: rawUser.id, email: rawUser.email ?? '');
      _nickname = null;
    } else {
      _user = null;
    }
    _load();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _version = '${info.version} (${info.buildNumber})';
    });
  }

  Future<void> _load() async {
    if (mounted && !_loading) setState(() => _loading = true);
    final user = _user;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    UserProfile? cached = await _store.readProfile(user.id);
    if (cached?.hasAvatar == true && mounted) {
      setState(() {
        _user = user.copyWith(
          avatarUrl: cached!.avatarUrl,
          avatarPath: cached.avatarPath,
        );
      });
    }

    try {
      final isActivated = await _repository.isActivated(user.id);
      final remaining = await _store.readRemainingCount(user.id);
      final cloudProfile = await _repository.loadProfile(user.id);
      final nickname = await _repository.loadNickname(user.id);
      final updatedUser = _user ?? user;
      var finalUser = updatedUser;
      if (cloudProfile?.hasAvatar == true) {
        finalUser = updatedUser.copyWith(
          avatarUrl: cloudProfile!.avatarUrl,
          avatarPath: cloudProfile.avatarPath,
        );
        await _store.saveProfile(user.id, cloudProfile);
        await _store.saveUser(finalUser);
      }
      if (!mounted) return;
      setState(() {
        _user = finalUser;
        _isActivated = isActivated;
        _usageCount = isActivated ? 0 : freeDailyLimit - remaining;
        _loading = false;
        _nickname = nickname;
      });
      _openInitialProPurchaseIfNeeded();
    } catch (e) {
      debugPrint('Settings load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _openInitialProPurchaseIfNeeded();
    }
  }

  Future<void> _editNickname() async {
    final controller = TextEditingController(text: _nickname ?? '');

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '修改昵称',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: controller,
                      maxLength: 20,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: '输入新的昵称',
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  controller.clear();
                                  setStateDialog(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '仅支持中英文、数字，最多20字符',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final newName = controller.text.trim();
                              final valid = RegExp(
                                r'^[a-zA-Z0-9\u4e00-\u9fa5_]+$',
                              );
                              if (newName.isEmpty) {
                                _showSnack('昵称不能为空');
                                return;
                              }
                              if (!valid.hasMatch(newName)) {
                                _showSnack('昵称包含非法字符');
                                return;
                              }
                              try {
                                await _repository.saveNickname(
                                  _user!.id,
                                  newName,
                                );
                                if (!mounted) return;
                                if (context.mounted) Navigator.pop(context);
                                await _load();
                                // 同步到全局用户，主页问候语立即刷新
                                if (_user != null) {
                                  final withName = _user!.copyWith(
                                    name: newName,
                                  );
                                  currentUserNotifier.value = _userFromSunland(
                                    withName,
                                  );
                                }
                                _showSnack('昵称已更新');
                              } catch (e) {
                                debugPrint('昵称保存错误: $e');
                                _showSnack('保存失败');
                              }
                            },
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text('保存'),
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
      },
    );
    controller.dispose();
  }

  void _openInitialProPurchaseIfNeeded() {
    if (_openedInitialProPurchase ||
        !widget.openProPurchaseOnStart ||
        _isActivated ||
        _user == null) {
      return;
    }
    _openedInitialProPurchase = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startProPurchase();
    });
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      final user = _user;
      if (user == null) return;

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 768,
        maxHeight: 768,
        imageQuality: 82,
      );
      if (picked == null) return;

      // === 格式限制（仅允许常见图片格式） ===
      final path = picked.path.toLowerCase();
      final allowed = ['.jpg', '.jpeg', '.png', '.webp'];
      final isValidFormat = allowed.any((ext) => path.endsWith(ext));
      if (!isValidFormat) {
        _showSnack('仅支持 JPG / PNG / WEBP 格式图片');
        return;
      }

      final file = File(picked.path);
      if (!await file.exists()) return;
      final size = await file.length();
      // === 0 字节文件安全检查 ===
      if (size == 0) {
        _showSnack('图片文件异常，请重新选择');
        return;
      }
      if (size > 8 * 1024 * 1024) {
        _showSnack('图片太大，请选择 8MB 内的图片');
        return;
      }

      setState(() {
        _avatarStatus = '正在上传头像...';
      });

      try {
        final profile = await _repository.uploadAvatar(
          userId: user.id,
          file: file,
        );
        await _repository.saveProfile(user.id, profile);
        await _store.saveProfile(user.id, profile);
        final updated = user.copyWith(
          avatarUrl: profile.avatarUrl,
          avatarPath: profile.avatarPath,
        );
        await _store.saveUser(updated);
        if (!mounted) return;
        setState(() {
          _user = updated;
          _avatarStatus = '头像已保存';
        });

        // ⭐ 同步到全局用户（修复主页头像不更新问题）
        currentUserNotifier.value = _userFromSunland(updated);
      } catch (error) {
        if (!mounted) return;
        debugPrint(error.toString());
        setState(() => _avatarStatus = '上传失败，请检查网络');
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }

    _avatarStatusTimer?.cancel();
    _avatarStatusTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _avatarStatus = null);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _avatarStatusTimer?.cancel();
    _proActivationPollingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingProActivation) {
      unawaited(_checkPurchasedPro());
    }
  }

  User _userFromSunland(SunlandUser user) {
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

  Future<void> _startProPurchase() async {
    final user = _user;
    if (user == null) {
      _showSnack('请先登录');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('前往爱发电开通 Pro？'),
          content: const Text(
            '请选择“月付”方案（¥10 / 月）即可。付款成功后将自动开通永久 Pro，'
            '无需多选月份，多付不会增加权益。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('前往支付'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) return;

    final uri = buildProPurchaseUri(user.id);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!mounted) return;
      if (!opened) {
        _showSnack('暂时无法打开爱发电，请稍后再试');
        return;
      }
      _startProActivationPolling();
    } catch (error) {
      debugPrint('Open Pro purchase error: $error');
      if (mounted) _showSnack('暂时无法打开爱发电，请稍后再试');
    }
  }

  void _startProActivationPolling() {
    _proActivationPollingTimer?.cancel();
    _awaitingProActivation = true;
    _proActivationPollingDeadline = DateTime.now().add(
      const Duration(minutes: 3),
    );
    unawaited(_checkPurchasedPro());
    _proActivationPollingTimer = Timer.periodic(const Duration(seconds: 3), (
      timer,
    ) {
      final deadline = _proActivationPollingDeadline;
      if (deadline == null || DateTime.now().isAfter(deadline)) {
        timer.cancel();
        _proActivationPollingTimer = null;
        _awaitingProActivation = false;
        if (mounted) {
          _showSnack('开通处理中，付款成功后约 1-2 分钟自动生效，可稍后刷新');
        }
        return;
      }
      unawaited(_checkPurchasedPro());
    });
  }

  Future<void> _checkPurchasedPro() async {
    if (!_awaitingProActivation || _checkingProActivation) return;
    final user = _user;
    if (user == null) return;

    _checkingProActivation = true;
    try {
      final activated = await _repository.isActivated(user.id);
      if (!mounted ||
          !_awaitingProActivation ||
          _user?.id != user.id ||
          !activated) {
        return;
      }
      _proActivationPollingTimer?.cancel();
      _proActivationPollingTimer = null;
      _awaitingProActivation = false;
      setState(() => _isActivated = true);
      _showSnack('支付成功，Pro 已解锁');
    } catch (error) {
      debugPrint('Refresh Pro status error: $error');
    } finally {
      _checkingProActivation = false;
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('退出登录？'),
          content: const Text('将清除本机登录状态与本地历史记录；重新登录后会从云端同步。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      // 1. Supabase 退出登录
      await Supabase.instance.client.auth.signOut();

      // 2. 清除本地登录状态
      await _store.clearSession();
      clearApplicationAuthState();
      // 2.1 清除本地历史记录缓存（退出后不保留本地对话）
      try {
        await _store.clearAll(); // 若你的实现中没有该方法，请确保删除本地聊天/缓存数据
      } catch (_) {}

      // 3. 清空全局用户状态
      currentUserNotifier.value = null;

      if (!mounted) return;

      // 4. 返回 ChatPage，由其处理跳转到登录页
      Navigator.of(context).pop(const SettingsResult(loggedOut: true));
    } catch (e) {
      _showSnack('退出失败，请重试');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = _user;
    final remain = _isActivated
        ? freeDailyLimit
        : (freeDailyLimit - _usageCount).clamp(0, freeDailyLimit);
    final usageFraction = _isActivated ? 1.0 : remain / freeDailyLimit;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: Stack(
          children: [
            Positioned(
              top: -80,
              left: -60,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x5522D3EE), Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x55A78BFA), Colors.transparent],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: _loading
                  ? Center(
                      child: Image.asset(
                        'assets/loading.gif',
                        width: 64,
                        height: 64,
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                      children: [
                        _AvatarHeader(
                          user: user,
                          nickname: _nickname,
                          uploading: _uploadingAvatar,
                          status: _avatarStatus,
                          onTap: _pickAvatar,
                          activated: _isActivated,
                        ),
                        const SizedBox(height: 20),
                        _SectionTitle('账号'),
                        _SettingsCard(
                          children: [
                            _ActionRow(
                              icon: Icons.person,
                              label: '昵称',
                              onTap: _editNickname,
                            ),
                            _InfoRow(
                              icon: Icons.alternate_email,
                              label: '邮箱',
                              value: user?.email ?? '未登录',
                            ),
                            _InfoRow(
                              icon: Icons.badge_outlined,
                              label: '用户 ID',
                              value: user?.id != null && user!.id.length > 8
                                  ? user.id.substring(0, 8)
                                  : (user?.id ?? '--'),
                              monospace: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // --- Theme Switcher Section ---
                        _SectionTitle('外观'),
                        _SettingsCard(
                          children: [
                            ListTile(
                              leading: const Icon(Icons.palette_outlined),
                              title: const Text('主题模式'),
                              subtitle: Text(
                                Theme.of(context).brightness == Brightness.dark
                                    ? '深色模式'
                                    : '浅色模式',
                              ),
                              trailing: PopupMenuButton<ThemeMode>(
                                onSelected: (mode) {
                                  themeNotifier.value = mode;
                                  saveThemeMode(mode);
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: ThemeMode.light,
                                    child: Text('浅色模式'),
                                  ),
                                  PopupMenuItem(
                                    value: ThemeMode.dark,
                                    child: Text('深色模式'),
                                  ),
                                  PopupMenuItem(
                                    value: ThemeMode.system,
                                    child: Text('跟随系统'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // --- End Theme Switcher Section ---
                        _SectionTitle('今日使用'),
                        _SettingsCard(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(
                                            Icons.query_stats,
                                            color: Color(0xFF0891B2),
                                          ),
                                          SizedBox(width: 10),
                                          Text(
                                            '剩余次数',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      Text(
                                        _isActivated ? '∞' : '$remain 次',
                                        style: const TextStyle(
                                          color: Color(0xFF0891B2),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: usageFraction,
                                      minHeight: 7,
                                      backgroundColor: const Color(0xFFE0F2FE),
                                      color: const Color(0xFF22D3EE),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _isActivated
                                        ? 'Pro 会员 · 无限次对话'
                                        : '每天重置 20 次免费额度',
                                    style: TextStyle(
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black45,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _SectionTitle('会员'),
                        _ProPanel(
                          activated: _isActivated,
                          onPurchase: _startProPurchase,
                        ),
                        const SizedBox(height: 10),
                        _SectionTitle('其他'),
                        _SettingsCard(
                          children: [
                            _ActionRow(
                              icon: Icons.description_outlined,
                              label: '用户协议',
                              onTap: () => _openExternal(
                                'https://sunland.dev/xukexieyi.html',
                              ),
                            ),
                            _ActionRow(
                              icon: Icons.privacy_tip_outlined,
                              label: '隐私政策',
                              onTap: () => _openExternal(
                                'https://sunland.dev/privacy.html',
                              ),
                            ),
                            _ActionRow(
                              icon: Icons.logout,
                              label: '退出登录',
                              danger: true,
                              onTap: _logout,
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Center(
                          child: Text(
                            '霜蓝 AI · v$_version · 数据安全存储于云端',
                            style: TextStyle(
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _showSnack('暂时无法打开链接');
    } catch (_) {
      _showSnack('暂时无法打开链接');
    }
  }
}

class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({
    required this.user,
    required this.nickname,
    required this.uploading,
    required this.status,
    required this.onTap,
    required this.activated,
  });

  final SunlandUser? user;
  final String? nickname;
  final bool uploading;
  final String? status;
  final VoidCallback onTap;
  final bool activated;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = user?.avatarUrl;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        GestureDetector(
          onTap: uploading ? null : onTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: CircleAvatar(
                  backgroundColor: Colors.white,
                  backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                      ? NetworkImage(avatarUrl)
                      : null,
                  child: avatarUrl == null || avatarUrl.isEmpty
                      ? Text(
                          user?.initial ?? '?',
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        )
                      : null,
                ),
              ),
              if (uploading)
                Image.asset('assets/loading.gif', width: 48, height: 48),
              const Positioned(
                right: 2,
                bottom: 2,
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: Color(0xFF0F172A),
                  child: Icon(Icons.camera_alt, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          (nickname != null && nickname!.isNotEmpty)
              ? nickname!
              : (user?.email ?? '未登录'),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: activated
                ? const Color(0xFFA78BFA).withValues(alpha: 0.18)
                : colorScheme.onSurface.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            activated ? 'Pro 会员' : '普通用户',
            style: TextStyle(
              color: activated
                  ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFFC4B5FD)
                        : const Color(0xFF7C3AED))
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          status ?? '点击头像上传新头像',
          style: TextStyle(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white38
                : Colors.black45,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).hintColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: List.generate(children.length * 2 - 1, (index) {
            if (index.isEven) return children[index ~/ 2];
            return Divider(height: 1, indent: 56);
          }),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.monospace = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontFamily: monospace ? 'monospace' : null,
                fontSize: monospace ? 11 : 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? Colors.redAccent
        : Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ListTile(
          leading: Icon(icon, color: color),
          title: Text(
            label,
            style: TextStyle(color: danger ? Colors.redAccent : null),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        ),
      ),
    );
  }
}

class _ProPanel extends StatelessWidget {
  const _ProPanel({required this.activated, required this.onPurchase});

  final bool activated;
  final VoidCallback onPurchase;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (activated) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).dividerColor.withOpacity(0.18),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.workspace_premium,
              color: Color(0xFF7C3AED),
              size: 30,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '已是 Pro 会员',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '深度思考与无限对话已解锁',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.diamond_outlined,
                color: Color(0xFF7C3AED),
                size: 30,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '霜蓝 Pro',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '一次付费，永久解锁',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FeatureChip('无限次对话'),
              _FeatureChip('深度思考模式'),
              _FeatureChip('V4 Pro模型访问权限'),
              _FeatureChip('永久有效'),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF22D3EE), Color(0xFFA78BFA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF22D3EE).withOpacity(0.3),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: onPurchase,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: Text(
                            '立即升级 · ¥10 永久',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 14, color: Color(0xFF22C55E)),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
