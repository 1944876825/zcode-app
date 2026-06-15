import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/app_providers.dart';
import 'workspace_list_screen.dart';
import '../../settings/screens/settings_screen.dart';

/// 主页 — 底部导航 (工作区 / 技能 / 我的)
class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // 连接 relay 并加载工作区
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(workspaceListProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(relayConnectionStateProvider);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const WorkspaceListScreen(),
          _buildSkillsTab(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.work_outline),
            selectedIcon: Icon(Icons.work),
            label: '工作区',
          ),
          const NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: '技能',
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsTab() {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              '技能中心',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '技能管理功能将在 Phase 3 上线',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
