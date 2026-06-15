import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../core/relay/relay_protocol.dart';
import '../../../data/models/workspace.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/chat_provider.dart';
import '../../../shared/theme/app_design_tokens.dart';
import '../../../shared/theme/app_router.dart';
import '../../../shared/widgets/glass_bars.dart';

/// AI 对话页 — 核心交互界面 (实测对接 2026-06-15)
///
/// 数据流: chatProvider(ChatNotifier)
///   - init: 加载历史 (getTaskSnapshot) + 订阅 session 事件
///   - sendMessage: enqueueTaskCommand 入队, AI 回复走 session 事件
///   - session.event: tool.updated = AI 在调工具; 文本流 = 追加到 AI 消息
class ChatScreen extends ConsumerWidget {
  final String workspaceKey;
  final String? taskId;

  const ChatScreen({
    super.key,
    required this.workspaceKey,
    this.taskId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(selectedWorkspaceProvider);
    final title = workspace?.name ?? '对话';

    // taskId 可空: null = 新会话 (首发消息时创建)
    final chatRef = ChatRef(taskId: taskId, workspacePath: workspaceKey);
    final chatState = ref.watch(chatProvider(chatRef));

    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey();

    return Scaffold(
      key: scaffoldKey,
      drawer: _HistoryDrawer(
        workspacePath: workspaceKey,
        currentTaskId: taskId,
        onSelected: (selectedTaskId) {
          // 选了历史会话: 用新 taskId 跳转
          // replace: 原地替换当前 chat 路由, 不叠加新 chat, 保持工作区列表在栈底
          context.replace(
            '${AppRoutes.chat}?workspace=${Uri.encodeComponent(workspaceKey)}'
            '&task=${Uri.encodeComponent(selectedTaskId)}',
          );
        },
        onNewChat: () {
          // 新对话: 跳回不带 task 的聊天页 (replace: 原地替换, 保持返回栈)
          context.replace(
            '${AppRoutes.chat}?workspace=${Uri.encodeComponent(workspaceKey)}',
          );
        },
      ),
      body: _ChatScaffold(
        title: title,
        workspacePath: workspaceKey,
        chatRef: chatRef,
        state: chatState,
        onMenuTap: () => scaffoldKey.currentState?.openDrawer(),
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

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 监听状态变化: 历史加载完成时自动滚到底部
  @override
  void didUpdateWidget(covariant _ChatScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 历史加载完成: isLoadingHistory 从 true→false, 且消息数从 0 变多
    if (oldWidget.state.isLoadingHistory &&
        !widget.state.isLoadingHistory &&
        widget.state.messages.length > oldWidget.state.messages.length) {
      _scrollToBottom();
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

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
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
            if (state.isResponding)
              Text(
                'AI 正在工作...',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.menu),  // 汉堡菜单 (打开历史会话抽屉)
          onPressed: widget.onMenuTap,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
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
            final info = switch (connState) {
              RelayConnectionState.reconnecting => (
                Icons.wifi_off, Colors.orange, '正在重连...'
              ),
              RelayConnectionState.connecting ||
              RelayConnectionState.connected => (
                Icons.wifi_find, Colors.orange, '连接中...'
              ),
              RelayConnectionState.error => (
                Icons.cloud_off, Colors.red, '连接断开'
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
          Expanded(
            child: state.isLoadingHistory && state.messages.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : state.messages.isEmpty
                    ? _buildEmpty(theme)
                    : ListView.builder(
                        controller: _scrollController,
                        // 顶部留出 标题栏(56)+状态栏 的空间, 否则首条消息被
                        // extendBodyBehindAppBar 的毛玻璃标题栏遮挡、滚不到顶
                        padding: EdgeInsets.fromLTRB(
                            12,
                            MediaQuery.of(context).padding.top + 56 + AppSpacing.sm,
                            12,
                            AppSpacing.sm),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final msg = state.messages[index];
                          return _MessageBubble(message: msg, theme: theme);
                        },
                      ),
          ),
          _buildInputArea(theme),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 64, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('开始与 AI 对话', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '输入你的需求, AI 将帮你编码',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea(ThemeData theme) {
    return GlassBottomBar(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: '输入消息...',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: widget.state.isResponding ? null : _sendMessage,
              icon: const Icon(Icons.send, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                minimumSize: const Size(AppTouch.min, AppTouch.min),
              ),
            ),
          ],
        ),
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

/// 消息气泡
///
/// 用户: 强调色填充, 右对齐
/// AI: 透明面 + 左侧强调竖条 (开发者工具气质, 非圆胖聊天气泡)
class _MessageBubble extends StatelessWidget {
  final DisplayMessage message;
  final ThemeData theme;

  const _MessageBubble({required this.message, required this.theme});

  @override
  Widget build(BuildContext context) {
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
      // 用户气泡: 强调色填充
      return Align(
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
      );
    }

    // AI 气泡: 硬编码深色 (APP 强制深色模式, 不依赖 theme.brightness 检测)
    const aiBg = Color(0xFF1F2024);        // 深灰面 (比黑底亮一档)
    const aiInk = Color(0xFFE8EAED);       // 高对比近白文字
    const aiInkMuted = Color(0xFF9AA0A6);  // 思考过程次要文字
    const aiCodeBg = Color(0xFF0D0E11);    // 代码块更深的底

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.88),
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
            // 工具调用 (AI 跑 Bash/改文件等)
            if (message.activities.isNotEmpty)
              _ToolsList(
                  activities: message.activities, theme: theme, inkColor: aiInk),
            // 正文 — 硬编码高对比文字
            MarkdownBody(
              data: message.content.isEmpty && message.isStreaming
                  ? '_(思考中...)_'
                  : message.content,
              styleSheet: MarkdownStyleSheet(
                p: const TextStyle(color: aiInk, fontSize: 14, height: 1.6),
                code: const TextStyle(
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
          ],
        ),
      ),
    );
  }
}

/// AI 工具调用列表 (紧凑行: 图标 + 工具名 + 状态 + 耗时)
class _ToolsList extends StatelessWidget {
  final List<ToolActivity> activities;
  final ThemeData theme;
  final Color inkColor;

  const _ToolsList({
    required this.activities,
    required this.theme,
    required this.inkColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: inkColor.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final a in activities)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _ToolRow(activity: a, theme: theme, inkColor: inkColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  final ToolActivity activity;
  final ThemeData theme;
  final Color inkColor;

  const _ToolRow({
    required this.activity,
    required this.theme,
    required this.inkColor,
  });

  @override
  Widget build(BuildContext context) {
    final running = activity.isRunning;
    final statusText = switch (activity.status) {
      'scheduled' => '排队',
      'started' || 'progress' || 'running' => '运行中',
      'result' || 'done' || 'complete' || 'completed' || 'success' => '完成',
      'error' || 'failed' => '出错',
      _ => activity.status,
    };
    final elapsed = activity.elapsedMs != null
        ? ' · ${(activity.elapsedMs! / 1000).toStringAsFixed(1)}s'
        : '';
    final statusColor =
        running ? AppColors.accent : theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(_iconFor(activity.toolName), size: 14, color: statusColor),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            activity.toolName,
            style: TextStyle(fontSize: 12, fontFamily: kMonoFont, color: inkColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$statusText$elapsed',
          style: TextStyle(fontSize: 11, color: statusColor),
        ),
        if (running) ...[
          const SizedBox(width: 4),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        ],
      ],
    );
  }

  IconData _iconFor(String name) {
    final n = name.toLowerCase();
    if (n.contains('bash') ||
        n.contains('shell') ||
        n.contains('terminal') ||
        n.contains('cmd')) {
      return Icons.terminal;
    }
    if (n.contains('edit') ||
        n.contains('write') ||
        n.contains('create') ||
        n.contains('str_replace')) {
      return Icons.edit_note;
    }
    if (n.contains('read') || n.contains('view') || n.contains('cat')) {
      return Icons.description_outlined;
    }
    if (n.contains('search') ||
        n.contains('grep') ||
        n.contains('glob') ||
        n.contains('find')) {
      return Icons.search;
    }
    if (n.contains('web') || n.contains('fetch') || n.contains('curl')) {
      return Icons.language;
    }
    if (n.contains('todo') || n.contains('task')) {
      return Icons.checklist;
    }
    return Icons.build_outlined;
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

/// 代码块 widget: 顶栏(语言+复制) + 横向滚动代码
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
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: widget.theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.theme.dividerColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: widget.theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(children: [
              if (widget.language != null)
                Text(widget.language!,
                    style: TextStyle(fontSize: 11, fontFamily: 'monospace',
                        color: widget.theme.colorScheme.onSurfaceVariant)),
              const Spacer(),
              InkWell(
                onTap: _copy,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_copied ? Icons.check : Icons.copy, size: 14,
                        color: _copied ? Colors.green : widget.theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(_copied ? '已复制' : '复制',
                        style: TextStyle(fontSize: 11, color: widget.theme.colorScheme.onSurfaceVariant)),
                  ]),
                ),
              ),
            ]),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(widget.code,
                style: TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5,
                    color: widget.theme.colorScheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

/// 历史会话抽屉 (左滑出)
class _HistoryDrawer extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final allTasks = ref.watch(allTasksProvider);
    final tasks = allTasks
        .where((t) => t.workspaceKey == workspacePath)
        .toList()
      ..sort((a, b) => (b.updatedAt?.millisecondsSinceEpoch ?? 0)
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
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
              child: Text('对话历史',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ),
            // 新对话按钮
            ListTile(
              leading: Icon(Icons.add_circle_outline,
                  color: theme.colorScheme.primary, size: 22),
              title: const Text('新对话'),
              onTap: () {
                Navigator.pop(context);
                onNewChat();
              },
            ),
            const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
            // 历史列表
            Expanded(
              child: tasks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text('暂无历史对话',
                            style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontSize: 13)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                      itemCount: tasks.length,
                      itemBuilder: (context, index) {
                        final task = tasks[index];
                        final isActive = task.id == currentTaskId;
                        return ListTile(
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
                            onSelected(task.id);
                          },
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
