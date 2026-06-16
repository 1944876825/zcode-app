import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/storage/message_cache.dart';
import 'providers/app_providers.dart';
import 'shared/theme/app_router.dart';
import 'shared/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化本地消息缓存 (离线可见优化)。
  await Hive.initFlutter();
  await MessageCache.init();

  // 启动时从 SharedPreferences 恢复主题选择, 避免首帧闪烁。
  final prefs = await SharedPreferences.getInstance();
  final initialThemeMode =
      themeModeFromString(prefs.getString(kThemeModePrefKey));

  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider.overrideWith((ref) => initialThemeMode),
      ],
      child: const ZcodeApp(),
    ),
  );
}

class ZcodeApp extends ConsumerWidget {
  const ZcodeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'ZCode',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: goRouterProvider,
    );
  }
}
