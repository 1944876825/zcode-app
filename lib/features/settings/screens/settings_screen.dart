import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/relay/relay_protocol.dart';
import '../../../providers/app_providers.dart';

/// 设置页
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider);
    final connectionAsync = ref.watch(relayConnectionStateProvider);

    final user = session.valueOrNull;
    final userName = user?.deviceName ?? '未登录';
    final deviceId = user?.deviceSid ?? '—';

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        children: [
          // 用户信息卡片
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: 0.7),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: const Icon(Icons.person, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            userName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '设备: $deviceId',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 连接状态
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi,
                          size: 16, color: Colors.white.withValues(alpha: 0.9)),
                      const SizedBox(width: 8),
                      Text(
                        connectionAsync.maybeWhen(
                          data: (state) {
                            final s = state;
                            return switch (s) {
                              RelayConnectionState.ready => '已连接到 ZCode',
                              RelayConnectionState.connecting => '正在连接...',
                              RelayConnectionState.reconnecting => '正在重连...',
                              RelayConnectionState.disconnected => '未连接',
                              _ => '—',
                            };
                          },
                          orElse: () => '—',
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 设置项
          _SectionHeader(title: '模型设置'),
          ListTile(
            leading: const Icon(Icons.smart_toy_outlined),
            title: const Text('默认模型'),
            subtitle: const Text('GLM-5.2'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('模型选择功能将在 Phase 2 上线')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('默认模式'),
            subtitle: const Text('变更前确认'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              _showModeDialog(context);
            },
          ),

          _SectionHeader(title: '外观'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('主题'),
            subtitle: const Text('跟随系统'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('主题设置即将上线')),
              );
            },
          ),

          _SectionHeader(title: '关于'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('版本'),
            subtitle: const Text('ZCode App v1.0.0 (Phase 1)'),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('开源协议'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),

          const SizedBox(height: 16),

          // 登出
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => _logout(context, ref),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: const Text('断开连接',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showModeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择默认模式'),
        children: const [
          SimpleDialogOption(
            child: Text('变更前确认 — 编辑前先问我'),
          ),
          SimpleDialogOption(
            child: Text('自动编辑 — 自动编辑文件'),
          ),
          SimpleDialogOption(
            child: Text('计划模式 — 编辑前先出计划'),
          ),
          SimpleDialogOption(
            child: Text('完全访问 — 减少确认次数'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('断开连接'),
        content: const Text('确定要断开与 ZCode 的连接吗?需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(sessionProvider.notifier).logout();
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
