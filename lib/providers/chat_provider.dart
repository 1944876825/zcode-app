import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/relay/relay_client.dart';
import '../core/relay/relay_events.dart';
import '../core/relay/relay_protocol.dart';
import '../data/models/workspace.dart';
import 'app_providers.dart';

// ================================================================
// 对话状态管理 (实测 2026-06-15)
//
// 流程:
// 1. init: 加载历史 (getTaskSnapshot) + 订阅 session 事件
// 2. sendMessage: 入队 (enqueueTaskCommand), 等流式回复
// 3. session.event: tool.updated = AI 正在工作; 文本流 = 追加到 AI 消息
// ================================================================

/// 对话引用 (taskId 可空 = 新会话, workspacePath 必填)
class ChatRef {
  /// 任务 ID。null 表示新会话 (首发消息时调 createSession 创建)。
  final String? taskId;
  final String workspacePath;

  const ChatRef({this.taskId, required this.workspacePath});

  @override
  bool operator ==(Object other) =>
      other is ChatRef && other.taskId == taskId && other.workspacePath == workspacePath;

  @override
  int get hashCode => Object.hash(taskId, workspacePath);
}

/// AI 工具调用活动 (来自 tool.updated 事件)
class ToolActivity {
  final String toolCallId;
  final String toolName;
  final String status; // 'progress' | 'done' | 'error' | ... (payload.kind)
  final int? elapsedMs;

  const ToolActivity({
    required this.toolCallId,
    required this.toolName,
    required this.status,
    this.elapsedMs,
  });

  bool get isRunning =>
      status == 'scheduled' ||
      status == 'started' ||
      status == 'progress' ||
      status == 'running';
}

/// 显示用消息
class DisplayMessage {
  final String id;
  final String role; // 'user' | 'assistant' | 'error'
  final String content;
  final String? thought;
  final String? model;
  final bool isStreaming;
  final DateTime createdAt;
  final List<ToolActivity> activities; // AI 调用的工具 (按到达顺序)

  DisplayMessage({
    required this.id,
    required this.role,
    required this.content,
    this.thought,
    this.model,
    this.isStreaming = false,
    this.activities = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  DisplayMessage copyWith({
    String? content,
    String? thought,
    String? model,
    bool? isStreaming,
    List<ToolActivity>? activities,
  }) {
    return DisplayMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      thought: thought ?? this.thought,
      model: model ?? this.model,
      isStreaming: isStreaming ?? this.isStreaming,
      activities: activities ?? this.activities,
      createdAt: createdAt,
    );
  }
}

/// 对话状态
class ChatState {
  final List<DisplayMessage> messages;
  final bool isLoadingHistory;
  final bool isResponding;
  final String? error;
  final String? activeTurnId; // 当前轮次 (同一次提问共享)

  const ChatState({
    this.messages = const [],
    this.isLoadingHistory = false,
    this.isResponding = false,
    this.error,
    this.activeTurnId,
  });

  ChatState copyWith({
    List<DisplayMessage>? messages,
    bool? isLoadingHistory,
    bool? isResponding,
    String? error,
    String? activeTurnId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      isResponding: isResponding ?? this.isResponding,
      error: error,
      activeTurnId: activeTurnId ?? this.activeTurnId,
    );
  }
}

/// 对话 Notifier
class ChatNotifier extends StateNotifier<ChatState> {
  final RelayClient _relay;
  final ChatRef _ref;
  final void Function(Task task)? _onSessionCreated;
  StreamSubscription<SessionEvent>? _eventSub;
  StreamSubscription<RelayConnectionState>? _stateSub;
  int _msgCounter = 0;

  /// 当前 taskId (新会话时为 null, createSession 后赋值)
  String? _taskId;
  bool _creating = false;  // 正在创建会话

  ChatNotifier(this._relay, this._ref, {this._onSessionCreated})
      : super(const ChatState()) {
    _taskId = _ref.taskId;
    // 已有 taskId: 立即加载历史+订阅; 新会话: 等首发消息
    if (_taskId != null) {
      _init();
    }
    // 监听连接状态: 重连成功后重新订阅
    _stateSub = _relay.onStateChange.listen((state) {
      if (state == RelayConnectionState.ready &&
          _eventSub == null &&
          _taskId != null) {
        _resubscribe();
      }
    });
  }

  String _newMsgId() => 'local_${DateTime.now().millisecondsSinceEpoch}_${_msgCounter++}';

  /// 是否是新会话 (还没创建)
  bool get isNewChat => _taskId == null;

  Future<void> _init() async {
    state = state.copyWith(isLoadingHistory: true);
    try {
      // 订阅 session 事件 (先订阅, 避免错过早期事件)
      final stream = await _relay.subscribeSessionEvents(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
      );
      _eventSub = stream.listen(_onSessionEvent);
      // 加载历史
      await _loadHistory();
    } catch (e) {
      state = state.copyWith(isLoadingHistory: false, error: '加载失败: $e');
    }
  }

