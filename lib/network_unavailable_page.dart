import 'package:flutter/material.dart';

class NetworkUnavailablePage extends StatelessWidget {
  const NetworkUnavailablePage({
    super.key,
    required this.isChecking,
    required this.onRetry,
  });

  final bool isChecking;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
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
                        Image.asset(
                          'assets/network_unavailable.jpg',
                          width: 300,
                          fit: BoxFit.contain,
                          semanticLabel: '网络连接异常提示图',
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          '网络连接异常',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 24,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '请检查网络设置，连接正常后再刷新。',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
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
                                    '刷新',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
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
    );
  }
}
