import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../shared/theme/app_design_tokens.dart';
import '../../../../shared/theme/app_router.dart';
import '../../../providers/app_providers.dart';

/// 启动页 — 黑底 + Z logo,与原生 launch_background.xml 无缝衔接。
/// 检查 session 后决定跳转登录或主页。
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    );
    _controller.forward();
    _checkSession();
  }

  Future<void> _checkSession() async {
    await Future.delayed(const Duration(milliseconds: 600));

    if (!mounted) return;

    final session = ref.read(sessionProvider);
    session.when(
      data: (s) {
        if (s != null && s.isValid) {
          context.go(AppRoutes.home);
        } else {
          context.go(AppRoutes.login);
        }
      },
      loading: () {
        // 等待加载完成
        Future.delayed(const Duration(milliseconds: 300), _checkSession);
      },
      error: (_, __) {
        context.go(AppRoutes.login);
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 与原生 launch_background.xml 的 @color/ic_launcher_background 完全一致
      backgroundColor: AppColors.darkBg,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Z logo — 与启动器图标同源
              Image.asset(
                'assets/images/app_icon.png',
                width: 112,
                height: 112,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 56),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.white.withValues(alpha: 0.5),
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
