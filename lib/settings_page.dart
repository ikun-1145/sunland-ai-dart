import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'main.dart';

import 'sunland_ai_core.dart';

class SettingsResult {
  const SettingsResult({this.user, this.loggedOut = false, this.activated});

  final SunlandUser? user;
  final bool loggedOut;
  final bool? activated;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.openActivationOnStart = false});

  final bool openActivationOnStart;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final SunlandSessionStore _store = SunlandSessionStore();
  late final SupabaseAiRepository _repository = SupabaseAiRepository();
  SunlandUser? _user;
  bool _isActivated = false;
  int _usageCount = 0;
  bool _loading = true;
  bool _uploadingAvatar = false;
  String? _avatarStatus;
  String? _nickname;
  bool _openedInitialActivation = false;
  String _version = '';
  Timer? _avatarStatusTimer;

  @override
  void initState() {
    super.initState();
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
      _openInitialActivationIfNeeded();
    } catch (e) {
      debugPrint('Settings load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      _openInitialActivationIfNeeded();
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
                    const Text(
                      '仅支持中英文、数字，最多20字符',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
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
                                Navigator.pop(context);
                                await _load();
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
  }

  void _openInitialActivationIfNeeded() {
    if (_openedInitialActivation ||
        !widget.openActivationOnStart ||
        _isActivated ||
        _user == null) {
      return;
    }
    _openedInitialActivation = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _activate();
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
    _avatarStatusTimer?.cancel();
    super.dispose();
  }

  User _userFromSunland(SunlandUser user) {
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

  Future<void> _activate() async {
    final user = _user;
    if (user == null) {
      _showSnack('请先登录');
      return;
    }

    final controller = TextEditingController();
    var submitting = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('输入激活码'),
              content: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'SL-XXXX-XXXX',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () {
                          Navigator.pop(dialogContext);
                          _showPaySheet();
                        },
                  child: const Text('扫码支付'),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          final code = controller.text.trim().toUpperCase();
                          if (code.isEmpty) {
                            _showSnack('请输入激活码');
                            return;
                          }
                          setDialogState(() => submitting = true);
                          try {
                            final result = await _repository.activateCode(
                              userId: user.id,
                              code: code,
                            );
                            if (!mounted) return;
                            switch (result) {
                              case ActivationResult.success:
                              case ActivationResult.alreadyActivated:
                                setState(() => _isActivated = true);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                _showSnack('激活成功，Pro 已解锁');
                                break;

                              case ActivationResult.invalidCode:
                                _showSnack('激活码无效');
                                break;

                              case ActivationResult.usedByOther:
                                _showSnack('这个激活码已被使用');
                                break;

                              case ActivationResult.raceLost:
                                _showSnack('激活失败，可能刚被使用');
                                break;
                            }
                          } catch (_) {
                            _showSnack('激活失败，请稍后再试');
                          } finally {
                            if (mounted) {
                              setDialogState(() => submitting = false);
                            }
                          }
                        },
                  child: submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('激活'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showPaySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '解锁 Pro · 永久使用',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  '一次付费，永久无限使用。支付后发送截图至 sunlandccc@outlook.com 获取激活码。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54, height: 1.5),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _PaymentQr(
                        label: '微信',
                        asset: 'assets/ten_wx.webp',
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _PaymentQr(
                        label: '支付宝',
                        asset: 'assets/ten_zfb.webp',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _activate();
                  },
                  child: const Text('我已有激活码'),
                ),
              ],
            ),
          ),
        );
      },
    );
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
      // 2.1 清除本地历史记录缓存（退出后不保留本地对话）
      try {
        await _store.clearAll(); // 若你的实现中没有该方法，请确保删除本地聊天/缓存数据
      } catch (_) {}

      // 3. 清空全局用户状态
      currentUserNotifier.value = null;

      if (!mounted) return;

      // 4. 跳转到登录页（清空返回栈）
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
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
                        width: 32,
                        height: 32,
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
                          onActivate: _activate,
                          onPay: _showPaySheet,
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
                : Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            activated ? 'Pro 会员' : '普通用户',
            style: TextStyle(
              color: activated ? const Color(0xFF7C3AED) : Colors.black54,
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
  const _ProPanel({
    required this.activated,
    required this.onActivate,
    required this.onPay,
  });

  final bool activated;
  final VoidCallback onActivate;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
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
        child: const Row(
          children: [
            Icon(Icons.workspace_premium, color: Color(0xFF7C3AED), size: 30),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '已是 Pro 会员',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: 3),
                  Text(
                    '深度思考与无限对话已解锁',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
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
          const Row(
            children: [
              Icon(Icons.diamond_outlined, color: Color(0xFF7C3AED), size: 30),
              SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('霜蓝 Pro', style: TextStyle(fontWeight: FontWeight.w700)),
                  SizedBox(height: 3),
                  Text('一次付费，永久解锁', style: TextStyle(color: Colors.black54)),
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
                      onTap: onActivate,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 14, color: Color(0xFF22C55E)),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _PaymentQr extends StatelessWidget {
  const _PaymentQr({required this.label, required this.asset});

  final String label;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(asset, fit: BoxFit.cover),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
        ),
      ],
    );
  }
}
