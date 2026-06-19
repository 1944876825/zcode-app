import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:markdown/markdown.dart' as md;

import 'package:share_plus/share_plus.dart';

import '../../../core/relay/relay_protocol.dart';
import '../../../data/models/glm_quota.dart' as glm;
import '../../../core/voice/voice_input_service.dart';
import '../../../data/models/workspace.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/chat_provider.dart';
import '../../../shared/theme/app_design_tokens.dart';
import '../../../shared/theme/app_router.dart';
import '../../../shared/widgets/code_highlight.dart';
import '../../../shared/widgets/glass_bars.dart';
import '../../../shared/widgets/voice_input_button.dart';
import '../../search/screens/search_palette.dart';

/// AI 对话页 — 核心交互界面 (实测对接 2026-06-15)
///
/// 数据流: chatProvider(ChatNotifier)
///   - init: 加载历史 (getTaskSnapshot) + 订阅 session 事件
///   - sendMessage: enqueueTaskCommand 入队, AI 回复走 session 事件
///   - session.event: tool.updated = AI 在调工具; 文本流 = 追加到 AI 消息
class ChatScreen extends ConsumerStatefulWidget {
  final String workspaceKey;
  final String? taskId;

  const ChatScreen({
    super.key,
    required this.workspaceKey,
    this.taskId,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  // ⚠️ GlobalKey 必须在 state 里持有 (跨帧稳定), 不能在 build 里 new。
  // 之前在 build 里每次 new GlobalKey() 会导致 Scaffold 子树每帧重新挂载,
  // 输入框 (TextEditingController) 随之重建 → 打字内容在 rebuild 时丢失
  // (典型现象: 点停止/切模式/收消息后输入框文字清空)。
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(selectedWorkspaceProvider);
    final title = workspace?.name ?? '对话';

    // taskId 可空: null = 新会话 (首发消息时创建)
    final chatRef = ChatRef(taskId: widget.taskId, workspacePath: widget.workspaceKey);
    final chatState = ref.watch(chatProvider(chatRef));

    return Scaffold(
      key: _scaffoldKey,
      drawer: _HistoryDrawer(
        workspacePath: widget.workspaceKey,
        currentTaskId: widget.taskId,
        onSelected: (selectedTaskId) {
          // 选了历史会话: 用新 taskId 跳转
          // replace: 原地替换当前 chat 路由, 不叠加新 chat, 保持工作区列表在栈底
          context.replace(
            '${AppRoutes.chat}?workspace=${Uri.encodeComponent(widget.workspaceKey)}'
            '&task=${Uri.encodeComponent(selectedTaskId)}',
          );
        },
        onNewChat: () {
          // 新对话: 跳回不带 task 的聊天页 (replace: 原地替换, 保持返回栈)
          context.replace(
            '${AppRoutes.chat}?workspace=${Uri.encodeComponent(widget.workspaceKey)}',
          );
        },
      ),
      body: _ChatScaffold(
        title: title,
        workspacePath: widget.workspaceKey,
        chatRef: chatRef,
        state: chatState,
        onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
        onBack: () => context.go(AppRoutes.home),
      ),
    );
  }
}

class _ChatScaffold extends ConsumerStatefulWidget {
  final String title;
  final String workspacePath;
  final ChatRef chatRef;
  final ChatState state;
  final VoidCallback onMenuTap;
  final VoidCallback onBack;

  const _ChatScaffold({
    required this.title,
    required this.workspacePath,
    required this.chatRef,
    required this.state,
    required this.onMenuTap,
    required this.onBack,
  });

  @override
  ConsumerState<_ChatScaffold> createState() => _ChatScaffoldState();
}

class _ChatScaffoldState extends ConsumerState<_ChatScaffold> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _voiceService = VoiceInputService();
  final _inputFocusNode = FocusNode();

