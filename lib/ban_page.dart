import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/user_status_service.dart';

class BanPage extends StatelessWidget {
  const BanPage({
    super.key,
    required this.status,
    required this.isChecking,
    required this.onRetry,
  });

  static const appealEmail = 'support@sunland.dev';

  final UserStatus status;
  final bool isChecking;
  final Future<void> Function() onRetry;

  Future<void> _copyAppealEmail(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: appealEmail));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('申诉邮箱已复制')));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final secondaryTextColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F1A) : Colors.white,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? const [Color(0xFF0B0F1A), Color(0xFF020617)]
                : const [Color(0xFFF8FAFC), Color(0xFFEFF6FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight > 64
                        ? constraints.maxHeight - 64
                        : 0,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFEF4444,
                              ).withValues(alpha: isDark ? 0.14 : 0.10),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_off_outlined,
                              size: 34,
                              color: Color(0xFFDC2626),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            '账号已限制使用',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 26,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            '你的账号目前无法使用 Sunland AI。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),
                          if (status.banReason != null) ...[
                            const SizedBox(height: 22),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.white.withValues(alpha: 0.82),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '原因：',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    status.banReason!,
                                    style: TextStyle(
                                      color: secondaryTextColor,
                                      fontSize: 14,
                                      height: 1.55,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 28),
                          Text(
                            '如果认为这是误判，可以发送邮件申诉：',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 13,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const SelectableText(
                            appealEmail,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF0891B2),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: FilledButton(
                              onPressed: isChecking
                                  ? null
                                  : () async {
                                      await onRetry();
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF22D3EE),
                                foregroundColor: const Color(0xFF0F172A),
                                disabledBackgroundColor: const Color(
                                  0xFF22D3EE,
                                ).withValues(alpha: 0.55),
                                disabledForegroundColor: const Color(
                                  0xFF0F172A,
                                ).withValues(alpha: 0.65),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isChecking
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Color(0xFF0F172A),
                                      ),
                                    )
                                  : const Text(
                                      '重新检查',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 46,
                            child: OutlinedButton.icon(
                              onPressed: () => _copyAppealEmail(context),
                              icon: const Icon(Icons.copy_outlined, size: 18),
                              label: const Text('复制邮箱'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: isDark
                                    ? Colors.white
                                    : const Color(0xFF334155),
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.black12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