  Future<void> _loadHistory() async {
    try {
      final resp = await _relay.getTaskSnapshot(
        taskId: _taskId!,
        workspacePath: _ref.workspacePath,
        messageLimit: 50,
      );
      final snapshot = resp['snapshot'] as Map<String, dynamic>?;
      if (snapshot == null) {
        // notModified (etag 命中), 无需更新
        state = state.copyWith(isLoadingHistory: false);
        return;
      }
      final messagesJson = snapshot['messages'] as List<dynamic>? ?? [];
      final messages = messagesJson
          .map((e) => _displayFromHistory(e as Map<String, dynamic>))
          .toList();
      state = state.copyWith(
        messages: messages,
        isLoadingHistory: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingHistory: false, error: '历史加载失败: $e');
    }
  }

  /// 从历史消息 JSON 构造 DisplayMessage
  DisplayMessage _displayFromHistory(Map<String, dynamic> json) {
    return DisplayMessage(
      id: json['id'] as String? ?? _newMsgId(),
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      thought: json['thought'] as String?,
      model: json['model'] as String?,
      createdAt: json['timestamp'] is int
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : null,
    );
  }

  /// 发送消息
  Future<void> sendMessage(String content) async {
    if (content.trim().isEmpty || state.isResponding) return;

    // 1. 立即显示用户消息
    final userMsg = DisplayMessage(
      id: _newMsgId(),
      role: 'user',
      content: content,
    );
    // 2. 占位 AI 消息 (流式)
    final aiMsg = DisplayMessage(
      id: _newMsgId(),
      role: 'assistant',
      content: '',
      isStreaming: true,
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg, aiMsg],
      isResponding: true,
      error: null,
    );

    try {
      // 3. 新会话: 先 createSession 拿 taskId, 再订阅 + 发消息
      if (_taskId == null) {
        final session = await _relay.createSession(
          workspacePath: _ref.workspacePath,
        );
        _taskId = session['session']?['sessionId'] as String? ??
            session['sessionId'] as String?;
        if (_taskId == null) {
          throw Exception('创建会话失败: 未返回 sessionId');
        }
        // 新会话加入任务列表 (历史抽屉才能显示)
        _onSessionCreated?.call(Task(
          id: _taskId!,
          workspaceKey: _ref.workspacePath,
          title: content,
          status: TaskStatus.running,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
        // 订阅新会话的事件
        final stream = await _relay.subscribeSessionEvents(
          workspacePath: _ref.workspacePath,
          sessionId: _taskId!,
        );
        _eventSub = stream.listen(_onSessionEvent);
      }
      // 4. 入队 (立即返回 accepted, 真正回复走 session 事件)
      await _relay.enqueueTaskCommand(
        taskId: _taskId!,
        workspacePath: _ref.workspacePath,
        content: content,
      );
    } catch (e) {
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != aiMsg.id).toList(),
        isResponding: false,
        error: '发送失败: $e',
      );
    }
  }

  /// 处理 session 事件 (AI 流式回复)
  ///
  /// 实测自 APP 日志 (2026-06-15), 真实事件序列:
  ///   snapshot → state.updated → turn.started → model.streaming(多条)
  ///   → session.updated → turn.completed
  ///
  /// 文本流: kind=model.streaming, payload.delta=增量, payload.done=完成
  void _onSessionEvent(SessionEvent event) {
    // 只处理当前会话的事件 (snapshot/state.updated 的 sid 可能为空, 放行)
    if (event.sessionId.isNotEmpty && event.sessionId != _taskId) return;

    // AI 文本流增量 (model.streaming, payload.kind=text_delta 或默认)
    if (event.isTextDelta) {
      final text = event.delta ?? '';
      if (text.isNotEmpty) {
        _appendAssistantText(text);
      }
      if (event.isDone) {
        _finishAssistantMessage();
      } else {
        state = state.copyWith(isResponding: true, activeTurnId: event.turnId);
      }
      return;
    }

    // AI 思考流增量 (model.streaming, payload.kind=reasoning_delta)
    if (event.isReasoningDelta) {
      final thought = event.delta ?? '';
      if (thought.isNotEmpty) {
        _appendAssistantThought(thought);
      }
      state = state.copyWith(isResponding: true, activeTurnId: event.turnId);
      return;
    }

    // 一轮完成
    if (event.isTurnCompleted) {
      _finishAssistantMessage();
      return;
    }

    // 一轮开始 → AI 正在工作
    // (不再让 state.updated 设 true: turn.completed 之后会来一条 idle 态的
    //  state.updated, 会把已归位的 isResponding 又拉回 true → 永远显示"工作中")
    if (event.isTurnStarted) {
      state = state.copyWith(isResponding: true, activeTurnId: event.turnId);
      return;
    }

    // 工具调用 → 记录到当前 AI 消息 + 标记 AI 正在工作
    if (event.isToolEvent) {
      _recordToolActivity(event);
      if (!state.isResponding) {
        state = state.copyWith(isResponding: true, activeTurnId: event.turnId);
      }
      return;
    }

    // 任务完成
    if (event.isTaskComplete) {
      _finishAssistantMessage();
      return;
    }

    // 任务出错
    if (event.isTaskError) {
      final errorMsg = event.payload['message'] as String? ?? '任务出错';
      _finishAssistantMessageWithError(errorMsg);
      return;
    }
  }