  /// 用户是否在底部附近 (用于自动跟随 / 显示滚动按钮)
  bool _isAtBottom = true;
  /// 上一帧的滚动 offset, 用于检测用户主动滚动方向
  double _lastOffset = 0;
  /// 上一次构建时的消息数 (检测新消息)
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  /// 滚动监听: 判断用户是否在底部附近 → 控制悬浮按钮显隐
  /// reverse: true 后, 底部 = offset 0
  ///
  /// 关键: 用户主动向上滚动 (offset 增大) 时立即标记 _isAtBottom=false,
  /// 不等超过阈值 —— 否则 AI 流式输出时会把视图"拽回"底部, 打断翻阅。
  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final current = _scrollController.offset;
    // 用户主动向上翻 (offset 变大) → 立即脱离"贴底"态
    // (留 1px 容差, 排除流式增长导致的微小正向漂移)
    if (current > _lastOffset + 1) {
      if (_isAtBottom) setState(() => _isAtBottom = false);
    } else {
      // 向下滚回底部附近 (offset < 60) → 恢复"贴底"态, 重新启用自动跟随
      // 阈值收紧到 60, 避免上翻一点又被判回底部
      final nearBottom = current < 60;
      if (nearBottom != _isAtBottom) {
        setState(() => _isAtBottom = nearBottom);
      }
    }
    _lastOffset = current;
  }

  /// reverse: true 下新消息自动出现在底部 (offset 0)
  /// 只需处理: 历史加载完成时跳到底部, 以及用户在底部时跟随流式更新
  @override
  void didUpdateWidget(covariant _ChatScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newCount = widget.state.messages.length;
    final oldCount = oldWidget.state.messages.length;

    // 历史加载完成 / 消息从空变非空 → 跳到底部
    // 用 post-frame 包裹: didUpdateWidget 阶段 ListView 可能尚未 attach
    // (hasClients == false 会导致 jumpTo 静默失败)。
    if ((oldWidget.state.isLoadingHistory && !widget.state.isLoadingHistory) ||
        (oldCount == 0 && newCount > 0)) {
      _lastMsgCount = newCount;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      return;
    }

    _lastMsgCount = newCount;

    // AI 流式输出时跟随到底部:
    // reverse: true 下气泡随文字增长会向视觉上方扩展, 若不主动跟随,
    // 视图会"漂移"到内容顶部, 看起来像滚到了最上面。
    // 仅当用户当前贴在底部 (_isAtBottom) 时才跟随, 避免打断用户向上翻阅。
    if (widget.state.isResponding && _isAtBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty || widget.state.isResponding) return;

    // 不 await, 让 UI 立即响应; 错误由 chatProvider 状态反映
    ref.read(chatProvider(widget.chatRef).notifier).sendMessage(text);
    _messageController.clear();
    _scrollToBottom();
  }

  /// reverse: true → 底部 = offset 0
  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(0,
      duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _jumpToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontSize: 16)),
            // 状态行: AI 工作中 / 用量统计
            if (state.isResponding)
              Text(
                'AI 正在工作...',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
              )
            else
              _UsagePill(
                tokenUsage: state.tokenUsage,
                glmQuotaAsync: ref.watch(glmQuotaProvider),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),  // 汉堡菜单 (打开历史会话抽屉)
          onPressed: widget.onMenuTap,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            tooltip: '搜索',
            onPressed: () {
              showSearchPalette(
                context,
                onSlashCommand: (command) {
                  if (!context.mounted) return;
                  final notifier =
                      ref.read(chatProvider(widget.chatRef).notifier);
                  switch (command) {
                    case '/compact':
                      notifier.compact();
                    case '/model':
                      _openModelPicker();
                    default:
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$command — 命令暂未实现'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                  }
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            tooltip: '新对话',
            onPressed: () {
              // 跳回不带 task 的聊天页 (replace: 原地替换, 保持返回栈)
              context.replace(
                '${AppRoutes.chat}?workspace=${Uri.encodeComponent(widget.workspacePath)}',
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            tooltip: '返回工作区',
            onPressed: widget.onBack,
          ),
        ],
      ),
      body: Column(
        children: [
          // 连接状态条 (非 ready 时显示)
          Consumer(builder: (context, ref, _) {
            final connAsync = ref.watch(relayConnectionStateProvider);
            final connState = connAsync.valueOrNull;
            if (connState == null || connState == RelayConnectionState.ready) {
              return const SizedBox.shrink();
            }
            // error 状态仅在 RelayClient 重连重试次数耗尽后出现
            // → 极可能是 Cookie (acw_tc 30min 过期) 失效, 给出重新登录入口。
            if (connState == RelayConnectionState.error) {
              return Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: Colors.red.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(Icons.cookie_outlined,
                        size: 14, color: Colors.red),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Cookie 可能已过期',
                        style: TextStyle(fontSize: 12, color: Colors.red),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => context.go(AppRoutes.login),
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重新连接'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red,
                        visualDensity: VisualDensity.compact,
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              );
            }
            final info = switch (connState) {
              RelayConnectionState.reconnecting => (
                Icons.wifi_off, Colors.orange, '正在重连...'
              ),
              RelayConnectionState.connecting ||
              RelayConnectionState.connected => (
                Icons.wifi_find, Colors.orange, '连接中...'
              ),
              RelayConnectionState.disconnected => (
                Icons.cloud_off, Colors.red, '已断开'
              ),
              _ => (Icons.hourglass_empty, Colors.grey, ''),
            };
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: info.$2.withValues(alpha: 0.15),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(info.$1, size: 14, color: info.$2),
                const SizedBox(width: 6),
                Text(info.$3,
                    style: TextStyle(fontSize: 12, color: info.$2)),
              ]),
            );
          }),
          if (state.error != null)
            _ErrorBanner(message: state.error!, theme: theme),
          // plan 提议批准卡 (AI 调 ExitPlanMode, 等用户批准/拒绝)
          if (state.pendingPlan != null)
            _PlanApprovalCard(
              planText: state.pendingPlan!,
              theme: theme,
              onApprove: () {
                ref
                    .read(chatProvider(widget.chatRef).notifier)
                    .answerPlan(true);
              },
              onReject: () {
                ref
                    .read(chatProvider(widget.chatRef).notifier)
                    .answerPlan(false);
              },
            ),
          // Todo 计划列表 (AI 用 TodoWrite 产出的任务清单, 来自 runtime.plan[])
          if (state.plan.isNotEmpty)
            _PlanList(
              plan: state.plan,
              theme: theme,
              isResponding: state.isResponding,
            ),
          // 工具执行前确认 (build/plan 模式 pendingPermissions)
          if (state.pendingPermissions.isNotEmpty)
            _PermissionCard(
              permissions: state.pendingPermissions,
              theme: theme,
              onAnswer: (id, optionId, decision) {
                ref
                    .read(chatProvider(widget.chatRef).notifier)
                    .answerPermission(id, optionId, decision);
              },
            ),
          // AskUserQuestion 交互式问题卡片 (AI 提问时显示)
          if (state.pendingQuestion != null)
            _QuestionCard(
              question: state.pendingQuestion!,
              onAnswer: (selected) {
                ref
                    .read(chatProvider(widget.chatRef).notifier)
                    .answerQuestion(selected);
              },
            ),
          Expanded(
            child: state.isLoadingHistory && state.messages.isEmpty
                ? _buildSkeleton(theme)
                : state.messages.isEmpty
                    ? _buildWorkspaceHome(theme)
                    : Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            reverse: true,
                            // 顶部留出 标题栏(56)+状态栏 的空间, 否则首条消息被
                            // extendBodyBehindAppBar 的毛玻璃标题栏遮挡、滚不到顶
                            padding: EdgeInsets.fromLTRB(
                                12,
                                MediaQuery.of(context).padding.top + 56 + AppSpacing.sm,
                                12,
                                AppSpacing.sm),
                            itemCount: state.messages.length,
                            itemBuilder: (context, index) {
                              final realIndex = state.messages.length - 1 - index;
                              final msg = state.messages[realIndex];
                              // 日期分组: 最后一条(视觉最底)或日期变化时插入分隔线
                              final showDateSeparator = realIndex == state.messages.length - 1 ||
                                  !_isSameDay(state.messages[realIndex + 1].createdAt, msg.createdAt);
                              // 判断是否为最后一条用户消息 (用于撤销功能)
                              final isLastUserMessage = msg.role == 'user' &&
                                  !state.messages.skip(realIndex + 1).any((m) => m.role == 'user');
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (showDateSeparator) _DateSeparator(date: msg.createdAt),
                                  _MessageBubble(
                                    message: msg,
                                    theme: theme,
                                    isLastUserMessage: isLastUserMessage,
                                    isResponding: state.isResponding,
                                    onEdit: (text) => ref
                                        .read(chatProvider(widget.chatRef).notifier)
                                        .sendMessage(text),
                                    onRewind: () => ref
                                        .read(chatProvider(widget.chatRef).notifier)
                                        .rewindLastTurn(),
                                  ),
                                ],
                              );
                            },
                          ),
                          // 滚动到底部悬浮按钮: 不在底部时显示
                          if (!_isAtBottom)
                            Positioned(
                              bottom: AppSpacing.sm,
                              right: 12,
                              child: _ScrollToBottomButton(
                                onPressed: _scrollToBottom,
                                hasNewContent: state.isResponding,
                              ),
                            ),
                        ],
                      ),
          ),
          _buildInputArea(theme),
        ],
      ),
    );
  }

  /// 消息加载骨架屏
  Widget _buildSkeleton(ThemeData theme) {
    final shimmerColor = theme.colorScheme.surfaceContainerHighest;
    final topInset = MediaQuery.of(context).padding.top + 56 + AppSpacing.sm;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.md, topInset, AppSpacing.md, 0),
      child: Column(
        children: List.generate(4, (i) {
          final isLeft = i % 2 == 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              mainAxisAlignment:
                  isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isLeft) ...[
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: shimmerColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Container(
                    width: MediaQuery.sizeOf(context).width * 0.7,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: shimmerColor,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: double.infinity, height: 14,
                          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4)),
                        ),
                        const SizedBox(height: 8),
                        Container(width: double.infinity, height: 14,
                          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4)),
                        ),
                        const SizedBox(height: 8),
                        Container(width: i.isEven ? 180 : 120, height: 14,
                          decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(4)),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!isLeft) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                        color: shimmerColor, shape: BoxShape.circle),
                  ),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  /// 工作区主页 — 新会话空状态
  ///
  /// 进入工作区但还没发消息时展示项目全貌:
  /// 项目信息卡 → 最近对话 → 快速开始提示词
  Widget _buildWorkspaceHome(ThemeData theme) {
    final workspace = ref.watch(selectedWorkspaceProvider);
    final connState = ref.watch(relayConnectionStateProvider).valueOrNull;
    final allTasks = ref.watch(allTasksProvider);
    final tasks = allTasks
        .where((t) => t.workspaceKey == widget.workspacePath && !t.archived)
        .toList()
      ..sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));
    final recentTasks = tasks.take(5).toList();

    final topInset = MediaQuery.of(context).padding.top + 56 + AppSpacing.sm;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          AppSpacing.md, topInset, AppSpacing.md, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.lg),

          // 项目信息卡
          _ProjectInfoCard(
            workspace: workspace,
            workspacePath: widget.workspacePath,
            connState: connState,
          ),

          const SizedBox(height: AppSpacing.xl),

          // 最近对话
          if (recentTasks.isNotEmpty) ...[
            _HomeSectionHeader(
              title: '最近对话',
              actionLabel: '全部',
              onAction: widget.onMenuTap,
            ),
            const SizedBox(height: AppSpacing.sm),
            ...recentTasks.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _RecentTaskCard(
                    task: t,
                    onTap: () => context.replace(
                      '${AppRoutes.chat}?workspace=${Uri.encodeComponent(widget.workspacePath)}'
                      '&task=${Uri.encodeComponent(t.id)}',
                    ),
                  ),
                )),
            const SizedBox(height: AppSpacing.xl),
          ],

          const SizedBox(height: AppSpacing.xxxl),
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme) {
    final notifier = ref.read(chatProvider(widget.chatRef).notifier);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
        // 整个 composer 是一个圆角卡片 (深灰, 柔边)
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm, AppSpacing.xs, AppSpacing.sm, AppSpacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 统一提及面板 (@文件 / #会话 / $技能 / /命令)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _messageController,
                builder: (context, value, _) {
                  final mention = _detectMentionAtCursor(value);
                  if (mention == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(
                        bottom: AppSpacing.xs, left: AppSpacing.sm, right: AppSpacing.sm),
                    child: _MentionOverlay(
                      trigger: mention.$1,
                      query: mention.$2,
                      workspacePath: widget.workspacePath,
                      chatRef: widget.chatRef,
                      onSelected: (insertText) =>
                          _replaceMention(mention, insertText),
                    ),
                  );
                },
              ),
              // 输入行: + 按钮 | 输入框 | 发送按钮 (内嵌输入框内)
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 左侧 + 按钮 (附件/功能)
                  IconButton(
                    onPressed: _showPlusMenu,
                    icon: const Icon(Icons.add_rounded, size: 22),
                    style: IconButton.styleFrom(
                      foregroundColor: theme.colorScheme.onSurfaceVariant,
                      minimumSize: const Size(AppTouch.min, AppTouch.min),
                      padding: const EdgeInsets.all(6),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // 输入框 (无边框, 透明, 自适应高度)
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      focusNode: _inputFocusNode,
                      minLines: 1,
                      maxLines: 6,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                      decoration: InputDecoration(
                        hintText: '提出后续修改要求',
                        hintStyle: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 4),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  // 右侧发送按钮 (圆形, 上箭头, 有内容才亮)
                  // 必须包 ValueListenableBuilder: TextField 打字不会触发父 build,
                  // 否则 hasText 只在 build 时算一次 → 输入文字后按钮永远禁用。
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _messageController,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      return widget.state.isResponding
                          ? _ComposerSendButton(
                              icon: Icons.stop_rounded,
                              onPressed: () => notifier.stopResponding(),
                              enabled: true,
                              isStop: true,
                            )
                          : _ComposerSendButton(
                              icon: Icons.arrow_upward_rounded,
                              onPressed: hasText ? _sendMessage : null,
                              enabled: hasText,
                            );
                    },
                  ),
                ],
              ),
              // 工具栏 (输入框内底部一行): + 语音 | 变更前确认 | 模型 | 质量
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  children: [
                    // 语音输入按钮 (长按说话)
                    // ValueKey 稳定 state: 避免父级 rebuild 时按钮 unmount/remount
                    // 导致 _available 重置 → 闪烁
                    VoiceInputButton(
                      key: const ValueKey('voice_input'),
                      service: _voiceService,
                      size: 36,
                      onTranscribed: (text) {
                        final existing = _messageController.text;
                        final sep = existing.isEmpty || existing.endsWith(' ')
                            ? ''
                            : ' ';
                        _messageController.text = '$existing$sep$text';
                        _messageController.selection =
                            TextSelection.fromPosition(
                          TextPosition(offset: _messageController.text.length),
                        );
                        _messageController.notifyListeners();
                      },
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // 模式选择器 (变更前确认/计划模式/自动编辑)
                    _ModeSelector(
                      mode: widget.state.mode,
                      onChanged: (m) => notifier.setMode(m),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // 思考级别选择器
                    _ThoughtLevelSelector(
                      level: widget.state.thoughtLevel,
                      onChanged: (l) => notifier.setThoughtLevel(l),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: _ModelSelector(
                        models: ref
                                .watch(modelListProvider)
                                .valueOrNull
                                ?.models ??
                            const <String>[],
                        current: widget.state.model ??
                            ref.watch(preferredModelProvider),
                        providerNames: ref
                                .watch(modelListProvider)
                                .valueOrNull
                                ?.providerNames ??
                            const <String, String>{},
                        isLoading: ref.watch(modelListProvider).isLoading,
                        onSelected: (m) => notifier.setModel(m),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// /model 命令 + 模型按钮共用: 打开模型选择底部表 (模型列表读全局 modelListProvider)
  void _openModelPicker() {
    final modelList = ref.read(modelListProvider).valueOrNull;
    final models = modelList?.models ?? const <String>[];
    if (models.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('模型列表未加载 (relay 可能未就绪)'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final notifier = ref.read(chatProvider(widget.chatRef).notifier);
    showModelPicker(
      context,
      models: models,
      current: ref.read(preferredModelProvider),
      providerNames: modelList?.providerNames ?? const {},
      onSelected: (m) => notifier.setModel(m),
    );
  }

  /// 执行 slash 命令 (/compact→session/compact; /model→选模型; 其余客户端提示)
  void _runCommand(_SlashCommand cmd) {
    final notifier = ref.read(chatProvider(widget.chatRef).notifier);
    _messageController.clear();
    switch (cmd.name) {
      case '/compact':
        notifier.compact();
      case '/model':
        _openModelPicker();
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${cmd.name}：${cmd.desc}'),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  /// + 功能菜单 (图片/文件/@提及/#会话/指令)
  void _showPlusMenu() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('插入',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.lg),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  mainAxisSpacing: AppSpacing.md,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 0.82,
                  children: [
                    _PlusMenuItem(
                      icon: Icons.image_outlined,
                      label: '图片',
                      color: AppColors.accent,
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertImage();
                      },
                    ),
                    _PlusMenuItem(
                      icon: Icons.description_outlined,
                      label: '文件',
                      color: AppColors.success,
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertFileMention();
                      },
                    ),
                    _PlusMenuItem(
                      icon: Icons.alternate_email,
                      label: '@文件',
                      color: const Color(0xFFF59E0B),
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertAtCursor('@');
                      },
                    ),
                    _PlusMenuItem(
                      icon: Icons.tag,
                      label: '#会话',
                      color: const Color(0xFF8B5CF6),
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertAtCursor('#');
                      },
                    ),
                    _PlusMenuItem(
                      icon: Icons.bolt_outlined,
                      label: r'$技能',
                      color: const Color(0xFFFBBF24),
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertAtCursor(r'$');
                      },
                    ),
                    _PlusMenuItem(
                      icon: Icons.terminal,
                      label: '/指令',
                      color: AppColors.danger,
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertAtCursor('/');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // 提示文字
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '@文件路径 让 AI 读取桌面端文件；#可引用其他对话',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 在光标位置插入文本
  void _insertAtCursor(String text) {
    final sel = _messageController.selection;
    final currentText = _messageController.text;
    if (sel.isValid) {
      final newText =
          currentText.substring(0, sel.start) + text + currentText.substring(sel.end);
      _messageController.text = newText;
      final newPos = (sel.start ?? currentText.length) + text.length;
      _messageController.selection = TextSelection.collapsed(offset: newPos);
    } else {
      _messageController.text = currentText + text;
      _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length);
    }
    _messageController.notifyListeners();
    // 保持输入框聚焦 (触发提及弹窗)
    FocusScope.of(context).requestFocus(_inputFocusNode);
  }

  /// 检测光标位置的提及触发符 (@ # $ /)
  /// 返回 (触发符, 查询文本, 触发符起始位置) 或 null
  (String, String, int)? _detectMentionAtCursor(TextEditingValue value) {
    final text = value.text;
    final cursor = value.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return null;

    // 从光标往回扫描, 找到触发符
    for (var i = cursor - 1; i >= 0; i--) {
      final ch = text[i];
      if (ch == ' ' || ch == '\n' || ch == '\t') return null;
      if (ch == '@' || ch == '#' || ch == r'$' || ch == '/') {
        // 触发符必须在词首 (前面是空格或行首)
        if (i > 0) {
          final prev = text[i - 1];
          if (prev != ' ' && prev != '\n' && prev != '\t') return null;
        }
        final query = text.substring(i + 1, cursor);
        // /命令只在行首触发
        if (ch == '/' && i != 0) return null;
        return (ch, query, i);
      }
    }
    return null;
  }

  /// 替换提及文本: 把 [trigger+query] 替换为 [insertText]
  void _replaceMention((String, String, int) mention, String insertText) {
    final trigger = mention.$1;
    final startPos = mention.$3;
    final cursor = _messageController.selection.baseOffset;
    final text = _messageController.text;

    final newText =
        text.substring(0, startPos) + insertText + ' ' + text.substring(cursor);
    _messageController.text = newText;
    final newPos = startPos + insertText.length + 1;
    _messageController.selection = TextSelection.collapsed(offset: newPos);
    _messageController.notifyListeners();

    // 如果是 / 命令, 执行对应操作
    if (trigger == '/' && insertText.startsWith('/')) {
      final cmd = _slashCommands.where((c) => c.name == insertText).firstOrNull;
      if (cmd != null) {
        _messageController.clear();
        _runCommand(cmd);
      }
    }
  }

  /// 插入图片 — 从手机选图, 压缩后 base64 嵌入消息
  Future<void> _insertImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 75,
    );
    if (xfile == null) return;

    final bytes = await xfile.readAsBytes();
    // 检查大小 (> 2MB 压缩后仍太大 → 警告)
    if (bytes.length > 2 * 1024 * 1024) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('图片过大 (>2MB)，请选择更小的图片'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final base64Data = base64Encode(bytes);
    final ext = xfile.name.split('.').last.toLowerCase();
    final mime = switch (ext) {
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    // 嵌入 markdown 图片语法
    final imageMarkdown = '![${xfile.name}](data:$mime;base64,$base64Data)';
    _insertAtCursor('$imageMarkdown\n\n');
  }

  /// 插入文件 — 从手机选文件, 读取文本内容嵌入消息
  Future<void> _insertFileMention() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    final path = file.path;

    // 如果有路径且是文本文件, 读取内容
    if (path != null) {
      try {
        final rawBytes = await File(path).readAsBytes();
        // 限制 200KB
        if (rawBytes.length > 200 * 1024) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('文件过大 (>200KB)，仅支持文本文件'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }

        // 尝试解码为文本
        final content = utf8.decode(rawBytes, allowMalformed: true);
        final ext = file.extension ?? '';
        final langTag = switch (ext.replaceAll('.', '').toLowerCase()) {
          'py' => 'python',
          'js' => 'javascript',
          'ts' => 'typescript',
          'dart' => 'dart',
          'java' => 'java',
          'kt' => 'kotlin',
          'go' => 'go',
          'rs' => 'rust',
          'c' || 'cpp' || 'h' => 'cpp',
          'sh' || 'bash' => 'bash',
          'yml' || 'yaml' => 'yaml',
          'json' => 'json',
          'xml' => 'xml',
          'html' => 'html',
          'css' => 'css',
          'sql' => 'sql',
          'md' => 'markdown',
          _ => '',
        };
        // 嵌入为代码块
        final fileBlock = '📎 ${file.name}\n```$langTag\n$content\n```\n\n';
        _insertAtCursor(fileBlock);
      } catch (e) {
        // 二进制文件无法读取 → 只插入文件名提示
        _insertAtCursor('📎 ${file.name}\n\n');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法读取文件内容: $e')),
          );
        }
      }
    } else {
      // 无路径 (web 平台)
      _insertAtCursor('📎 ${file.name}\n\n');
    }
  }

  /// 插入会话引用 (#)
  void _insertSessionRef() {
    final allTasks = ref.read(allTasksProvider);
    final tasks = allTasks
        .where((t) => t.workspaceKey == widget.workspacePath && !t.archived)
        .toList()
      ..sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));

    if (tasks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可引用的会话')),
      );
      return;
    }

    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text('选择会话引用',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: tasks.length,
                  itemBuilder: (ctx, index) {
                    final task = tasks[index];
                    return ListTile(
                      leading: Icon(
                        task.status == TaskStatus.running
                            ? Icons.autorenew
                            : Icons.chat_bubble_outline,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(task.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(task.id,
                          style: AppText.mono(context,
                              size: 10,
                              color: theme.colorScheme.onSurfaceVariant)),
                      onTap: () {
                        Navigator.pop(ctx);
                        // 插入 #任务标题 作为引用文本
                        _insertAtCursor('#${task.title} ');
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  /// @提及选择器 — 直接弹出提及类型列表
  void _showMentionPicker() {
    final theme = Theme.of(context);
    final mentions = [
      ('@file', '📁 文件路径', '引用桌面端文件，让 AI 读取内容'),
      ('@url', '🔗 网页链接', '粘贴网页 URL 让 AI 分析'),
      ('@image', '🖼️ 图片', '引用桌面端图片文件'),
      ('@folder', '📂 文件夹', '引用桌面端项目文件夹'),
    ];

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('@提及',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: AppSpacing.sm),
                Text('选择提及类型，将插入对应标签',
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.md),
                ...mentions.map((m) => ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm)),
                      leading: Text(m.$1,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: kMonoFont,
                            color: const Color(0xFFF59E0B),
                          )),
                      title: Text(m.$2,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500)),
                      subtitle: Text(m.$3,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _insertAtCursor('${m.$1} ');
                        _messageController.selection = TextSelection.collapsed(
                            offset: _messageController.text.length);
                      },
                    )),
              ],
            ),
          ),
        );
      },
    );
  }

  /// /指令选择器 — 直接弹出完整指令列表
  void _showCommandPicker() {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text('指令',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _slashCommands.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.3),
                  ),
                  itemBuilder: (ctx, index) {
                    final cmd = _slashCommands[index];
                    return ListTile(
                      leading: Icon(Icons.chevron_right,
                          size: 18, color: theme.colorScheme.primary),
                      title: Text(cmd.name,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text(cmd.desc,
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                      onTap: () {
                        Navigator.pop(ctx);
                        _runCommand(cmd);
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

/// + 菜单项 (图标 + 文字, 网格布局)
class _PlusMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _PlusMenuItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 24, color: color),
          ),
          const SizedBox(height: AppSpacing.xs + 2),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final ThemeData theme;

  const _ErrorBanner({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.errorContainer,
      child: Text(
        message,
        style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 13),
      ),
    );
  }
}

/// Todo 计划列表 (来自 runtime.plan[])
///
/// AI 用 TodoWrite 工具产出的任务清单, 实时反映执行进度
/// (pending → in_progress → completed)。默认折叠只显示进度摘要,
/// 展开后列出每项 + 状态图标。
class _PlanList extends StatefulWidget {
  final List<PlanItem> plan;
  final ThemeData theme;
  final bool isResponding;

  const _PlanList({
    required this.plan,
    required this.theme,
    required this.isResponding,
  });

  @override
  State<_PlanList> createState() => _PlanListState();
}

class _PlanListState extends State<_PlanList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final plan = widget.plan;
    if (plan.isEmpty) return const SizedBox.shrink();

    final completed = plan.where((p) => p.status == TodoStatus.completed).length;
    final total = plan.length;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;
    // 有进行中的项, 或 AI 正在工作 → 视为"活跃"
    final isActive = widget.isResponding ||
        plan.any((p) => p.status == TodoStatus.inProgress);

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isActive
              ? AppColors.accent.withValues(alpha: 0.4)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxHeight: 240),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部: 进度摘要 + 折叠箭头
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(
                    isActive
                        ? Icons.playlist_play_rounded
                        : Icons.checklist_rounded,
                    size: 16,
                    color: isActive ? AppColors.accent : theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '计划 $completed/$total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 进度条
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: total == 0 ? 0 : completed / total,
                        minHeight: 3,
                        backgroundColor:
                            theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppColors.success),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // 展开后: 任务列表 (可滚动, 防止过长)
          if (_expanded)
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.only(
                    bottom: AppSpacing.sm, left: AppSpacing.sm, right: AppSpacing.sm),
                itemCount: plan.length,
                itemBuilder: (ctx, i) => _PlanRow(item: plan[i], theme: theme),
              ),
            ),
        ],
      ),
    );
  }
}

