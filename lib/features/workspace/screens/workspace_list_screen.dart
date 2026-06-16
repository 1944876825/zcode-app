import 'package:connectivity_plus/connectivity_plus.dart' as connectivity_plus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/relay/relay_protocol.dart';
import '../../../../shared/theme/app_design_tokens.dart';
import '../../../../shared/theme/app_router.dart';
import '../../../data/models/workspace.dart';
import '../../../providers/app_providers.dart';
import '../../search/screens/search_palette.dart';

/// 工作区列表页
class WorkspaceListScreen extends ConsumerStatefulWidget {
  const WorkspaceListScreen({super.key});

  @override
  ConsumerState<WorkspaceListScreen> createState() =>
      _WorkspaceListScreenState();
}

class _WorkspaceListScreenState extends ConsumerState<WorkspaceListScreen> {
  /// 网络恢复监听订阅 (网络从断开恢复时自动刷新工作区列表)
  ProviderSubscription<AsyncValue<List<connectivity_plus.ConnectivityResult>>>
      ? _netSub;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    // 监听网络状态: 从 ConnectivityResult.none 恢复时自动刷新工作区列表。
    // 在 build() 之外 (initState) 使用 ref.listenManual, 并自行管理订阅生命周期。
    _netSub = ref.listenManual(networkInfoProvider, (_, next) {
      next.whenData((results) {
        final offline =
            results.contains(connectivity_plus.ConnectivityResult.none);
        if (offline) {
          _wasOffline = true;
        } else if (_wasOffline) {
          _wasOffline = false;
          if (mounted) {
            ref.read(workspaceListProvider.notifier).refresh();
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _netSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final workspacesAsync = ref.watch(workspaceListProvider);
    final connectionAsync = ref.watch(relayConnectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('工作区'),
        actions: [
          // 全局搜索
          IconButton(
            icon: const Icon(Icons.search, size: 22),
            tooltip: '搜索',
            onPressed: () => showSearchPalette(context),
          ),
          // 连接状态指示
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: connectionAsync.when(
                data: (state) => _ConnectionBadge(state: state),
                loading: () => const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                error: (_, __) => const Icon(Icons.cloud_off, size: 18),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(workspaceListProvider.notifier).refresh(),
        child: workspacesAsync.when(
          data: (workspaces) {
            if (workspaces.isEmpty) {
              return _buildEmpty(theme);
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: workspaces.length,
              itemBuilder: (context, index) {
                final ws = workspaces[index];
                return _WorkspaceCard(
                  workspace: ws,
                  onTap: () => _openWorkspace(ws),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _buildError(theme, error.toString()),
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(
                Icons.folder_off_outlined,
                size: 40,
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('暂无工作区', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '在 ZCode 桌面端创建项目后\n下拉刷新即可看到',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => ref.read(workspaceListProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('刷新'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Center(
          child: Text(
            '加载失败',
            style: theme.textTheme.titleMedium,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: () => ref.read(workspaceListProvider.notifier).load(),
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }

  void _openWorkspace(Workspace workspace) {
    // 设置选中工作区
    ref.read(selectedWorkspaceProvider.notifier).state = workspace;

    // 打开工作区桥接
    final repo = ref.read(workspaceRepositoryProvider);
    if (repo == null) return;
    repo.openWorkspace(workspace.workspaceKey).then((_) {
      if (!mounted) return;
      // 直接进聊天页 (默认新会话, 不预先创建)
      // taskId 留空, ChatNotifier 在首发消息时调 createSession
      _goToChat(workspace, null);
    }).catchError((e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开工作区失败: $e')),
        );
      }
    });
  }

  void _goToChat(Workspace workspace, String? taskId) {
    // push 而非 go: 保留工作区列表在栈底, 系统返回键才能 pop 回去
    // (go 会替换整个栈, 聊天页变成栈底, 返回键无处可退)
    context.push(
      '${AppRoutes.chat}?workspace=${Uri.encodeComponent(workspace.workspaceKey)}'
      '${taskId != null ? '&task=${Uri.encodeComponent(taskId)}' : ''}',
    );
  }
}

/// 连接状态徽章
class _ConnectionBadge extends StatelessWidget {
  final RelayConnectionState? state;

  const _ConnectionBadge({required this.state});

  @override
  Widget build(BuildContext context) {
    // state 是 AsyncValue<RelayConnectionState>
    final relayState = state;

    final (color, label) = switch (relayState) {
      RelayConnectionState.ready => (Colors.green, '已连接'),
      RelayConnectionState.connected ||
      RelayConnectionState.bootstrapping =>
        (Colors.orange, '连接中'),
      RelayConnectionState.connecting ||
      RelayConnectionState.reconnecting =>
        (Colors.orange.shade300, '重连中'),
      RelayConnectionState.error || RelayConnectionState.disconnected =>
        (Colors.red, '未连接'),
      RelayConnectionState.idle => (Colors.grey, '待机'),
      _ => (Colors.grey, '—'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }
}

/// 工作区卡片
class _WorkspaceCard extends StatelessWidget {
  final Workspace workspace;
  final VoidCallback onTap;

  const _WorkspaceCard({required this.workspace, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRemote = workspace.kind == WorkspaceKind.remote;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              // 项目图标 (方块, 等宽感)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isRemote
                      ? AppColors.accentContainer
                      : theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Icon(
                  isRemote ? Icons.cloud_outlined : Icons.folder_outlined,
                  size: 20,
                  color: isRemote
                      ? AppColors.accent
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // 项目信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workspace.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    // 路径用等宽字体
                    Text(
                      workspace.workspacePath,
                      style: AppText.mono(context,
                          size: 11, color: theme.colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (workspace.branch != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Icon(Icons.call_split,
                              size: 11,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            workspace.branch!,
                            style: AppText.mono(context,
                                size: 11,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

