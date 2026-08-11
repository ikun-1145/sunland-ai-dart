import 'package:flutter/material.dart';

import 'services/app_config_service.dart';

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({
    super.key,
    required this.config,
    required this.isChecking,
    required this.onRetry,
  });

  final AppConfig config;
  final bool isChecking;
  final Future<void> Function() onRetry;

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
                : const [Color(0xFFF0F9FF), Color(0xFFE0F2FE)],
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
                                0xFF22D3EE,
                              ).withValues(alpha: isDark ? 0.16 : 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.engineering_outlined,
                              size: 34,
                              color: Color(0xFF0891B2),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            config.maintenanceTitle,
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
                            config.maintenanceMessage,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),
                          if (config.maintenanceEstimatedEnd != null) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.white.withValues(alpha: 0.72),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.05),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.schedule_outlined,
                                    size: 18,
                                    color: Color(0xFF0891B2),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      '预计恢复时间：${_formatEstimatedEnd(config.maintenanceEstimatedEnd!)}',
                                      style: TextStyle(
                                        color: secondaryTextColor,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
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
                          const SizedBox(height: 14),
                          Text(
                            '服务恢复后即可继续使用，无需更新应用。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontSize: 12,
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

  String _formatEstimatedEnd(DateTime value) {
    final localValue = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${localValue.year}-${twoDigits(localValue.month)}-'
        '${twoDigits(localValue.day)} ${twoDigits(localValue.hour)}:'
        '${twoDigits(localValue.minute)}';
  }
}