/// 计划单行 (状态图标 + 标题)
class _PlanRow extends StatelessWidget {
  final PlanItem item;
  final ThemeData theme;

  const _PlanRow({required this.item, required this.theme});

  @override
  Widget build(BuildContext context) {
    final (icon, color, deco) = switch (item.status) {
      TodoStatus.completed => (
          Icons.check_circle_rounded,
          AppColors.success,
          TextDecoration.lineThrough,
        ),
      TodoStatus.inProgress => (
          Icons.radio_button_checked,
          AppColors.accent,
          TextDecoration.none,
        ),
      TodoStatus.pending => (
          Icons.radio_button_unchecked,
          theme.colorScheme.onSurfaceVariant,
          TextDecoration.none,
        ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              item.title,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: item.status == TodoStatus.completed
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.onSurface,
                decoration: deco,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 工具执行前确认卡片 (build/plan 模式 pendingPermissions)
///
/// ★ wire 实测 (host bundle 2026-06-19, 规格 §11.2):
/// permission.requested 事件含 options[] (PermissionOption),
/// 每个 option 自带 optionId + name + decision。
/// 用户选哪个 option, 就回传那个 optionId + decision。
class _PermissionCard extends StatelessWidget {
  final List<PendingPermission> permissions;
  final ThemeData theme;
  /// (permissionId, optionId, decision) — 用所选 option 回应
  final void Function(String permissionId, String optionId, String decision) onAnswer;

  const _PermissionCard({
    required this.permissions,
    required this.theme,
    required this.onAnswer,
  });

  String _summarize(PendingPermission p) {
    final input = p.input;
    final path = input['file_path'] ??
        input['filePath'] ??
        input['path'] ??
        input['file'];
    if (path is String && path.isNotEmpty) return path;
    final cmd = input['command'] ?? input['cmd'];
    if (cmd is String && cmd.isNotEmpty) return cmd;
    return '';
  }

  String _toolLabel(String toolName) {
    return switch (toolName) {
      'Edit' || 'Write' => '编辑文件',
      'Bash' => '执行命令',
      'MultiEdit' => '批量编辑',
      _ => '执行 $toolName',
    };
  }

  Color _riskColor(String riskLevel) {
    return switch (riskLevel) {
      'critical' => Colors.red.shade700,
      'high' => Colors.red,
      'medium' => Colors.orange,
      _ => Colors.blue,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = this.theme;
    final p = permissions.first; // 一次确认一个, 多个会依次出现
    final detail = _summarize(p);
    final riskColor = _riskColor(p.riskLevel);

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: riskColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: riskColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: riskColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '请求${_toolLabel(p.toolName)}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: riskColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 风险等级标签
              if (p.riskLevel == 'high' || p.riskLevel == 'critical')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: riskColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p.riskLevel.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          // 原因 (为什么需要权限)
          if (p.reason.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              p.reason,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (detail.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm, vertical: AppSpacing.xs + 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: kMonoFont,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // ★ 渲染 options (来自 permission.requested 的结构化选项)
          // 典型: [allow_once, deny] 或 [allow_always, allow_once, deny]
          if (p.options.isNotEmpty)
            Row(
              children: [
                for (int i = 0; i < p.options.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _PermissionOptionButton(
                      option: p.options[i],
                      isPrimary: p.options[i].decision == 'allow',
                      theme: theme,
                      onTap: () => onAnswer(
                          p.id, p.options[i].optionId, p.options[i].decision),
                    ),
                  ),
                ],
              ],
            )
          else
            // 回退: 如果 wire 上 options 为空 (不该发生), 用传统 allow/deny
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => onAnswer(p.id, '', 'allow'),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('允许'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(38),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onAnswer(p.id, '', 'deny'),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('拒绝'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      minimumSize: const Size.fromHeight(38),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// 单个权限选项按钮 (根据 option.decision 自动选颜色)
class _PermissionOptionButton extends StatelessWidget {
  final PermissionOption option;
  final bool isPrimary;
  final ThemeData theme;
  final VoidCallback onTap;

  const _PermissionOptionButton({
    required this.option,
    required this.isPrimary,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDeny = option.decision == 'deny';
    if (isDeny) {
      return OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.close_rounded, size: 16),
        label: Text(option.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.danger,
          minimumSize: const Size.fromHeight(38),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.check_rounded, size: 16),
      label: Text(option.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.success,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(38),
      ),
    );
  }
}

/// plan 提议批准卡片 (AI 调 ExitPlanMode, 等用户批准/拒绝)
///
/// AI 提交计划后后端暂停, 此卡片展示 plan 内容 (兜底用最近 assistant 消息文本,
/// 因 plan 原文 wire 上 inputOmitted) + 批准/拒绝按钮。
class _PlanApprovalCard extends StatelessWidget {
  final String planText;
  final ThemeData theme;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PlanApprovalCard({
    required this.planText,
    required this.theme,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final theme = this.theme;
    // 截断过长 plan 文本 (展示用, 避免卡片撑太高)
    final display = planText.length > 600
        ? '\${planText.substring(0, 600)}...'
        : planText;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'AI 提议的计划',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 280),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: SingleChildScrollView(
              child: MarkdownBody(
                data: display,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.colorScheme.onSurface),
                  h2: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface),
                  code: TextStyle(
                    backgroundColor: theme.colorScheme.surfaceContainerHigh,
                    fontSize: 12,
                    fontFamily: kMonoFont,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('批准并继续'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('拒绝'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    minimumSize: const Size.fromHeight(40),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// AskUserQuestion 交互式问题卡片
///
/// AI 调 AskUserQuestion 工具时, 此卡片渲染问题 + 选项,
/// 用户点选后通过 onAnswer 回调提交。
class _QuestionCard extends StatefulWidget {
  final AskUserQuestion question;
  final void Function(List<String> selected) onAnswer;

  const _QuestionCard({required this.question, required this.onAnswer});

  @override
  State<_QuestionCard> createState() => _QuestionCardState();
}

class _QuestionCardState extends State<_QuestionCard> {
  String? _singleSelect;
  final Set<String> _multiSelect = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = widget.question;

    return Container(
      margin: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.accentContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题行
          Row(
            children: [
              Icon(Icons.help_outline,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: AppSpacing.sm),
              Text(
                q.header.isNotEmpty ? q.header : 'AI 有个问题',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          // 问题文本
          Text(
            q.question,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          // 选项列表
          ...q.options.map((opt) {
            final isSelected = q.multiSelect
                ? _multiSelect.contains(opt.label)
                : _singleSelect == opt.label;
            return _QuestionOption(
              label: opt.label,
              description: opt.description,
              selected: isSelected,
              onTap: () {
                setState(() {
                  if (q.multiSelect) {
                    if (_multiSelect.contains(opt.label)) {
                      _multiSelect.remove(opt.label);
                    } else {
                      _multiSelect.add(opt.label);
                    }
                  } else {
                    _singleSelect = opt.label;
                  }
                });
              },
            );
          }),
          // 提交按钮
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _canSubmit()
                ? () {
                    final selected = q.multiSelect
                        ? _multiSelect.toList()
                        : [_singleSelect!];
                    widget.onAnswer(selected);
                  }
                : null,
            icon: const Icon(Icons.check, size: 18),
            label: Text(q.multiSelect ? '提交选择' : '确认'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ],
      ),
    );
  }

  bool _canSubmit() {
    if (widget.question.multiSelect) return _multiSelect.isNotEmpty;
    return _singleSelect != null;
  }
}

/// 问题选项行
class _QuestionOption extends StatelessWidget {
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _QuestionOption({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppColors.accent.withValues(alpha: 0.5)
                  : theme.dividerColor.withValues(alpha: 0.2),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 选择指示器
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    selected ? Icons.check_circle : Icons.radio_button_unchecked,
                    key: ValueKey(selected),
                    size: 18,
                    color: selected
                        ? AppColors.accent
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              // 文本
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected
                            ? AppColors.accent
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// slash 命令 (/命令面板)
///
/// 协议层命令多为客户端处理; 仅 /compact 接 session/compact RPC。
/// 命令表硬编码 (zcode 桌面端命令集, 见规格 §5.5)。
class _SlashCommand {
  final String name;
  final String desc;
  const _SlashCommand(this.name, this.desc);
}

const _slashCommands = <_SlashCommand>[
  _SlashCommand('/compact', '压缩对话历史'),
  _SlashCommand('/model', '切换模型'),
  _SlashCommand('/agents', '子代理'),
  _SlashCommand('/help', '查看帮助'),
];

class _CommandPalette extends StatelessWidget {
  final String query;
  final ValueChanged<_SlashCommand> onSelected;
  const _CommandPalette({required this.query, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final matches =
        _slashCommands.where((c) => c.name.startsWith(query)).toList();
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: matches.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        itemBuilder: (context, i) {
          final c = matches[i];
          return ListTile(
            dense: true,
            leading: Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.primary),
            title: Text(c.name,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text(c.desc,
                style: TextStyle(
                    fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
            onTap: () => onSelected(c),
          );
        },
      ),
    );
  }
}

// ================================================================
// 统一提及弹窗 (@文件 / #会话 / $技能 / /命令)
// ================================================================

class _MentionOverlay extends ConsumerWidget {
  final String trigger; // @ # $ /
  final String query;
  final String workspacePath;
  final ChatRef chatRef;
  final ValueChanged<String> onSelected; // 传入要插入的完整文本

  const _MentionOverlay({
    required this.trigger,
    required this.query,
    required this.workspacePath,
    required this.chatRef,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = _buildItems(ref);
    if (items.isEmpty) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分类标签
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 2),
            child: Text(
              _triggerLabel(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                return InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => onSelected(item.insertText),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 7),
                    child: Row(
                      children: [
                        Icon(item.icon, size: 16, color: item.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              if (item.subtitle.isNotEmpty)
                                Text(
                                  item.subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _triggerLabel() {
    switch (trigger) {
      case '@':
        return 'FILES';
      case '#':
        return 'SESSIONS';
      case r'$':
        return 'SKILLS';
      case '/':
        return 'COMMANDS';
      default:
        return '';
    }
  }

  List<_MentionItem> _buildItems(WidgetRef ref) {
    final q = query.toLowerCase();
    switch (trigger) {
      case '/':
        return _buildCommands(q);
      case '@':
        return _buildFiles(ref, q);
      case '#':
        return _buildSessions(ref, q);
      case r'$':
        return _buildSkills(ref, q);
      default:
        return [];
    }
  }

  // /命令
  List<_MentionItem> _buildCommands(String q) {
    final matches = _slashCommands
        .where((c) => c.name.toLowerCase().contains(q.isEmpty ? '/' : q))
        .toList();
    return matches
        .map((c) => _MentionItem(
              icon: Icons.chevron_right,
              color: const Color(0xFF60A5FA),
              label: c.name,
              subtitle: c.desc,
              insertText: c.name,
            ))
        .toList();
  }

  // @文件 — 通过 RPC file.listWorkspaceFiles 获取工作区文件列表
  List<_MentionItem> _buildFiles(WidgetRef ref, String q) {
    final client = ref.read(relayClientProvider);
    if (client == null) return [];
    // 同步调用: 从缓存的文件列表过滤
    // 如果没有缓存, 触发异步加载 (下次输入时就有)
    final cached = _workspaceFileCache[workspacePath];
    if (cached == null) {
      // 触发异步加载
      _loadWorkspaceFiles(client);
      return [];
    }

    var files = cached;
    if (q.isNotEmpty) {
      files = files.where((f) => f.toLowerCase().contains(q)).toList();
    }

    if (files.isEmpty && q.isNotEmpty) {
      return [
        _MentionItem(
          icon: Icons.file_present,
          color: const Color(0xFF34D399),
          label: q,
          subtitle: '直接引用此路径',
          insertText: '@$q',
        ),
      ];
    }

    return files.take(20).map((f) {
      final parts = f.split('/');
      final name = parts.last;
      final dir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';
      return _MentionItem(
        icon: Icons.description_outlined,
        color: const Color(0xFF34D399),
        label: name,
        subtitle: dir,
        insertText: '@$f',
      );
    }).toList();
  }

  /// 工作区文件缓存 (per workspacePath)
  static final Map<String, List<String>> _workspaceFileCache = {};
  static final Set<String> _loadingWorkspaces = {};

  void _loadWorkspaceFiles(client) async {
    if (_loadingWorkspaces.contains(workspacePath)) return;
    _loadingWorkspaces.add(workspacePath);
    try {
      final result = await client.listWorkspaceFiles(rootPath: workspacePath);
      final paths = result
          .map((f) => f['relativePath'] as String? ?? f['path'] as String? ?? f['name'] as String? ?? '')
          .where((p) => p.isNotEmpty)
          .toList();
      _workspaceFileCache[workspacePath] = paths;
    } catch (_) {
      // 加载失败, 下次重试
    } finally {
      _loadingWorkspaces.remove(workspacePath);
    }
  }

  // #会话 — 从 allTasksProvider 获取
  List<_MentionItem> _buildSessions(WidgetRef ref, String q) {
    final allTasks = ref.read(allTasksProvider);
    var tasks = allTasks
        .where((t) => t.workspaceKey == workspacePath && !t.archived)
        .toList()
      ..sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0)
          .compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));

    if (q.isNotEmpty) {
      tasks = tasks
          .where((t) => t.title.toLowerCase().contains(q))
          .toList();
    }

    return tasks.take(10).map((t) {
      return _MentionItem(
        icon: t.status == TaskStatus.running
            ? Icons.autorenew
            : Icons.chat_bubble_outline,
        color: const Color(0xFFA78BFA),
        label: t.title,
        subtitle: t.id,
        insertText: '#${t.title}',
      );
    }).toList();
  }

  // $技能 — 从 skillsProvider 获取
  List<_MentionItem> _buildSkills(WidgetRef ref, String q) {
    final skillsAsync = ref.watch(skillsProvider);
    final skills = skillsAsync.valueOrNull ?? [];
    if (skills.isEmpty) return [];

    var filtered = skills.where((s) => s.enabled).toList();
    if (q.isNotEmpty) {
      filtered = filtered
          .where((s) =>
              s.name.toLowerCase().contains(q) ||
              s.description.toLowerCase().contains(q))
          .toList();
    }

    return filtered.take(10).map((s) {
      return _MentionItem(
        icon: Icons.bolt_outlined,
        color: const Color(0xFFFBBF24),
        label: s.name,
        subtitle: s.description.isNotEmpty
            ? (s.description.length > 50
                ? '${s.description.substring(0, 50)}...'
                : s.description)
            : (s.scope ?? ''),
        insertText: r'$' + s.name,
      );
    }).toList();
  }
}

class _MentionItem {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final String insertText;
  const _MentionItem({
    required this.icon,
    required this.color,
    required this.label,
    required this.subtitle,
    required this.insertText,
  });
}

/// 用量统计小药丸 (标题栏副行)
///
/// 同时显示:
/// - Token 用量: ↑1.2k ↓3.4k (本会话累计, 来自 session/usage)
/// - GLM 余量: 本周 45% (Coding Plan, 来自 glmQuotaProvider)
/// 无数据时显示工作区路径的省略形式。
class _UsagePill extends StatelessWidget {
  final ({int input, int output})? tokenUsage;
  final AsyncValue<glm.GlmQuota?> glmQuotaAsync;

  const _UsagePill({this.tokenUsage, required this.glmQuotaAsync});

  static String _fmt(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final k = n / 1000;
      return k >= 100 ? '${k.toStringAsFixed(0)}k' : '${k.toStringAsFixed(1)}k';
    }
    final m = n / 1000000;
    return m >= 100 ? '${m.toStringAsFixed(0)}M' : '${m.toStringAsFixed(1)}M';
  }

  static String _fmtPct(double v) {
    if (v <= 0) return '0%';
    if (v >= 100) return '100%';
    return v >= 10 ? '${v.toStringAsFixed(0)}%' : '${v.toStringAsFixed(1)}%';
  }

  Color _pctColor(double pct, BuildContext context) {
    if (pct >= 90) return const Color(0xFFEF4444);
    if (pct >= 70) return const Color(0xFFF59E0B);
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quota = glmQuotaAsync.valueOrNull;
    final parts = <_UsagePart>[];

    // Token 用量
    if (tokenUsage != null) {
      parts.add(_UsagePart(
        icon: Icons.bolt_outlined,
        text: '↑${_fmt(tokenUsage!.input)} ↓${_fmt(tokenUsage!.output)}',
        color: theme.colorScheme.onSurfaceVariant,
      ));
    }

    // GLM 余量 (优先显示 weekly, 其次 five_hour)
    if (quota != null && quota.hasData) {
      final tier = quota.weeklyTier ?? quota.fiveHourTier;
      if (tier != null) {
        parts.add(_UsagePart(
          icon: Icons.local_fire_department_outlined,
          text: _fmtPct(tier.utilization),
          color: _pctColor(tier.utilization, context),
        ));
      }
    }

    if (parts.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 2,
      children: parts.map((p) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(p.icon, size: 11, color: p.color),
          const SizedBox(width: 3),
          Text(
            p.text,
            style: TextStyle(
              fontSize: 11,
              fontFamily: kMonoFont,
              color: p.color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      )).toList(),
    );
  }
}

class _UsagePart {
  final IconData icon;
  final String text;
  final Color color;
  const _UsagePart({required this.icon, required this.text, required this.color});
}

/// Token 用量 badge (输入栏内显示)
///
/// AI 每轮回复完成后由 ChatNotifier 刷新 state.tokenUsage (累计 input/output)。
/// composer 圆形发送按钮 (上箭头/停止)
class _ComposerSendButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final bool enabled;
  final bool isStop;

  const _ComposerSendButton({
    required this.icon,
    required this.onPressed,
    required this.enabled,
    this.isStop = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isStop
        ? AppColors.danger
        : (enabled ? theme.colorScheme.primary : theme.colorScheme.outline);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: (isStop || enabled)
                ? color
                : theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      ),
    );
  }
}

/// 工具栏 chip (icon + label, 可点击下拉)
class _ToolbarChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _ToolbarChip({
    required this.icon,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 滚动到底部悬浮按钮: 当用户不在底部时出现。
/// AI 正在回复时显示蓝色高亮 + 小红点提示有新内容。
class _ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool hasNewContent;

  const _ScrollToBottomButton({
    required this.onPressed,
    this.hasNewContent = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: hasNewContent
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasNewContent
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: hasNewContent ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 24,
              color: hasNewContent
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            if (hasNewContent)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: theme.colorScheme.surfaceContainerHigh,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Token 用量徽章 (compact, 等宽, 状态行副标题用)。
/// 格式: ↑1.2k ↓3.4k — ↑=输入(prompt), ↓=输出(completion)。
/// 数字: <1000 原值; >=1000 用 1.2k (>=100k 去小数, >=1M 用 M)。
class _TokenUsageBadge extends StatelessWidget {
  final ({int input, int output})? usage;

  const _TokenUsageBadge({this.usage});

  /// 紧凑数字格式化: 999 → 999, 1234 → 1.2k, 12345 → 12.3k, 123456 → 123k, 1234567 → 1.2M
  static String _fmt(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) {
      final k = n / 1000;
      return k >= 100 ? '${k.toStringAsFixed(0)}k' : '${k.toStringAsFixed(1)}k';
    }
    final m = n / 1000000;
    return m >= 100 ? '${m.toStringAsFixed(0)}M' : '${m.toStringAsFixed(1)}M';
  }

  @override
  Widget build(BuildContext context) {
    final u = usage;
    if (u == null) return const SizedBox.shrink();
    return Text(
      '↑${_fmt(u.input)} ↓${_fmt(u.output)}',
      style: TextStyle(
        fontSize: 11,
        fontFamily: kMonoFont,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// 代理模式选择 (新/已有会话都显示)
///
/// 协议实测只有两种模式 (规格 §5.5 `mode:{current:"yolo"|"build"}`):
/// - build = 确认模式, 工具执行前需用户确认
/// - yolo  = 自动模式, AI 全自动无需确认
/// 新会话设 createSession.mode; 已有会话走 session/setMode 热切换。
/// 代理模式选择器 (popover 下拉, 4 选项)
///
/// 协议只有 build/yolo 两种, UI 映射 4 档自主度:
///   变更前确认 → build (改文件前先问)
///   自动编辑   → yolo (自动编辑文件)
///   计划模式   → build (先出计划, 映射到 build 谨慎态)
///   完全访问   → yolo (最少确认, 映射到 yolo)
/// 模式选择结果 (带计划子态标记)
class _ModeSelector extends StatelessWidget {
  final String mode; // 'build' | 'plan' | 'yolo' (wire 值, 与后端一致)
  final ValueChanged<String> onChanged;

  const _ModeSelector({required this.mode, required this.onChanged});

  // UI 模式定义: (apiMode, icon, title, desc)
  // wire mode 实测三种 (抓包 settings.mode.options):
  //   build — 默认, 改文件前确认
  //   plan  — 只读/规划, 不改 workspace (UI "计划模式")
  //   yolo  — 自动执行, 无确认
  static const _options = <(String, IconData, String, String)>[
    ('build', Icons.back_hand_outlined, '变更前确认', '改文件前先问我'),
    ('plan', Icons.event_note_outlined, '计划模式', '只读规划, 不直接改文件'),
    ('yolo', Icons.shield_outlined, '自动编辑', '自动编辑文件'),
  ];

  /// 当前选中的 UI 项索引
  int get _selectedIndex {
    for (int i = 0; i < _options.length; i++) {
      if (_options[i].$1 == mode) return i;
    }
    return 0;
  }

  (String, IconData, String, String) get _current =>
      _options[_selectedIndex];

  void _open(BuildContext context) {
    // 用 MenuAnchor 实现锚定 popover
    final theme = Theme.of(context);
    final cur = _selectedIndex;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('执行模式',
                      style: theme.textTheme.titleMedium),
                ),
              ),
              for (int i = 0; i < _options.length; i++)
                _ModeOptionTile(
                  icon: _options[i].$2,
                  title: _options[i].$3,
                  desc: _options[i].$4,
                  selected: i == cur,
                  onTap: () {
                    onChanged(_options[i].$1);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_current.$2,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(_current.$3,
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// 模式选项 tile (图标 + 标题/描述 + 对勾)
class _ModeOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOptionTile({
    required this.icon,
    required this.title,
    required this.desc,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      leading: Icon(icon,
          size: 20,
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant),
      title: Text(title,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: theme.colorScheme.onSurface,
          )),
      subtitle: Text(desc,
          style: TextStyle(
              fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
      trailing: selected
          ? Icon(Icons.check_rounded, size: 20, color: theme.colorScheme.primary)
          : null,
    );
  }
}

/// 思考级别选择器 (深思考 / 浅思考 / 关闭)
class _ThoughtLevelSelector extends StatelessWidget {
  final String level; // 'max' | 'medium' | 'nothink'
  final ValueChanged<String> onChanged;

  const _ThoughtLevelSelector({required this.level, required this.onChanged});

  static const _options = <(String, IconData, String, String)>[
    ('max', Icons.psychology, 'max', '完整推理链'),
    ('medium', Icons.lightbulb_outline, 'medium', '适度推理'),
    ('nothink', Icons.flash_off_outlined, 'nothink', '直接回答'),
  ];

  (IconData, String) get _current {
    for (final o in _options) {
      if (o.$1 == level) return (o.$2, o.$3);
    }
    return (Icons.psychology, 'max');
  }

  void _open(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('思考级别', style: theme.textTheme.titleMedium),
                ),
              ),
              for (final o in _options)
                _ModeOptionTile(
                  icon: o.$2,
                  title: o.$3,
                  desc: o.$4,
                  selected: o.$1 == level,
                  onTap: () {
                    onChanged(o.$1);
                    Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = _current;
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cur.$1, size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(cur.$2,
                style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 2),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}



/// 模型选择底部表 (模型按钮 + /model 命令共用)
void showModelPicker(
  BuildContext context, {
  required List<String> models,
  required String? current,
  required ValueChanged<String> onSelected,
  Map<String, String> providerNames = const {},
}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Color.alphaBlend(
      Theme.of(context).colorScheme.surfaceContainerHigh,
      Theme.of(context).colorScheme.surfaceContainerLowest,
    ),
    builder: (ctx) => _ModelPickerSheet(
      models: models,
      current: current,
      onSelected: onSelected,
      providerNames: providerNames,
    ),
  );
}

class _ModelPickerSheet extends StatefulWidget {
  final List<String> models;
  final String? current;
  final ValueChanged<String> onSelected;
  final Map<String, String> providerNames;

  const _ModelPickerSheet({
    required this.models,
    required this.current,
    required this.onSelected,
    required this.providerNames,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String slug(String id) => id.split('/').last;
    String providerLabel(String pid) => widget.providerNames[pid] ?? pid;

    // 过滤
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.models
        : widget.models.where((m) => m.toLowerCase().contains(query)).toList();

    // 分组
    final groups = <String, List<String>>{};
    final order = <String>[];
    for (final m in filtered) {
      final pid = m.contains('/') ? m.split('/').first : '其他';
      (groups[pid] ??= []).add(m);
      if (!order.contains(pid)) order.add(pid);
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              // 标题栏
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(children: [
                  Text('选择模型', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text('${widget.models.length} 个模型',
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                ]),
              ),
              // 搜索框
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: '搜索模型...',
                    hintStyle: TextStyle(fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
                    prefixIcon: Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () { _searchController.clear(); setState(() => _query = ''); },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              // 模型列表
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(query.isEmpty ? '暂无可用模型' : '未找到匹配的模型',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13)),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          for (final pid in order) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Row(children: [
                                Icon(Icons.dns_outlined, size: 13, color: theme.colorScheme.primary),
                                const SizedBox(width: 4),
                                Text(providerLabel(pid),
                                    style: theme.textTheme.labelMedium?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(width: 6),
                                Text('${groups[pid]!.length}',
                                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                              ]),
                            ),
                            for (final m in groups[pid]!)
                              ListTile(
                                dense: true,
                                leading: Icon(
                                  m == widget.current
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: m == widget.current
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                                title: Text(slug(m),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: m == widget.current ? FontWeight.w600 : FontWeight.w400,
                                    )),
                                onTap: () {
                                  widget.onSelected(m);
                                  Navigator.pop(context);
                                },
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模型选择按钮 (输入栏右侧); 加载中/空列表自适应
class _ModelSelector extends StatelessWidget {
  final List<String> models;
  final String? current;
  final ValueChanged<String> onSelected;
  final Map<String, String> providerNames;
  final bool isLoading;

  const _ModelSelector({
    required this.models,
    required this.current,
    required this.onSelected,
    this.providerNames = const {},
    this.isLoading = false,
  });

  String get _label {
    if (current != null) return current!.split('/').last;
    // 无选择时取第一个可用模型名
    if (models.isNotEmpty) return models.first.split('/').last;
    return '默认';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ActionChip(
      avatar: isLoading
          ? SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2, color: theme.colorScheme.primary),
            )
          : Icon(Icons.memory, size: 16, color: theme.colorScheme.primary),
      label: Text(_label, style: const TextStyle(fontSize: 12)),
      tooltip: models.isEmpty
          ? (isLoading ? '正在加载模型...' : '模型列表未加载')
          : '切换模型',
      onPressed: (models.isEmpty && !isLoading)
          ? null
          : () => showModelPicker(context,
              models: models,
              current: current,
              onSelected: onSelected,
              providerNames: providerNames),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 判断两个 DateTime 是否同一天
bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 日期分组标签 (居中药丸形)
class _DateSeparator extends StatelessWidget {
  final DateTime date;
  const _DateSeparator({required this.date});

  String _format(DateTime d) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(d, now)) return '今天';
    if (_isSameDay(d, yesterday)) return '昨天';
    return '${d.month}月${d.day}日';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            _format(date),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// 消息头像 (AI: 渐变圆 + spark; 用户: 蓝色圆 + person)
class _Avatar extends StatelessWidget {
  final String role; // 'user' | 'assistant'
  final ThemeData theme;

  const _Avatar({required this.role, required this.theme});

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isUser
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.accent, const Color(0xFF8B5CF6)],
              ),
        color: isUser ? AppColors.accent : null,
      ),
      child: Icon(
        isUser ? Icons.person_rounded : Icons.auto_awesome,
        size: 15,
        color: Colors.white,
      ),
    );
  }
}

/// 消息气泡
///
/// 用户: 强调色填充, 右对齐
/// AI: 透明面 + 左侧强调竖条 (开发者工具气质, 非圆胖聊天气泡)
/// 消息反馈类型 (赞/踩)
enum _Feedback { like, dislike }

/// 消息气泡 (用户/AI/错误)
class _MessageBubble extends StatefulWidget {
  final DisplayMessage message;
  final ThemeData theme;
  /// 是否为最后一条用户消息 (用于撤销功能)
  final bool isLastUserMessage;
  /// AI 是否正在响应中 (用于撤销功能的可用性判断)
  final bool isResponding;
  /// 编辑消息回调 (用户消息)
  final void Function(String)? onEdit;
  /// 撤销最后一轮回调
  final VoidCallback? onRewind;

  const _MessageBubble({
    required this.message,
    required this.theme,
    this.isLastUserMessage = false,
    this.isResponding = false,
    this.onEdit,
    this.onRewind,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  /// 本地赞/踩状态 (UI-only, 无 RPC)
  _Feedback? _feedback;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final theme = widget.theme;
    final isUser = message.role == 'user';
    final isError = message.role == 'error';

    if (isError) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(message.content,
                style: TextStyle(color: AppColors.danger, fontSize: 13)),
          ),
        ]),
      );
    }

    if (isUser) {
      // 用户气泡: 强调色填充, 右对齐 + 编辑按钮
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.82),
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.lg),
                  topRight: Radius.circular(AppRadius.lg),
                  bottomLeft: Radius.circular(AppRadius.lg),
                  bottomRight: Radius.circular(AppRadius.xs),
                ),
              ),
              child: MarkdownBody(
                data: message.content,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                  code: TextStyle(
                    backgroundColor: Colors.black26,
                    fontSize: 13,
                    fontFamily: kMonoFont,
                  ),
                ),
              ),
            ),
          ),
          // 编辑按钮
          if (widget.onEdit != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: AppSpacing.xs),
              child: GestureDetector(
                onTap: () => _showEditSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit_outlined, size: 14,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('编辑',
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // AI 气泡: 跟随主题 (深色=深灰面, 浅色=白底微灰)
    final isDark = theme.brightness == Brightness.dark;
    final aiBg = isDark ? const Color(0xFF1F2024) : theme.colorScheme.surfaceContainerHigh;
    final aiInk = isDark ? const Color(0xFFE8EAED) : theme.colorScheme.onSurface;
    final aiCodeBg = isDark ? const Color(0xFF0D0E11) : theme.colorScheme.surfaceContainerHighest;

    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showMessageMenu(context, message),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.96),
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.md, AppSpacing.sm + 2, AppSpacing.md, AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: aiBg,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.lg),
              topRight: Radius.circular(AppRadius.lg),
              bottomLeft: Radius.circular(AppRadius.xs),
              bottomRight: Radius.circular(AppRadius.lg),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 思考过程 (折叠)
              if (message.thought != null && message.thought!.isNotEmpty)
                _ThoughtBlock(thought: message.thought!, theme: theme),
              // 正文 — 硬编码高对比文字
              MarkdownBody(
                data: message.content.isEmpty && message.isStreaming
                    ? '_(思考中...)_'
                    : message.content,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(color: aiInk, fontSize: 14, height: 1.6),
                  code: TextStyle(
                    backgroundColor: aiCodeBg,
                    fontSize: 13,
                    fontFamily: kMonoFont,
                    color: aiInk,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: aiCodeBg,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                builders: {
                  'pre': _CodeBlockBuilder(theme: theme),
                },
              ),
              // 流式光标
              if (message.isStreaming)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _TypingCursor(color: AppColors.accent),
                ),
              // 变更文件摘要 (从工具活动中提取文件操作, 聚合展示)
              if (message.activities.any(_isFileActivity) && !message.isStreaming)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: _ChangedFilesSummary(
                    activities: message.activities,
                    theme: theme,
                    inkColor: aiInk,
                  ),
                ),
              // 工具调用详情卡片 (折叠式, 正文之后)
              if (message.activities.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: _ToolActivityCards(
                    activities: message.activities,
                    theme: theme,
                    inkColor: aiInk,
                  ),
                ),
              // 赞/踩按钮 (非流式 AI 消息)
              if (!message.isStreaming && message.content.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _FeedbackButton(
                        icon: Icons.thumb_up_outlined,
                        activeIcon: Icons.thumb_up,
                        isActive: _feedback == _Feedback.like,
                        color: AppColors.accent,
                        onTap: () => setState(() {
                          _feedback = _feedback == _Feedback.like
                              ? null
                              : _Feedback.like;
                        }),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _FeedbackButton(
                        icon: Icons.thumb_down_outlined,
                        activeIcon: Icons.thumb_down,
                        isActive: _feedback == _Feedback.dislike,
                        color: AppColors.danger,
                        onTap: () => setState(() {
                          _feedback = _feedback == _Feedback.dislike
                              ? null
                              : _Feedback.dislike;
                        }),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 编辑消息 — 底部弹出编辑框 (实色背景)
  void _showEditSheet(BuildContext context) {
    final theme = Theme.of(context);
    final controller = TextEditingController(text: widget.message.content);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surfaceContainerHighest,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
              child: Row(
                children: [
                  Text('编辑消息',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                ],
              ),
            ),
            // 编辑框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: TextField(
                controller: controller,
                maxLines: 5,
                minLines: 1,
                autofocus: true,
                style: TextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: AppColors.accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(AppSpacing.md),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            // 发送按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final text = controller.text.trim();
                    Navigator.pop(ctx);
                    if (text.isNotEmpty) {
                      widget.onEdit?.call(text);
                    }
                  },
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('发送'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm + 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// AI 消息长按菜单 (复制/分享/撤销)
  void _showMessageMenu(BuildContext context, DisplayMessage message) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 预览 (截断的消息内容)
            if (message.content.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  message.content.length > 120
                      ? '${message.content.substring(0, 120)}...'
                      : message.content,
                  style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant),
                  maxLines: 3,
                ),
              ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制全文'),
              onTap: () async {
                Navigator.pop(ctx);
                await Clipboard.setData(
                    ClipboardData(text: message.content));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('已复制'),
                        duration: Duration(seconds: 1)),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('分享'),
              onTap: () {
                Navigator.pop(ctx);
                Share.share(message.content);
              },
            ),
            // 撤销最后一轮 (仅最后一条用户消息 + 非响应中)
            if (widget.isLastUserMessage &&
                !widget.isResponding &&
                widget.onRewind != null)
              ListTile(
                leading: const Icon(Icons.undo, color: AppColors.warning),
                title: const Text('撤销最后一轮'),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onRewind!.call();
                },
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// 赞/踩按钮 (小尺寸, inline)
class _FeedbackButton extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final Color color;
  final VoidCallback onTap;

  const _FeedbackButton({
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xs),
        child: Icon(
          isActive ? activeIcon : icon,
          size: 16,
          color: isActive
              ? color
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// 判断工具活动是否是文件操作 (写/编辑/创建/删除文件)
bool _isFileActivity(ToolActivity a) {
  final n = a.toolName.toLowerCase();
  return n.contains('edit') ||
      n.contains('write') ||
      n.contains('create') ||
      n.contains('str_replace') ||
      n.contains('file') ||
      n.contains('delete') ||
      n.contains('remove');
}

/// 从工具活动中提取变更的文件路径
/// 优先从 input 中取 path/file_path, 回退到 result 中搜索路径模式
String? _extractFilePath(ToolActivity a) {
  final input = a.input;
  if (input != null) {
    for (final key in ['file_path', 'path', 'filename', 'file']) {
      final v = input[key];
      if (v is String && v.isNotEmpty) return v;
    }
  }
  // 回退: 从 result 中提取文件路径 (形如 /path/to/file.ext)
  final result = a.result ?? '';
  final match = RegExp(r'[/\w]+\.\w+').firstMatch(result);
  return match?.group(0);
}

/// 变更文件摘要 (折叠式 — 展示 N 个文件已更改 +N -M)
class _ChangedFilesSummary extends StatefulWidget {
  final List<ToolActivity> activities;
  final ThemeData theme;
  final Color inkColor;

  const _ChangedFilesSummary({
    required this.activities,
    required this.theme,
    required this.inkColor,
  });

  @override
  State<_ChangedFilesSummary> createState() => _ChangedFilesSummaryState();
}

class _ChangedFilesSummaryState extends State<_ChangedFilesSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final fileActivities = widget.activities.where(_isFileActivity).toList();

    // 提取唯一文件路径
    final fileMap = <String, ToolActivity>{};
    for (final a in fileActivities) {
      final path = _extractFilePath(a);
      if (path != null && path.isNotEmpty) {
        fileMap[path] = a;
      }
    }
    final files = fileMap.keys.toList();

    // 统计增删行数 (从 result 中尝试提取 +N -M)
    int totalAdded = 0;
    int totalRemoved = 0;
    for (final a in fileActivities) {
      final result = a.result ?? '';
      // 匹配 +N -M 格式
      final addMatch = RegExp(r'\+(\d+)').firstMatch(result);
      final delMatch = RegExp(r'-(\d+)').firstMatch(result);
      if (addMatch != null) totalAdded += int.tryParse(addMatch.group(1)!) ?? 0;
      if (delMatch != null) totalRemoved += int.tryParse(delMatch.group(1)!) ?? 0;
    }

    final cardBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部: "N 个文件已更改  +N -M"
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.difference_outlined,
                      size: 16, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    '${files.length} 个文件已更改',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: widget.inkColor),
                  ),
                  const SizedBox(width: 8),
                  if (totalAdded > 0)
                    Text('+$totalAdded',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.success)),
                  if (totalRemoved > 0) ...[
                    const SizedBox(width: 4),
                    Text('-$totalRemoved',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.danger)),
                  ],
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // 展开详情: 文件列表
          if (_expanded && files.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm + 2, 0, AppSpacing.sm + 2, AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(
                      height: 1,
                      color: widget.inkColor.withValues(alpha: 0.08)),
                  const SizedBox(height: AppSpacing.sm),
                  for (final path in files)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(_fileIcon(path),
                              size: 14,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              path.split('/').last,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: kMonoFont,
                                  color: widget.inkColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              path,
                              style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  IconData _fileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'dart' => Icons.flutter_dash,
      'py' => Icons.code,
      'js' || 'ts' || 'jsx' || 'tsx' => Icons.javascript,
      'json' || 'yaml' || 'yml' || 'toml' || 'xml' => Icons.settings,
      'md' => Icons.description,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' =>
        Icons.image_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

/// 工具调用统一折叠容器 (所有工具调用合并到一张卡, 节省空间)
///
/// 折叠态: 头部一行摘要 "🔧 N 个工具调用 · M 完成 / K 运行中"
/// 展开态: 内部按工具类型分组:
///   - 子代理 (Agent/Explore/Task): 整体折叠成 "🤖 调用了 N 个子任务"
///   - 普通工具: 精简行列表 (图标+名+状态), 点击单行展开详情
class _ToolActivityCards extends StatefulWidget {
  final List<ToolActivity> activities;
  final ThemeData theme;
  final Color inkColor;

  const _ToolActivityCards({
    required this.activities,
    required this.theme,
    required this.inkColor,
  });

  @override
  State<_ToolActivityCards> createState() => _ToolActivityCardsState();
}

class _ToolActivityCardsState extends State<_ToolActivityCards> {
  bool _expanded = false;
  bool _subagentsExpanded = false;
  // 记录哪些工具行被单独展开 (按 toolCallId)
  final Set<String> _expandedRows = {};

  /// 是否为子代理调用 (Agent / Explore / Task 等)
  bool _isSubagent(ToolActivity a) {
    final n = a.toolName.toLowerCase();
    return n == 'agent' ||
        n == 'task' ||
        n == 'explore' ||
        n.contains('subagent') ||
        n.startsWith('explore');
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final activities = widget.activities;
    if (activities.isEmpty) return const SizedBox.shrink();

    final subagents = activities.where(_isSubagent).toList();
    final tools = activities.where((a) => !_isSubagent(a)).toList();

    final running = activities.where((a) => a.isRunning).length;
    final completed = activities
        .where((a) =>
            a.status == 'result' ||
            a.status == 'done' ||
            a.status == 'complete' ||
            a.status == 'completed' ||
            a.status == 'success')
        .length;
    final errors = activities
        .where((a) => a.status == 'error' || a.status == 'failed')
        .length;

    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;

    return Container(
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部: 摘要 + 折叠箭头
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm + 2, vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Icon(Icons.build_outlined,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '${activities.length} 个工具调用',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 状态摘要: M✓ K● ✗N
                  Flexible(
                    child: Text(
                      [
                        if (completed > 0) '$completed 完成',
                        if (running > 0) '$running 运行中',
                        if (errors > 0) '$errors 出错',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 11,
                        color: running > 0
                            ? AppColors.accent
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (running > 0)
                    const SizedBox(
                      width: 11,
                      height: 11,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    )
                  else
                    Icon(
                      errors > 0 ? Icons.error_outline : Icons.check_circle,
                      size: 13,
                      color: errors > 0
                          ? AppColors.danger
                          : AppColors.success,
                    ),
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.chevron_right,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // 展开后: 子代理区 + 普通工具行
          if (_expanded) ...[
            // 子代理 (整体折叠, 因为内容多)
            if (subagents.isNotEmpty)
              _SubagentSection(
                subagents: subagents,
                theme: theme,
                inkColor: widget.inkColor,
                expanded: _subagentsExpanded,
                onToggle: () => setState(
                    () => _subagentsExpanded = !_subagentsExpanded),
                expandedRows: _expandedRows,
                onRowToggle: (id) => setState(() {
                  if (_expandedRows.contains(id)) {
                    _expandedRows.remove(id);
                  } else {
                    _expandedRows.add(id);
                  }
                }),
              ),
            // 普通工具行
            if (tools.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm + 2, 0, AppSpacing.sm + 2, AppSpacing.sm),
                child: Column(
                  children: [
                    for (final a in tools) ...[
                      _ToolActivityRow(
                        activity: a,
                        theme: theme,
                        inkColor: widget.inkColor,
                        expanded: _expandedRows.contains(a.toolCallId),
                        onToggle: () => setState(() {
                          if (_expandedRows.contains(a.toolCallId)) {
                            _expandedRows.remove(a.toolCallId);
                          } else {
                            _expandedRows.add(a.toolCallId);
                          }
                        }),
                      ),
                      const SizedBox(height: 2),
                    ],
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// 工具名 → emoji 图标 (顶层函数, 供多处复用)
String _emojiFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('search') ||
      n.contains('grep') ||
      n.contains('glob') ||
      n.contains('find')) {
    return '🔍';
  }
  if (n.contains('edit') ||
      n.contains('write') ||
      n.contains('create') ||
      n.contains('str_replace') ||
      n.contains('file')) {
    return '📝';
  }
  if (n.contains('bash') ||
      n.contains('shell') ||
      n.contains('terminal') ||
      n.contains('cmd') ||
      n.contains('run') ||
      n.contains('exec')) {
    return '⚡';
  }
  if (n.contains('web') ||
      n.contains('browser') ||
      n.contains('fetch') ||
      n.contains('curl') ||
      n.contains('url')) {
    return '🌐';
  }
  if (n == 'agent' || n == 'task' || n.contains('subagent') || n == 'explore') {
    return '🤖';
  }
  return '🔧';
}

/// 子代理调用区 (Agent/Explore/Task, 整体可折叠, 默认折叠)
class _SubagentSection extends StatelessWidget {
  final List<ToolActivity> subagents;
  final ThemeData theme;
  final Color inkColor;
  final bool expanded;
  final VoidCallback onToggle;
  final Set<String> expandedRows;
  final void Function(String id) onRowToggle;

  const _SubagentSection({
    required this.subagents,
    required this.theme,
    required this.inkColor,
    required this.expanded,
    required this.onToggle,
    required this.expandedRows,
    required this.onRowToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = this.theme;
    final running = subagents.where((a) => a.isRunning).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm + 2, vertical: AppSpacing.sm - 2),
            child: Row(
              children: [
                Icon(Icons.hub_outlined,
                    size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Text(
                  '${subagents.length} 个子任务',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (running > 0) ...[
                  const SizedBox(width: 6),
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('$running 运行中',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.accent)),
                ],
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(Icons.chevron_right,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(
                bottom: AppSpacing.xs),
            child: Column(
              children: [
                for (final a in subagents) ...[
                  _ToolActivityRow(
                    activity: a,
                    theme: theme,
                    inkColor: inkColor,
                    expanded: expandedRows.contains(a.toolCallId),
                    onToggle: () => onRowToggle(a.toolCallId),
                  ),
                  const SizedBox(height: 2),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// 工具调用精简单行 (无独立卡片背景, 点击展开详情)
class _ToolActivityRow extends StatelessWidget {
  final ToolActivity activity;
  final ThemeData theme;
  final Color inkColor;
  final bool expanded;
  final VoidCallback onToggle;

  const _ToolActivityRow({
    required this.activity,
    required this.theme,
    required this.inkColor,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final a = activity;
    final theme = this.theme;
    final running = a.isRunning;
    final isError = a.status == 'error' || a.status == 'failed';

    final emoji = _emojiFor(a.toolName);
    final statusText = switch (a.status) {
      'scheduled' => '排队',
      'started' || 'progress' || 'running' => '运行中',
      'result' || 'done' || 'complete' || 'completed' || 'success' => '完成',
      'error' || 'failed' => '出错',
      _ => a.status,
    };
    final elapsed = a.elapsedMs != null
        ? ' · ${(a.elapsedMs! / 1000).toStringAsFixed(1)}s'
        : '';

    final Widget statusIcon;
    if (running) {
      statusIcon = const SizedBox(
        width: 10,
        height: 10,
        child: CircularProgressIndicator(
          strokeWidth: 1.3,
          valueColor: AlwaysStoppedAnimation(AppColors.accent),
        ),
      );
    } else if (isError) {
      statusIcon =
          const Text('✗', style: TextStyle(color: AppColors.danger, fontSize: 13));
    } else {
      statusIcon = const Text('✓',
          style: TextStyle(color: AppColors.success, fontSize: 13));
    }

    final hasDetail =
        (a.input != null && a.input!.isNotEmpty) ||
        (a.result != null && a.result!.isNotEmpty);

    final detailBg = theme.brightness == Brightness.dark
        ? const Color(0xFF0D0E11)
        : theme.colorScheme.surfaceContainerHighest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasDetail ? onToggle : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    a.toolName,
                    style: TextStyle(
                        fontSize: 12, fontFamily: kMonoFont, color: inkColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '$statusText$elapsed',
                  style: TextStyle(
                    fontSize: 11,
                    color: running
                        ? AppColors.accent
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
                statusIcon,
                if (hasDetail) ...[
                  const SizedBox(width: 2),
                  AnimatedRotation(
                    turns: expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Icon(Icons.chevron_right,
                        size: 13,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
        // 展开详情 (输入参数 + 结果)
        if (expanded && hasDetail) ...[
          const SizedBox(height: 2),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: detailBg,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.input != null && a.input!.isNotEmpty) ...[
                  Text('参数',
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  ...a.input!.entries.map((e) {
                    final valStr = e.value is String
                        ? e.value as String
                        : e.value.toString();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Text(
                        valStr.length > 150
                            ? '${e.key}: ${valStr.substring(0, 150)}...'
                            : '${e.key}: $valStr',
                        style: TextStyle(
                            fontSize: 11,
                            fontFamily: kMonoFont,
                            color: inkColor),
                      ),
                    );
                  }),
                ],
                if (a.result != null && a.result!.isNotEmpty) ...[
                  if (a.input != null && a.input!.isNotEmpty)
                    const SizedBox(height: AppSpacing.xs),
                  Text('结果',
                      style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                    a.result!.length > 300
                        ? '${a.result!.substring(0, 300)}...'
                        : a.result!,
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: kMonoFont,
                        color: inkColor),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}



/// 思考过程折叠块
class _ThoughtBlock extends StatefulWidget {
  final String thought;
  final ThemeData theme;

  const _ThoughtBlock({required this.thought, required this.theme});

  @override
  State<_ThoughtBlock> createState() => _ThoughtBlockState();
}

class _ThoughtBlockState extends State<_ThoughtBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: widget.theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 4),
                Text(
                  '思考过程',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.theme.colorScheme.onSurface,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Text(
                widget.thought,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.theme.colorScheme.onSurface,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 打字光标动画
class _TypingCursor extends StatefulWidget {
  final Color color;

  const _TypingCursor({required this.color});

  @override
  State<_TypingCursor> createState() => _TypingCursorState();
}

class _TypingCursorState extends State<_TypingCursor>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 16,
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 代码块构建器: 带复制按钮 + 语言标签 + 等宽字体
class _CodeBlockBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  _CodeBlockBuilder({required this.theme});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    String code = '';
    String? language;
    final codeNode = element.children?.first;
    if (codeNode is md.Element && codeNode.tag == 'code') {
      code = codeNode.textContent;
      final cls = codeNode.attributes['class'] ?? '';
      final match = RegExp(r'language-(\w+)').firstMatch(cls);
      language = match?.group(1);
    }
    return _CodeBlock(code: code, language: language, theme: theme);
  }
}

/// 代码块 widget: 顶栏(语言+复制+行数) + 语法高亮 + 折叠展开
class _CodeBlock extends StatefulWidget {
  final String code;
  final String? language;
  final ThemeData theme;
  const _CodeBlock({required this.code, this.language, required this.theme});
  @override
  State<_CodeBlock> createState() => _CodeBlockState();
}

class _CodeBlockState extends State<_CodeBlock> {
  bool _copied = false;
  bool _expanded = false;

  /// 超过此行数默认折叠
  static const _collapseThreshold = 15;

  int get _lineCount => '\n'.allMatches(widget.code).length + 1;
  bool get _shouldCollapse => _lineCount > _collapseThreshold;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isDark = theme.brightness == Brightness.dark;
    final showCollapsed = _shouldCollapse && !_expanded;
    // 折叠时只显示前 N 行
    final displayCode = showCollapsed
        ? widget.code.split('\n').take(_collapseThreshold).join('\n')
        : widget.code;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0E11) : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶栏: 语言标签 + 行数 + 复制按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF161719)
                  : const Color(0xFFEFF2F5),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(children: [
              if (widget.language != null)
                Text(widget.language!,
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Text('$_lineCount 行',
                  style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6))),
              const Spacer(),
              InkWell(
                onTap: _copy,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        _copied ? Icons.check : Icons.copy,
                        size: 14,
                        color: _copied
                            ? Colors.green
                            : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(_copied ? '已复制' : '复制',
                        style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ]),
                ),
              ),
            ]),
          ),
          // 代码内容: 语法高亮 + 横向滚动
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: CodeHighlightView(
              code: displayCode,
              language: widget.language,
              isDark: isDark,
            ),
          ),
          // 折叠/展开按钮
          if (_shouldCollapse)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.2)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _expanded
                          ? '收起'
                          : '展开剩余 ${_lineCount - _collapseThreshold} 行',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ================================================================
// 工作区主页组件 (新会话空状态)
// ================================================================

/// 项目信息卡 — 进入工作区后第一眼看到的项目概览
class _ProjectInfoCard extends StatelessWidget {
  final Workspace? workspace;
  final String workspacePath;
  final RelayConnectionState? connState;

  const _ProjectInfoCard({
    required this.workspace,
    required this.workspacePath,
    required this.connState,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = workspace?.name ??
        workspacePath.split('/').where((s) => s.isNotEmpty).lastOrNull ??
        '项目';
    final isRemote = workspace?.kind == WorkspaceKind.remote;
    final branch = workspace?.branch;

    final (connColor, connLabel) = switch (connState) {
      RelayConnectionState.ready => (AppColors.success, '已连接'),
      RelayConnectionState.connecting ||
      RelayConnectionState.connected =>
        (AppColors.warning, '连接中'),
      RelayConnectionState.reconnecting => (AppColors.warning, '重连中'),
      RelayConnectionState.disconnected ||
      RelayConnectionState.error => (AppColors.danger, '未连接'),
      _ => (theme.colorScheme.onSurfaceVariant, '待连接'),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.accentContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  isRemote ? Icons.cloud_outlined : Icons.folder_outlined,
                  size: 20,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 2),
          Text(
            workspacePath,
            style: AppText.mono(context,
                size: 11, color: theme.colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (branch != null)
                _InfoTag(icon: Icons.call_split, label: branch),
              _InfoTag(
                icon:
                    isRemote ? Icons.cloud_outlined : Icons.computer_outlined,
                label: isRemote ? '远程' : '本地',
              ),
              _InfoTag(
                icon: Icons.circle,
                iconSize: 7,
                label: connLabel,
                color: connColor,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 信息标签 (项目卡内的小标签)
class _InfoTag extends StatelessWidget {
  final IconData icon;
  final double iconSize;
  final String label;
  final Color? color;

  const _InfoTag({
    required this.icon,
    required this.label,
    this.iconSize = 12,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: c),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: c)),
        ],
      ),
    );
  }
}

/// 区块标题 (带可选的操作链接)
class _HomeSectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _HomeSectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(actionLabel!, style: const TextStyle(fontSize: 12)),
                const Icon(Icons.chevron_right, size: 14),
              ],
            ),
          ),
      ],
    );
  }
}

/// 最近对话卡片
class _RecentTaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;

  const _RecentTaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRunning = task.status == TaskStatus.running;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: AppColors.darkSurfaceHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.darkBorderSubtle),
          ),
          child: Row(
            children: [
              Icon(
                isRunning ? Icons.autorenew : Icons.chat_bubble_outline,
                size: 18,
                color: isRunning
                    ? AppColors.accent
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isRunning ? '进行中' : _timeAgo(task.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: isRunning
                            ? AppColors.accent
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// 快速开始提示词
class _QuickStartItem {
  final IconData icon;
  final String label;
  final String prompt;
  const _QuickStartItem(this.icon, this.label, this.prompt);
}

const _quickStartItems = <_QuickStartItem>[
  _QuickStartItem(Icons.account_tree_outlined, '分析项目结构',
      '请分析这个项目的结构，帮我了解代码架构和主要模块'),
  _QuickStartItem(Icons.bug_report_outlined, '检查已知问题',
      '请检查项目中是否有已知的 bug 或潜在的问题'),
  _QuickStartItem(Icons.lightbulb_outline, '功能建议',
      '基于当前项目，你有什么改进或新功能的建议？'),
  _QuickStartItem(Icons.description_outlined, '生成文档',
      '请帮我生成一份项目 README 文档'),
];

/// 提示词卡片 (2 列网格)
class _PromptCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PromptCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.darkBorderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.accent),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 相对时间格式化
String _timeAgo(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
  if (diff.inHours < 24) return '${diff.inHours}小时前';
  if (diff.inDays < 7) return '${diff.inDays}天前';
  return '${dt.month}/${dt.day}';
}

/// 历史会话抽屉 (左滑出)
class _HistoryDrawer extends ConsumerStatefulWidget {
  final String workspacePath;
  final String? currentTaskId;
  final ValueChanged<String> onSelected;
  final VoidCallback onNewChat;

  const _HistoryDrawer({
    required this.workspacePath,
    required this.currentTaskId,
    required this.onSelected,
    required this.onNewChat,
  });

  @override
  ConsumerState<_HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends ConsumerState<_HistoryDrawer> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showArchived = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildSearchField(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        style: theme.textTheme.bodyMedium,
        cursorColor: theme.colorScheme.primary,
        decoration: InputDecoration(
          hintText: '搜索对话...',
          hintStyle: TextStyle(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
          prefixIcon: Icon(
            Icons.search,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 36,
            minHeight: 36,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  color: theme.colorScheme.onSurfaceVariant,
                  tooltip: '清除',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHigh,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide:
                BorderSide(color: AppColors.accent.withValues(alpha: 0.5)),
          ),
        ),
      ),
    );
  }

  /// 长按会话弹出操作菜单 (归档 / 删除)
  ///
  /// 归档通过 zcode-task.archive/unarchive RPC 调用;
  /// 删除为纯客户端操作 (服务器端删除 RPC 尚不可用)。
  void _showTaskActions(BuildContext context, Task task) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      // surfaceContainerHigh 是半透明白叠加 (设计为叠在实色 bg 上),
      // 单独做弹窗背景会透出底层; 叠到 surfaceContainerLowest(=bg 实色) 上得到不透明等价色。
      backgroundColor: Color.alphaBlend(
        theme.colorScheme.surfaceContainerHigh,
        theme.colorScheme.surfaceContainerLowest,
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 会话标题预览
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  task.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            // 归档 / 取消归档
            ListTile(
              leading: Icon(
                task.archived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              title: Text(task.archived ? '取消归档' : '归档'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleArchive(task);
              },
            ),
            // 删除会话 (危险操作, 红色文字)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('删除会话',
                  style: TextStyle(color: AppColors.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, task);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  /// 切换归档状态 (调用 zcode-task.archive/unarchive RPC, 成功后更新 allTasksProvider)
  Future<void> _toggleArchive(Task task) async {
    try {
      await archiveTask(ref, task);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 删除前确认对话框, 确认后从 allTasksProvider 移除 (纯客户端)
  Future<void> _confirmDelete(BuildContext context, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定要删除「${task.title}」吗?\n此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final tasks = List<Task>.from(ref.read(allTasksProvider));
      tasks.removeWhere((t) => t.id == task.id);
      ref.read(allTasksProvider.notifier).state = tasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allTasks = ref.watch(allTasksProvider);
    final query = _searchQuery.trim().toLowerCase();

    // 根据 _showArchived 过滤任务
    var tasks = allTasks
        .where((t) => t.workspaceKey == widget.workspacePath && t.archived == _showArchived)
        .toList();
    if (query.isNotEmpty) {
      tasks = tasks.where((t) => t.title.toLowerCase().contains(query)).toList();
    }
    tasks.sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.updatedAt?.millisecondsSinceEpoch ?? 0));

    return Drawer(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 头部
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  Text('对话历史',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  // 归档切换按钮
                  GestureDetector(
                    onTap: () => setState(() => _showArchived = !_showArchived),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: _showArchived
                            ? AppColors.accent.withValues(alpha: 0.12)
                            : theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showArchived ? Icons.archive : Icons.archive_outlined,
                            size: 14,
                            color: _showArchived
                                ? AppColors.accent
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showArchived ? '已归档' : '归档',
                            style: TextStyle(
                              fontSize: 12,
                              color: _showArchived
                                  ? AppColors.accent
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 搜索框
            _buildSearchField(theme),
            // 新对话按钮
            ListTile(
              leading: Icon(Icons.add_circle_outline,
                  color: theme.colorScheme.primary, size: 22),
              title: const Text('新对话'),
              onTap: () {
                Navigator.pop(context);
                widget.onNewChat();
              },
            ),
            const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            // 历史列表
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          query.isNotEmpty
                              ? '未找到匹配的对话'
                              : (_showArchived ? '暂无已归档对话' : '暂无历史对话'),
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 13),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final isActive = task.id == widget.currentTaskId;
                        final isDimmed = task.archived;
                        return Opacity(
                          opacity: isDimmed ? 0.5 : 1.0,
                          child: ListTile(
                          selected: isActive,
                          leading: Icon(
                            task.status == TaskStatus.running
                                ? Icons.autorenew
                                : Icons.chat_bubble_outline,
                            size: 18,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text(
                            task.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            widget.onSelected(task.id);
                          },
                          onLongPress: () => _showTaskActions(context, task),
                        ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
