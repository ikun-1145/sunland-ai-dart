import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';

import 'sunland_ai_core.dart';

class SettingsResult {
  const SettingsResult({this.user, this.loggedOut = false, this.activated});

  final SunlandUser? user;
  final bool loggedOut;
  final bool? activated;
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.store,
    required this.repository,
    required this.user,
  });

  final SunlandSessionStore store;
  final SupabaseAiRepository repository;
  final SunlandUser? user;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SunlandUser? _user;
  bool _isActivated = false;
  int _usageCount = 0;
  bool _loading = true;
  bool _uploadingAvatar = false;
  String? _avatarStatus;

  @override
  void initState() {
    super.initState();
    _user = widget.user;
    unawaited(_load());
  }

  Future<void> _load() async {
    final user = _user;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    UserProfile? cached = await widget.store.readProfile(user.id);
    if (cached?.hasAvatar == true && mounted) {
      setState(() {
        _user = user.copyWith(
          avatarUrl: cached!.avatarUrl,
          avatarPath: cached.avatarPath,
        );
      });
    }

    try {
      final isActivated = await widget.repository.isActivated(user.id);
      final usage = await widget.repository.usageCount(user.id);
      final cloudProfile = await widget.repository.loadProfile(user.id);
      SunlandUser updatedUser = _user ?? user;
      if (cloudProfile?.hasAvatar == true) {
        updatedUser = updatedUser.copyWith(
          avatarUrl: cloudProfile!.avatarUrl,
          avatarPath: cloudProfile.avatarPath,
        );
        await widget.store.saveProfile(user.id, cloudProfile);
        await widget.store.saveUser(updatedUser);
      }
      if (!mounted) return;
      setState(() {
        _user = updatedUser;
        _isActivated = isActivated;
        _usageCount = usage;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar() async {
    final user = _user;
    if (user == null || _uploadingAvatar) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 768,
      maxHeight: 768,
      imageQuality: 82,
    );
    if (picked == null) return;

    final file = File(picked.path);
    if (!await file.exists()) return;
    final size = await file.length();
    if (size > 8 * 1024 * 1024) {
      _showSnack('图片太大，请选择 8MB 内的图片');
      return;
    }

    setState(() {
      _uploadingAvatar = true;
      _avatarStatus = '正在上传头像...';
    });

    try {
      final profile = await widget.repository.uploadAvatar(
        userId: user.id,
        file: file,
      );
      await widget.repository.saveProfile(user.id, profile);
      await widget.store.saveProfile(user.id, profile);
      final updated = user.copyWith(
        avatarUrl: profile.avatarUrl,
        avatarPath: profile.avatarPath,
      );
      await widget.store.saveUser(updated);
      if (!mounted) return;
      setState(() {
        _user = updated;
        _avatarStatus = '头像已保存';
      });
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _avatarStatus = null);
      });
    } catch (error) {
      if (!mounted) return;
      debugPrint(error.toString());
      setState(() => _avatarStatus = '上传失败，请检查网络');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
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
                            final result = await widget.repository.activateCode(
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
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
          content: const Text('本机仍会保留已同步的历史缓存。'),
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
    await widget.store.clearSession();
    if (!mounted) return;
    Navigator.pop(context, const SettingsResult(loggedOut: true));
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              color: isDark
                  ? Colors.black.withOpacity(0.25)
                  : Colors.white.withOpacity(0.4),
            ),
          ),
        ),
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
          gradient: LinearGradient(
            colors: isDark
                ? [Color(0xFF0B0F1A), Color(0xFF111827)]
                : [Color(0xFFEAF4FF), Color(0xFFF7FBFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
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
                  ? const Center(child: CircularProgressIndicator())
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
                          children: [
                            _AvatarHeader(
                              user: user,
                              uploading: _uploadingAvatar,
                              status: _avatarStatus,
                              onTap: _pickAvatar,
                              activated: _isActivated,
                            ),
                            const SizedBox(height: 28),
                            _SectionTitle('账号'),
                            _SettingsCard(
                              children: [
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
                            // --- Theme Switcher Section ---
                            _SectionTitle('外观'),
                            _SettingsCard(
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.palette_outlined),
                                  title: const Text('主题模式'),
                                  subtitle: Text(
                                    Theme.of(context).brightness ==
                                            Brightness.dark
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
                            // --- End Theme Switcher Section ---
                            _SectionTitle('今日使用'),
                            _SettingsCard(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                          backgroundColor: const Color(
                                            0xFFE0F2FE,
                                          ),
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
                            _SectionTitle('会员'),
                            _ProPanel(
                              activated: _isActivated,
                              onActivate: _activate,
                              onPay: _showPaySheet,
                            ),
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
                                '霜蓝 AI · v1.0.0 beta · 数据安全存储于云端',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      _showSnack('暂时无法打开链接');
    }
  }
}

class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({
    required this.user,
    required this.uploading,
    required this.status,
    required this.onTap,
    required this.activated,
  });

  final SunlandUser? user;
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
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF22D3EE), Color(0xFFA78BFA)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF22D3EE).withOpacity(0.25),
                      blurRadius: 32,
                      spreadRadius: 4,
                    ),
                  ],
                ),
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
                const SizedBox(
                  width: 92,
                  height: 92,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
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
          user?.email ?? '未登录',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
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
          style: const TextStyle(color: Colors.black45, fontSize: 12),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          color: isDark ? Colors.white38 : Colors.black45,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withOpacity(0.04)
                : Colors.white.withOpacity(0.5),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.12)
                  : Colors.white.withOpacity(0.7),
            ),
          ),
          child: Column(children: children),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF0891B2)),
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
    final color = danger ? Colors.redAccent : const Color(0xFF0891B2);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: danger ? Colors.redAccent : null),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
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
          gradient: const LinearGradient(
            colors: [Color(0x3322D3EE), Color(0x33A78BFA)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x5522D3EE)),
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
        gradient: const LinearGradient(
          colors: [Color(0x5522D3EE), Color(0x55A78BFA)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x3322D3EE)),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF22D3EE).withOpacity(0.25),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
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
              _FeatureChip('优先响应速度'),
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
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
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
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onPay,
                  child: const Text('¥10 永久'),
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
