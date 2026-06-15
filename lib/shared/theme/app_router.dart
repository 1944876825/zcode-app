import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/chat/screens/chat_screen.dart';
import '../../features/workspace/screens/main_screen.dart';
import '../../features/workspace/screens/workspace_list_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

/// 路由名称
class AppRoutes {
  AppRoutes._();

  static const String splash = '/splash';
  static const String login = '/login';
  static const String home = '/';
  static const String workspaceList = '/workspaces';
  static const String chat = '/chat';
  static const String settings = '/settings';
}

/// GoRouter 配置
final goRouterProvider = GoRouter(
  initialLocation: AppRoutes.splash,
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const MainScreen(),
      routes: [
        GoRoute(
          path: 'workspaces',
          builder: (context, state) => const WorkspaceListScreen(),
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.chat,
      builder: (context, state) {
        final workspaceKey = state.uri.queryParameters['workspace'] ?? '';
        final taskId = state.uri.queryParameters['task'];
        return ChatScreen(
          workspaceKey: workspaceKey,
          taskId: taskId,
        );
      },
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64),
          const SizedBox(height: 16),
          Text('页面不存在: ${state.uri}'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('返回首页'),
          ),
        ],
      ),
    ),
  ),
);