  void _appendAssistantText(String text) {
    final messages = List<DisplayMessage>.from(state.messages);
    if (messages.isNotEmpty && messages.last.role == 'assistant') {
      final last = messages.last;
      messages[messages.length - 1] = last.copyWith(
        content: last.content + text,
      );
      state = state.copyWith(messages: messages, isResponding: true);
    }
  }

  void _appendAssistantThought(String thought) {
    final messages = List<DisplayMessage>.from(state.messages);
    if (messages.isNotEmpty && messages.last.role == 'assistant') {
      final last = messages.last;
      messages[messages.length - 1] = last.copyWith(
        thought: (last.thought ?? '') + thought,
      );
      state = state.copyWith(messages: messages, isResponding: true);
    }
  }

  /// 记录一次工具调用 (tool.updated) 到当前 AI 消息的 activities
  /// 同一 toolCallId 合并更新, 新的追加。
  ///
  /// 实测事件序列: scheduled(toolName,input...) → started(startedAt)
  ///   → result(result, duration)。result 事件不带 toolName, 需沿用前一条。
  void _recordToolActivity(SessionEvent event) {
    final p = event.payload;
    final toolCallId = (p['toolCallId'] as String?) ?? event.toolCallId ?? '';
    if (toolCallId.isEmpty) return;

    final messages = List<DisplayMessage>.from(state.messages);
    if (messages.isEmpty || messages.last.role != 'assistant') return;
    final last = messages.last;
    final activities = List<ToolActivity>.from(last.activities);
    final existing = activities.firstWhere(
      (a) => a.toolCallId == toolCallId,
      orElse: () => const ToolActivity(toolCallId: '', toolName: '', status: ''),
    );
    // result 事件无 toolName → 沿用已记录的; 耗时在 duration
    final toolName = (p['toolName'] as String?) ??
        (existing.toolName.isNotEmpty ? existing.toolName : '工具');
    final status = (p['kind'] as String?) ?? existing.status;
    final duration = (p['duration'] as num?)?.toInt() ??
        (p['elapsedMs'] as num?)?.toInt() ??
        existing.elapsedMs;
    final updated = ToolActivity(
      toolCallId: toolCallId,
      toolName: toolName,
      status: status,
      elapsedMs: duration,
    );
    final idx = activities.indexWhere((a) => a.toolCallId == toolCallId);
    if (idx >= 0) {
      activities[idx] = updated;
    } else {
      activities.add(updated);
    }
    messages[messages.length - 1] = last.copyWith(activities: activities);
    state = state.copyWith(messages: messages, isResponding: true);
  }

  void _finishAssistantMessage() {
    final messages = List<DisplayMessage>.from(state.messages);
    if (messages.isNotEmpty && messages.last.role == 'assistant') {
      final last = messages.last;
      messages[messages.length - 1] = last.copyWith(isStreaming: false);
    }
    state = state.copyWith(messages: messages, isResponding: false);
  }

  void _finishAssistantMessageWithError(String error) {
    final messages = List<DisplayMessage>.from(state.messages);
    if (messages.isNotEmpty && messages.last.role == 'assistant') {
      final last = messages.last;
      messages[messages.length - 1] = last.copyWith(
        isStreaming: false,
        content: last.content.isEmpty ? '⚠️ $error' : last.content,
      );
    }
    state = state.copyWith(messages: messages, isResponding: false);
  }

  /// 手动结束当前 AI 回复 (兜底, 当没有明确 done 事件时)
  void stopResponding() {
    _finishAssistantMessage();
  }

  /// 重新加载历史
  Future<void> reload() async {
    await _loadHistory();
  }

  /// 重连后重新订阅 session 事件
  Future<void> _resubscribe() async {
    try {
      final stream = await _relay.subscribeSessionEvents(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
      );
      _eventSub = stream.listen(_onSessionEvent);
    } catch (_) {
      // 重订阅失败, 下次 ready 再试
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}

/// 对话 Provider (按 taskId+workspacePath 区分)
final chatProvider = StateNotifierProvider.autoDispose
    .family<ChatNotifier, ChatState, ChatRef>((ref, chatRef) {
  final relay = ref.watch(relayClientProvider);
  if (relay == null) {
    // 无 relay client 时返回一个空 notifier (不应发生, UI 应保证已登录)
    throw StateError('RelayClient not available');
  }
  return ChatNotifier(relay, chatRef, onSessionCreated: (task) {
    // 新会话加到 allTasksProvider 头部, 历史抽屉即时显示
    final tasks = List<Task>.from(ref.read(allTasksProvider));
    if (!tasks.any((t) => t.id == task.id)) {
      ref.read(allTasksProvider.notifier).state = [task, ...tasks];
    }
  });
});
