import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/relay/relay_client.dart';
import '../core/relay/relay_events.dart';
import '../core/relay/relay_protocol.dart';
import '../core/storage/message_cache.dart';
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
  /// 工具输入参数 (来自 payload.input, 可能含 command/path/query 等)
  final Map<String, dynamic>? input;
  /// 工具执行结果文本 (来自 payload.result 或 payload.output)
  final String? result;

  const ToolActivity({
    required this.toolCallId,
    required this.toolName,
    required this.status,
    this.elapsedMs,
    this.input,
    this.result,
  });

  bool get isRunning =>
      status == 'scheduled' ||
      status == 'started' ||
      status == 'progress' ||
      status == 'running';
}

/// 计划项状态 (host bundle 实测 2026-06-19, todo.status 值)
enum TodoStatus { pending, inProgress, completed }

/// 计划项优先级 (host bundle 实测)
enum TodoPriority { high, medium, low }

/// 计划项 — AI 用 TodoWrite 工具产出的任务清单条目
///
/// wire 字段 (host bundle Zod schema, 规格 §11.3):
///   {content: string, status: "pending"|"in_progress"|"completed", priority: "high"|"medium"|"low"}
/// ⚠️ 字段名是 content 不是 title! 无 id 字段! 有 priority!
/// (之前代码用 title/id 是错的, 已订正)
class PlanItem {
  final String content;
  final TodoStatus status;
  final TodoPriority priority;

  const PlanItem({
    required this.content,
    this.status = TodoStatus.pending,
    this.priority = TodoPriority.medium,
  });

  /// 从单个 todo JSON 解析 (wire 字段名: content/status/priority)
  factory PlanItem.fromJson(Map<String, dynamic> json) {
    final s = json['status'] as String? ?? 'pending';
    // 兼容旧 title 字段 (历史快照可能有)
    final text = json['content'] as String? ?? json['title'] as String? ?? '';
    return PlanItem(
      content: text,
      status: switch (s) {
        'completed' => TodoStatus.completed,
        'in_progress' || 'inProgress' => TodoStatus.inProgress,
        _ => TodoStatus.pending,
      },
      priority: switch (json['priority'] as String?) {
        'high' => TodoPriority.high,
        'low' => TodoPriority.low,
        _ => TodoPriority.medium,
      },
    );
  }

  /// 兼容旧代码的 title getter
  String get title => content;
}

/// 权限选项 (host bundle 实测 2026-06-19, 规格 §11.2.3)
///
/// wire: {optionId, kind, name, description?, response:{decision, reason?}}
class PermissionOption {
  final String optionId;
  final String kind;
  final String name;
  final String? description;
  final String decision; // "allow" | "deny" | "escalate" | "modify"
  final Map<String, dynamic> fullResponse; // 完整 response (含 reason, permissionUpdates)

  const PermissionOption({
    required this.optionId,
    required this.kind,
    required this.name,
    this.description,
    this.decision = 'allow',
    this.fullResponse = const {},
  });

  factory PermissionOption.fromJson(Map<String, dynamic> json) {
    final response = json['response'] as Map<String, dynamic>?;
    return PermissionOption(
      optionId: json['optionId'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      name: json['name'] as String? ?? json['kind'] as String? ?? '',
      description: json['description'] as String?,
      decision: response?['decision'] as String? ?? 'allow',
      // ★ 网页端发完整 response (含 reason, permissionUpdates), 不能只发 decision!
      fullResponse: response ?? {},
    );
  }
}

/// 待确认的工具调用权限 (build/plan 模式下, AI 改文件/跑命令前请求批准)
///
/// wire 实测自 host bundle Zod schema (规格 §11.2.6):
///   {requestId, toolCallId, toolName, reason, riskLevel, input?, options[], requestedAt}
/// ★ options 是结构化的 PermissionOption[], 每个 option 自带 decision!
/// ★ 权限响应用 enqueueTaskCommand(type: respond_permission) + optionId, 不是文本回灌!
class PendingPermission {
  final String id; // = requestId (permissionRequestId)
  final String toolCallId;
  final String toolName;
  final String reason;
  final String riskLevel; // "low" | "medium" | "high" | "critical"
  final String traceId; // ★ permission 自己的 traceId (网页端用它做 runId 发 respond_permission)
  final Map<String, dynamic> input;
  final List<PermissionOption> options;

  const PendingPermission({
    required this.id,
    required this.toolCallId,
    required this.toolName,
    this.reason = '',
    this.riskLevel = 'medium',
    this.traceId = '',
    this.input = const {},
    this.options = const [],
  });

  factory PendingPermission.fromJson(Map<String, dynamic> json) {
    final optsRaw = json['options'] as List<dynamic>? ?? [];
    final requestId = json['requestId'] as String? ??
        json['permissionRequestId'] as String? ?? '';
    return PendingPermission(
      id: requestId,
      toolCallId: json['toolCallId'] as String? ??
          (json['raw'] is Map ? (json['raw'] as Map)['toolCallId'] as String? : null) ?? '',
      toolName: json['toolName'] as String? ??
          json['kind'] as String? ?? '',
      reason: json['reason'] as String? ??
          json['description'] as String? ?? '',
      riskLevel: json['riskLevel'] as String? ?? 'medium',
      // ★ traceId 在 runtime.pendingPermissions 顶层, projection 里没有 (用 toolCallId 兜底)
      traceId: json['traceId'] as String? ?? '',
      input: (json['input'] as Map<String, dynamic>?) ??
          (json['raw'] is Map ? (json['raw'] as Map)['input'] as Map<String, dynamic>? : null) ??
          const {},
      options: optsRaw
          .whereType<Map>()
          .map((e) => PermissionOption.fromJson(Map<String, dynamic>.from(e)))
          .where((o) => o.optionId.isNotEmpty)
          .toList(),
    );
  }
}

/// AskUserQuestion 工具的问题选项
class QuestionOption {
  final String label;
  final String description;

  const QuestionOption({required this.label, this.description = ''});
}

/// AskUserQuestion — AI 向用户提问的结构化数据
///
/// 捕获自真实 session 快照 (sample_init_events.json L3885):
/// tool: "AskUserQuestion", state.input.questions[] 每个:
/// {question, header, multiSelect, options[{label, description}]}
class AskUserQuestion {
  final String callId;
  final String question;
  final String header;
  final bool multiSelect;
  final List<QuestionOption> options;

  const AskUserQuestion({
    required this.callId,
    required this.question,
    this.header = '',
    this.multiSelect = false,
    this.options = const [],
  });

  /// 从 tool.updated 事件的 payload 解析
  factory AskUserQuestion.fromPayload(
      String callId, Map<String, dynamic> payload) {
    // payload 可能是 {input:{questions:[...]}} 或直接含 questions
    final input = payload['input'] as Map<String, dynamic>? ?? payload;
    final questions = input['questions'] as List<dynamic>? ?? [];
    if (questions.isEmpty) {
      return AskUserQuestion(callId: callId, question: '');
    }
    final q = questions.first as Map<String, dynamic>;
    final opts = (q['options'] as List<dynamic>? ?? [])
        .map((e) => QuestionOption(
              label: (e as Map<String, dynamic>)['label'] as String? ?? '',
              description:
                  (e)['description'] as String? ?? '',
            ))
        .where((o) => o.label.isNotEmpty)
        .toList();
    return AskUserQuestion(
      callId: callId,
      question: q['question'] as String? ?? '',
      header: q['header'] as String? ?? '',
      multiSelect: q['multiSelect'] as bool? ?? false,
      options: opts,
    );
  }
}

/// 消息内容的按序片段 — 匹配 web 客户端 parts[] 的逐项渲染。
///
/// 快照数据里 assistant 消息带 parts[] 数组, 每个元素按到达顺序描述一段
/// 内容 (正文 / 思考 / 工具调用)。旧代码把它们拍平到 content/thought/
/// activities 三个独立字段, 渲染时固定顺序 (思考→正文→工具卡)。
///
/// 为了和 web 客户端一致 (思考、正文、工具卡按真实发生顺序交错展示),
/// 这里把 parts[] 原样保留为 [MessagePart] 列表, UI 据此按序渲染。
sealed class MessagePart {
  const MessagePart();
}

/// 正文文本片段 (web part type: "text" / "content")
class TextPart extends MessagePart {
  final String text;
  const TextPart(this.text);
}

/// 思考过程片段 (web part type: "reasoning" / "thought")
class ThoughtPart extends MessagePart {
  final String text;
  const ThoughtPart(this.text);
}

/// 工具调用片段 (web part type: "tool" / "tool-call")
class ToolPart extends MessagePart {
  final ToolActivity activity;
  const ToolPart(this.activity);
}

/// 步骤分隔片段 (web part type: "step-start" / "step-finish")
/// 多步骤回复的边界标记, UI 渲染为细分隔线
class StepPart extends MessagePart {
  final bool isStart; // true=step-start, false=step-finish
  const StepPart(this.isStart);
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
  /// 按序片段 (匹配 web 客户端 parts[])。非空时 UI 据此交错渲染,
  /// 否则回退到旧的 content/thought/activities 固定顺序渲染。
  final List<MessagePart> parts;

  DisplayMessage({
    required this.id,
    required this.role,
    required this.content,
    this.thought,
    this.model,
    this.isStreaming = false,
    this.activities = const [],
    this.parts = const [],
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  DisplayMessage copyWith({
    String? content,
    String? thought,
    String? model,
    bool? isStreaming,
    List<ToolActivity>? activities,
    List<MessagePart>? parts,
  }) {
    return DisplayMessage(
      id: id,
      role: role,
      content: content ?? this.content,
      thought: thought ?? this.thought,
      model: model ?? this.model,
      isStreaming: isStreaming ?? this.isStreaming,
      activities: activities ?? this.activities,
      parts: parts ?? this.parts,
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
  // 代理模式: 'build'(确认) | 'yolo'(自动)。
  // 协议实测 (规格 §5.5): 只有这两种。新会话走 createSession.mode;
  // 已有会话可热切换 (zcode-session.setMode)。
  final String mode;
  /// 思考级别: 'max' | 'medium' | 'nothink'
  final String thoughtLevel;
  /// 当前会话的模型 ID (形如 providerId/slug), 来自 snapshot; null=未知。
  /// 供 UI 模型选择器显示真实模型名。
  final String? model;
  /// AI 向用户提问 (AskUserQuestion 工具), 需要用户选择后继续
  final AskUserQuestion? pendingQuestion;
  /// Token 用量 (累计 input/output; AI 回复完成后刷新, 累积保留)
  final ({int input, int output})? tokenUsage;
  /// 当前会话标题 (来自 snapshot.meta.title; 供 UI 顶栏/历史抽屉显示)。
  /// null = 新会话尚未加载历史, UI 可回退到 task.title。
  final String? sessionTitle;
  /// AI 计划清单 (来自 snapshot.runtime.plan[], TodoWrite 工具产出)。
  /// 空列表 = 无计划。随 session 事件实时更新 (pending→in_progress→completed)。
  final List<PlanItem> plan;
  /// 待确认的工具调用 (build 模式下, runtime.pendingPermissions[])。
  /// 非空时 UI 弹确认卡, 用户批准/拒绝后清空对应项。
  final List<PendingPermission> pendingPermissions;
  /// 客户端子态: "计划模式" UI 选项的本地标记。
  /// wire 上 mode 仍为 'build' (后端只认 build/yolo), 仅用于 UI 区分与提示。
  final bool isPlanMode;
  /// AI 提议的计划 (ExitPlanMode 工具触发), 非空时 UI 弹批准/拒绝卡。
  /// 内容用最近 assistant 消息文本兜底 (plan 原文 wire 上 inputOmitted)。
  final String? pendingPlan;

  const ChatState({
    this.messages = const [],
    this.isLoadingHistory = false,
    this.isResponding = false,
    this.error,
    this.activeTurnId,
    this.mode = 'build',
    this.thoughtLevel = 'max',
    this.model,
    this.pendingQuestion,
    this.tokenUsage,
    this.sessionTitle,
    this.plan = const [],
    this.pendingPermissions = const [],
    this.isPlanMode = false,
    this.pendingPlan,
  });

  ChatState copyWith({
    List<DisplayMessage>? messages,
    bool? isLoadingHistory,
    bool? isResponding,
    String? error,
    String? activeTurnId,
    String? mode,
    String? thoughtLevel,
    String? model,
    AskUserQuestion? pendingQuestion,
    ({int input, int output})? tokenUsage,
    String? sessionTitle,
    List<PlanItem>? plan,
    List<PendingPermission>? pendingPermissions,
    bool? isPlanMode,
    Object? pendingPlan,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      isResponding: isResponding ?? this.isResponding,
      error: error,
      activeTurnId: activeTurnId ?? this.activeTurnId,
      mode: mode ?? this.mode,
      thoughtLevel: thoughtLevel ?? this.thoughtLevel,
      model: model ?? this.model,
      pendingQuestion: pendingQuestion ?? this.pendingQuestion,
      tokenUsage: tokenUsage ?? this.tokenUsage,
      sessionTitle: sessionTitle ?? this.sessionTitle,
      // List 字段直接赋值 (允许传空列表清空, 不用 ?? 保留旧值)
      plan: plan ?? this.plan,
      pendingPermissions: pendingPermissions ?? this.pendingPermissions,
      isPlanMode: isPlanMode ?? this.isPlanMode,
      // pendingPlan: sentinel 区分"不传"(保留旧值) 和"传null"(清空)
      pendingPlan: identical(pendingPlan, _clearPendingPlan)
          ? null
          : (pendingPlan is String
              ? pendingPlan
              : this.pendingPlan),
    );
  }
}

/// sentinel: copyWith 传此对象表示"清空 pendingPlan"
const _clearPendingPlan = Object();

/// 对话 Notifier
class ChatNotifier extends StateNotifier<ChatState> {
  final RelayClient _relay;
  final ChatRef _ref;
  final void Function(Task task)? _onSessionCreated;
  /// 会话标题从服务端更新时回调 (taskId, newTitle) → 更新 allTasksProvider。
  /// 触发点: _loadHistory 解析 snapshot.meta.title 后发现与本地不同。
  final void Function(String taskId, String newTitle)? _onTitleUpdated;
  final String? Function() _preferredModelReader;
  final void Function(String?) _preferredModelSetter;
  final void Function(Set<String>) _mergeDiscovered;
  StreamSubscription<SessionEvent>? _eventSub;
  StreamSubscription<bool>? _rpcReadySub;
  int _msgCounter = 0;

  /// 当前 taskId (新会话时为 null, createSession 后赋值)
  String? _taskId;
  bool _creating = false; // 正在创建会话 (防并发 createSession)
  bool _initDone = false; // _init 完成 (避免重订阅死循环)

  ChatNotifier(
    this._relay,
    this._ref, {
    required String? Function() preferredModelReader,
    required void Function(String?) preferredModelSetter,
    required void Function(Set<String>) mergeDiscovered,
    this._onSessionCreated,
    this._onTitleUpdated,
  })  : _preferredModelReader = preferredModelReader,
        _preferredModelSetter = preferredModelSetter,
        _mergeDiscovered = mergeDiscovered,
        super(const ChatState()) {
    _taskId = _ref.taskId;
    // 已有 taskId: 立即加载历史+订阅; 新会话: 等首发消息
    if (_taskId != null) {
      _init();
    }
    // 监听 RPC ready 变化: bridge degraded → reopen 后重新订阅。
    // 加标志位避免初始化期间触发 (会死循环)。
    _rpcReadySub = _relay.onRpcReadyChange.listen((ready) {
      if (ready && _taskId != null && !state.isResponding && _initDone) {
        debugPrint('[Chat] RPC ready (reconnect), re-subscribing...');
        _eventSub?.cancel();
        _eventSub = null;
        _resubscribe();
      }
    });
  }

  String _newMsgId() => 'local_${DateTime.now().millisecondsSinceEpoch}_${_msgCounter++}';

  /// 是否是新会话 (还没创建)
  bool get isNewChat => _taskId == null;

  /// 切换代理模式
  /// - 新会话 (_taskId==null): 仅更新本地 state, 首发消息 createSession 时带上
  /// - 已有会话: 调 zcode-session.setMode 热切换 (规格 §5.5)
  ///
  /// wire mode 实测有三种 (抓包 settings.mode.options):
  ///   build — 默认, 改文件前确认
  ///   plan  — 只读/规划, 不改 workspace (对应 UI "计划模式")
  ///   yolo  — 自动执行, 无确认
  Future<void> setMode(String mode) async {
    // wire 实测 (host bundle 2026-06-19, 规格 §11.1):
    // 5 种 mode: plan/build/edit/yolo/auto
    const valid = {'build', 'edit', 'yolo', 'plan', 'auto'};
    if (!valid.contains(mode)) return;
    if (mode == state.mode) return;
    final prev = state.mode;
    state = state.copyWith(mode: mode); // 乐观更新
    debugPrint('[Chat] 执行模式切换: req=$mode prev=$prev taskId=$_taskId');
    if (_taskId == null) return; // 新会话: 本地即可
    try {
      final resp = await _relay.setSessionMode(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
        mode: mode,
      );
      debugPrint('[Chat] 执行模式切换: OK resp=$resp');
    } catch (e, st) {
      debugPrint('[Chat] 执行模式切换: FAIL $e\n$st');
      state = state.copyWith(mode: prev, error: '模式切换失败: $e');
    }
  }

  /// 切换思考级别 — zcode-session.setThoughtLevel
  Future<void> setThoughtLevel(String level) async {
    if (level != 'max' && level != 'medium' && level != 'nothink') return;
    if (level == state.thoughtLevel) return;
    final prev = state.thoughtLevel;
    state = state.copyWith(thoughtLevel: level); // 乐观更新
    if (_taskId == null) return; // 新会话: 本地即可
    try {
      await _relay.setSessionThoughtLevel(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
        thoughtLevel: level,
      );
    } catch (e) {
      state = state.copyWith(thoughtLevel: prev, error: '思考级别切换失败: $e');
    }
  }

  /// 压缩对话 (/compact) — zcode-session.compact, 完成后重载历史
  Future<void> compact() async {
    if (_taskId == null) {
      state = state.copyWith(error: '新会话无需压缩');
      return;
    }
    state = state.copyWith(isResponding: true, error: null);
    try {
      await _relay.compactSession(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
      );
      await _loadHistory();
    } catch (e) {
      state = state.copyWith(isResponding: false, error: '压缩失败: $e');
    }
  }

  /// 深度遍历 JSON, 收集 `<uuid>/<slug>` 形式字符串 (模型 ID)
  void _collectModelIds(Object? node, Set<String> out) {
    final uuidSlug = RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/.+$');
    if (node is String) {
      if (uuidSlug.hasMatch(node)) out.add(node);
    } else if (node is Map) {
      for (final v in node.values) {
        _collectModelIds(v, out);
      }
    } else if (node is List) {
      for (final v in node) {
        _collectModelIds(v, out);
      }
    }
  }

  /// 从 snapshot / session 事件 payload 抽取 runtime 计划与待确认权限。
  ///
  /// runtime 结构 (实测 sample_init_events.json L1742-1796):
  ///   payload.runtime.plan[]          — 扁平 todo 列表 (id/status/title)
  ///   payload.runtime.todoGroups[]    — 分组 todo (取第一个非空组的 todos)
  ///   payload.runtime.pendingPermissions[] — build 模式下的工具确认队列
  ///
  /// 优先 plan[], 为空则回退 todoGroups[0].todos[] (移动端常只暴露其一)。
  /// payload 本身可能就是 runtime 对象 (state.updated 等增量事件), 兼容处理。
  ({List<PlanItem> plan, List<PendingPermission> permissions}) _extractRuntime(
      Map<String, dynamic> payload) {
    // snapshot 实测结构 (sub-keys: protocol, session, settings, projection,
    // runtime, messages, todos, todoGroups, slashCommands):
    //   - runtime.plan[]           扁平 todo (TodoWrite 产出)
    //   - runtime.pendingPermissions[]
    //   - todos[] / todoGroups[]   ★ 顶层也有, 且常是数据实际所在
    // 不同事件类型位置不同, 全部聚合扫描。
    final snap = payload['snapshot'] as Map<String, dynamic>?;
    final runtime = (payload['runtime'] as Map<String, dynamic>?) ??
        (snap?['runtime'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    // ── plan: 聚合所有可能来源 (runtime.plan / 顶层 todos / 顶层 todoGroups) ──
    final plan = <PlanItem>[];
    // 1. runtime.plan[]
    for (final src in <List<dynamic>?>[
      runtime['plan'] as List<dynamic>?,
      snap?['plan'] as List<dynamic>?,
      snap?['todos'] as List<dynamic>?,
      payload['todos'] as List<dynamic>?,
    ]) {
      if (src == null || src.isEmpty) continue;
      for (final e in src) {
        if (e is! Map) continue;
        final item = PlanItem.fromJson(Map<String, dynamic>.from(e));
        if (item.title.isNotEmpty && plan.every((p) => p.content != item.content)) {
          plan.add(item);
        }
      }
      if (plan.isNotEmpty) break; // 扁平源取到就够
    }
    // 2. 回退: todoGroups[0].todos[]
    if (plan.isEmpty) {
      for (final groupsSrc in <List<dynamic>?>[
        runtime['todoGroups'] as List<dynamic>?,
        snap?['todoGroups'] as List<dynamic>?,
        payload['todoGroups'] as List<dynamic>?,
      ]) {
        if (groupsSrc == null || groupsSrc.isEmpty) continue;
        for (final g in groupsSrc) {
          if (g is! Map) continue;
          final todos = g['todos'] as List<dynamic>? ?? [];
          if (todos.isEmpty) continue;
          for (final e in todos) {
            if (e is! Map) continue;
            final item = PlanItem.fromJson(Map<String, dynamic>.from(e));
            if (item.title.isNotEmpty) plan.add(item);
          }
          if (plan.isNotEmpty) break;
        }
        if (plan.isNotEmpty) break;
      }
    }

    // ── permissions: projection.pendingPermissions[] (网页端实测位置!) ──
    // 网页端代码: e.projection.pendingPermissions.filter(e=>!nm(e.toolName))
    // ★ pendingPermissions 在 projection 里, 不在 runtime!
    // 兼容检查所有可能的位置。
    final projection = (payload['projection'] as Map<String, dynamic>?) ??
        (snap?['projection'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final perms = <PendingPermission>[];
    for (final src in <List<dynamic>?>[
      projection['pendingPermissions'] as List<dynamic>?,
      runtime['pendingPermissions'] as List<dynamic>?,
      snap?['pendingPermissions'] as List<dynamic>?,
      payload['pendingPermissions'] as List<dynamic>?,
    ]) {
      if (src == null || src.isEmpty) continue;
      for (final e in src) {
        if (e is! Map) continue;
        final p = PendingPermission.fromJson(Map<String, dynamic>.from(e));
        // 网页端过滤: !nm(toolName) — nm 检查 toolName==="AskUserQuestion"
        // AskUserQuestion 走 elicitation UI, 不走 permission 卡
        if (p.toolName.isNotEmpty && p.toolName != 'AskUserQuestion') {
          perms.add(p);
        }
      }
      if (perms.isNotEmpty) break;
    }

    return (plan: plan, permissions: perms);
  }

  /// 切换模型 — 更新全局偏好 (preferredModelProvider); 已有会话则热切换。
  /// 失败不回滚偏好 (它是用户 UI 意图, 非会话事实), 只显示瞬态 error。
  Future<void> setModel(String modelId) async {
    final cur = _preferredModelReader();
    debugPrint('[Chat] 模型切换: req=$modelId cur=$cur taskId=$_taskId');
    if (modelId == cur) return;
    _preferredModelSetter(modelId); // 全局偏好
    if (_taskId == null) return; // 新会话: 发消息时 createSession 后再 setModel
    try {
      await _relay.setSessionModel(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
        model: modelId,
      );
      debugPrint('[Chat] 模型切换: OK $modelId');
    } catch (e) {
      debugPrint('[Chat] 模型切换: FAIL $e');
      state = state.copyWith(error: '模型切换失败: $e');
    }
  }

  Future<void> _init() async {
    state = state.copyWith(isLoadingHistory: true);
    // 先尝试从本地缓存恢复显示
    if (_taskId != null) {
      try {
        final cached = MessageCache.loadMessages(_taskId!);
        if (cached.isNotEmpty && state.messages.isEmpty) {
          state = state.copyWith(messages: cached);
        }
      } catch (_) {}
    }
    try {
      // 重新开 bridge (带 taskId)，确保连接新鲜并绑定到当前 session
      debugPrint('[Chat] _init: opening bridge with taskId=$_taskId...');
      try {
        await _relay.openWorkspaceBridge(_ref.workspacePath, taskId: _taskId);
        debugPrint('[Chat] _init: bridge opened ✓');
      } catch (e) {
        debugPrint('[Chat] _init: bridge open error: $e, trying waitRpcReady...');
        await _relay.waitRpcReady(const Duration(seconds: 10));
      }

      // subscribe
      debugPrint('[Chat] _init: subscribing...');
      final stream = await _relay.subscribeSessionEvents(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
      );
      _eventSub = stream.listen(_onSessionEvent);
      debugPrint('[Chat] _init: subscribed ✓');

      // 趁 bridge 新鲜, 立即拉历史
      await _loadHistory();
      debugPrint('[Chat] _init: done (messages: ${state.messages.length})');
      _initDone = true;
    } catch (e, st) {
      debugPrint('[Chat] _init: FAILED: $e\n$st');
      state = state.copyWith(isLoadingHistory: false, error: '加载失败: $e');
      _initDone = true;
    }
  }

  Future<void> _loadHistory() async {
    try {
      final resp = await _relay.getTaskSnapshot(
        taskId: _taskId!,
        workspacePath: _ref.workspacePath,
        messageLimit: 50,
      );
      debugPrint('[Chat] _loadHistory: resp keys=${resp.keys.toList()}');
      final snapshot = resp['snapshot'] as Map<String, dynamic>?;
      if (snapshot == null) {
        state = state.copyWith(isLoadingHistory: false);
        return;
      }
      final messagesJson = snapshot['messages'] as List<dynamic>? ?? [];
      debugPrint('[Chat] _loadHistory: ${messagesJson.length} messages');
      final messages = messagesJson
          .map((e) => _displayFromHistory(e as Map<String, dynamic>))
          .toList();
      // 调试: 统计有 activities 的消息数
      final withActivities = messages.where((m) => m.activities.isNotEmpty).length;
      final withContent = messages.where((m) => m.content.isNotEmpty).length;
      debugPrint('[Chat] _loadHistory: parsed ${messages.length} msgs, '
          'withContent=$withContent withActivities=$withActivities');
      // 列出前几条消息概况
      for (var i = 0; i < messages.length && i < 5; i++) {
        final m = messages[i];
        debugPrint('[Chat]   msg[$i] role=${m.role} content=${m.content.length}ch '
            'activities=${m.activities.length} thought=${m.thought?.length ?? 0}ch');
      }
      // 抽取 runtime 计划/权限 (与 messages 同级, snapshot.runtime)
      final rt = _extractRuntime(snapshot);
      state = state.copyWith(
        messages: messages,
        isLoadingHistory: false,
        plan: rt.plan,
        pendingPermissions: rt.permissions,
      );
      try {
        await MessageCache.saveMessages(_taskId!, messages);
      } catch (_) {}
      final found = <String>{};
      _collectModelIds(snapshot, found);
      if (found.isNotEmpty) _mergeDiscovered(found);
      final meta = snapshot['meta'] as Map<String, dynamic>?;
      final remoteTitle = meta?['title'] as String?;
      final remoteModel = meta?['model'] as String?;
      if ((remoteTitle != null && remoteTitle.isNotEmpty &&
              remoteTitle != state.sessionTitle) ||
          (remoteModel != null && remoteModel != state.model)) {
        state = state.copyWith(
          sessionTitle: (remoteTitle != null && remoteTitle.isNotEmpty)
              ? remoteTitle
              : state.sessionTitle,
          model: remoteModel ?? state.model,
        );
        if (remoteTitle != null &&
            remoteTitle.isNotEmpty &&
            remoteTitle != state.sessionTitle &&
            _taskId != null) {
          _onTitleUpdated?.call(_taskId!, remoteTitle);
        }
      }
    } catch (e) {
      debugPrint('[Chat] _loadHistory: FAILED: $e');
      state = state.copyWith(isLoadingHistory: false, error: '历史加载失败: $e');
    }
  }

  /// 轻量刷新 runtime (plan/todos/pendingPermissions)。
  ///
  /// 实测: session.updated 事件只携带遥测数据 (URL/headers/usage),
  /// 不含 plan 字段。plan/todo 数据只在主动 RPC 调用的响应里:
  ///   - readSession (轻量, 网页端反复调用, 见抓包 seq=27/34)
  ///   - getTaskSnapshotWithEtag (重量, _loadHistory 用)
  /// AI 每轮完成后调 readSession 拉最新 plan, 让 UI 及时反映 TodoWrite 进度。
  Future<void> _refreshRuntime() async {
    if (_taskId == null) return;
    try {
      final resp = await _relay.readSession(
        sessionId: _taskId!,
        workspacePath: _ref.workspacePath,
        messageLimit: 1, // 只要 runtime, 不要消息
      );
      // readSession 响应顶层就是 snapshot 结构 (runtime/todos/todoGroups 平级)
      debugPrint('[Chat] _refreshRuntime: resp.keys=${resp.keys.toList()}');
      final snap = resp['snapshot'] as Map<String, dynamic>?;
      debugPrint('[Chat] _refreshRuntime: snap?.keys=${snap?.keys.toList()}');
      final runtime2 = resp['runtime'] as Map<String, dynamic>?;
      debugPrint('[Chat] _refreshRuntime: runtime?.keys=${runtime2?.keys.toList()}');
      // dump todos/todoGroups/plan wherever they are
      for (final key in ['todos', 'todoGroups', 'plan']) {
        final v = resp[key] ?? snap?[key] ?? runtime2?[key];
        if (v != null) {
          debugPrint('[Chat] _refreshRuntime: $key = ${v.toString().substring(0, v.toString().length > 300 ? 300 : v.toString().length)}');
        }
      }
      final rt = _extractRuntime(resp);
      debugPrint(
          '[Chat] _refreshRuntime: plan=${rt.plan.length} perm=${rt.permissions.length}');
      // 仅当确实变化才更新 (避免无谓 rebuild)
      if (rt.plan.length != state.plan.length ||
          rt.permissions.length != state.pendingPermissions.length ||
          _planChanged(state.plan, rt.plan)) {
        state = state.copyWith(
          plan: rt.plan,
          pendingPermissions: rt.permissions,
        );
      }
    } catch (e) {
      debugPrint('[Chat] _refreshRuntime: FAILED: $e');
    }
  }

  /// 判断 plan 列表是否有实质变化 (id/status/title)
  bool _planChanged(List<PlanItem> a, List<PlanItem> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].content != b[i].content ||
          a[i].status != b[i].status ||
          a[i].priority != b[i].priority) {
        return true;
      }
    }
    return false;
  }

  /// 从历史消息 JSON 构造 DisplayMessage
  DisplayMessage _displayFromHistory(Map<String, dynamic> json) {
    // ── 实测两种 wire 格式 (probe_read_plan 确认) ──
    //
    // 格式 A — readSession / snapshot 事件 (完整格式):
    //   { info: { role, model, time }, parts: [
    //     { type: "text", text },
    //     { type: "reasoning", text },
    //     { type: "tool", tool, callId, state: { status, input: { plan }, output } },
    //     { type: "step-start" }, { type: "step-finish" }
    //   ]}
    //
    // 格式 B — getTaskSnapshotWithEtag (精简格式):
    //   { id, role, content, thought, model, timestamp, turnIndex,
    //     tools: [{ toolName, kind, status, input: { plan }, output, raw: { toolCallId } }],
    //     parts: [{ type: "thought"|"content"|"tool-call", content?, toolIndex? }]
    //   }
    //
    // 格式 C — 旧格式 (无 parts, 直接 content/role)

    final info = json['info'] as Map<String, dynamic>?;
    final parts = json['parts'] as List<dynamic>?;
    final tools = json['tools'] as List<dynamic>?; // 精简格式的工具数组

    final role = info?['role'] as String? ?? json['role'] as String? ?? 'assistant';
    final modelInfo = info?['model'] as Map<String, dynamic>?;
    final modelStr = modelInfo != null
        ? '${modelInfo['providerId'] ?? ''}/${modelInfo['modelId'] ?? ''}'
        : json['model'] as String?;
    final timeCreated = info?['time'] is Map
        ? (info!['time'] as Map)['created'] as int?
        : (json['timestamp'] is int ? json['timestamp'] as int : null);

    final textBuffer = StringBuffer();
    final thoughtBuffer = StringBuffer();
    final activities = <ToolActivity>[];
    // ★ 按序片段 (匹配 web parts[])。UI 非空时据此交错渲染。
    final orderedParts = <MessagePart>[];

    // 预解析 Format B 的 tools[] (供 tool-call 引用, 也作兜底)
    final toolsList = <ToolActivity>[];
    if (tools != null) {
      for (final toolRaw in tools) {
        if (toolRaw is! Map) continue;
        toolsList.add(_toolActivityFromToolsEntry(
            Map<String, dynamic>.from(toolRaw)));
      }
    }

    // ── 解析 parts[] ──
    if (parts != null) {
      for (final part in parts) {
        if (part is! Map) continue;
        final partMap = Map<String, dynamic>.from(part);
        final type = partMap['type'] as String? ?? '';

        switch (type) {
          // 完整格式: text / reasoning
          case 'text':
            final t = partMap['text'] as String? ?? '';
            if (t.isNotEmpty) {
              if (textBuffer.isNotEmpty) textBuffer.write('\n');
              textBuffer.write(t);
              orderedParts.add(TextPart(t));
            }
            break;
          case 'reasoning':
            final t = partMap['text'] as String? ?? '';
            if (t.isNotEmpty) {
              if (thoughtBuffer.isNotEmpty) thoughtBuffer.write('\n');
              thoughtBuffer.write(t);
              orderedParts.add(ThoughtPart(t));
            }
            break;
          // 精简格式别名: thought → reasoning, content → text
          case 'thought':
            final t = partMap['content'] as String? ?? partMap['text'] as String? ?? '';
            if (t.isNotEmpty) {
              if (thoughtBuffer.isNotEmpty) thoughtBuffer.write('\n');
              thoughtBuffer.write(t);
              orderedParts.add(ThoughtPart(t));
            }
            break;
          case 'content':
            final t = partMap['content'] as String? ?? partMap['text'] as String? ?? '';
            if (t.isNotEmpty) {
              if (textBuffer.isNotEmpty) textBuffer.write('\n');
              textBuffer.write(t);
              orderedParts.add(TextPart(t));
            }
            break;
          // 完整格式: tool (含 state.input/output)
          case 'tool':
            final activity = _toolActivityFromToolPart(partMap);
            activities.add(activity);
            orderedParts.add(ToolPart(activity));
            break;
          // 精简格式: tool-call (引用 tools[toolIndex], 实际数据在 tools[])
          case 'tool-call':
            final idx = partMap['toolIndex'];
            if (idx is int && idx >= 0 && idx < toolsList.length) {
              final activity = toolsList[idx];
              activities.add(activity);
              orderedParts.add(ToolPart(activity));
            }
            break;
          // step-start / step-finish: 步骤边界标记
          case 'step-start':
            orderedParts.add(const StepPart(true));
            break;
          case 'step-finish':
            orderedParts.add(const StepPart(false));
            break;
        }
      }
    }

    // ── 精简格式兜底: parts 无 tool activities 时, 从 tools[] 补充 ──
    if (activities.isEmpty && toolsList.isNotEmpty) {
      for (final activity in toolsList) {
        activities.add(activity);
        orderedParts.add(ToolPart(activity));
      }
    }

    // ── 兜底: 如果 parts 没产出 content, 用 json['content'] ──
    var content = textBuffer.toString();
    if (content.isEmpty) {
      content = json['content'] as String? ?? '';
    }
    var thought = thoughtBuffer.isNotEmpty ? thoughtBuffer.toString() : null;
    if (thought == null || thought.isEmpty) {
      thought = json['thought'] as String?;
    }

    return DisplayMessage(
      id: json['messageId'] as String? ?? json['id'] as String? ?? _newMsgId(),
      role: role,
      content: content,
      thought: thought,
      model: modelStr,
      createdAt: timeCreated != null
          ? DateTime.fromMillisecondsSinceEpoch(timeCreated)
          : null,
      activities: activities,
      parts: orderedParts,
    );
  }

  /// 从 Format A 的 "tool" part 构造 ToolActivity (含 state.input/output)。
  /// ★ ExitPlanMode: status=running 时无 output, plan 在 input.plan。
  ToolActivity _toolActivityFromToolPart(Map<String, dynamic> partMap) {
    final toolName = partMap['tool'] as String? ?? '';
    final callId = partMap['callId'] as String? ?? '';
    final state = partMap['state'] as Map<String, dynamic>?;
    final status = state?['status'] as String? ?? '';
    final input = _toStrMap(state?['input']);
    final outputRaw = state?['output'];
    String? resultStr;
    if (outputRaw is String) {
      resultStr = outputRaw;
    } else if (outputRaw is Map) {
      resultStr = _extractPlanFromMap(Map<String, dynamic>.from(outputRaw));
    }
    if (resultStr == null && toolName.toLowerCase() == 'exitplanmode') {
      resultStr = input?['plan'] as String?;
    }
    return ToolActivity(
      toolCallId: callId,
      toolName: toolName,
      status: status,
      input: input,
      result: resultStr,
    );
  }

  /// 从 Format B 的 tools[] 条目构造 ToolActivity
  /// (raw.toolCallId / toolName|kind / status / input / output)。
  ToolActivity _toolActivityFromToolsEntry(Map<String, dynamic> tMap) {
    final toolName = tMap['toolName'] as String? ?? tMap['kind'] as String? ?? '';
    final rawMap = tMap['raw'] is Map
        ? Map<String, dynamic>.from(tMap['raw'] as Map)
        : null;
    final callId = rawMap?['toolCallId'] as String? ?? '';
    final status = tMap['status'] as String? ?? '';
    final input = _toStrMap(tMap['input']);
    final outputRaw = tMap['output'];
    String? resultStr;
    if (outputRaw is String) {
      resultStr = outputRaw;
    } else if (outputRaw is Map) {
      resultStr = _extractPlanFromMap(Map<String, dynamic>.from(outputRaw));
    }
    if (resultStr == null && toolName.toLowerCase() == 'exitplanmode') {
      resultStr = input?['plan'] as String?;
    }
    return ToolActivity(
      toolCallId: callId,
      toolName: toolName,
      status: status,
      input: input,
      result: resultStr,
    );
  }

  /// 安全转换 Map → Map<String, dynamic>
  static Map<String, dynamic>? _toStrMap(dynamic m) {
    if (m == null) return null;
    if (m is Map<String, dynamic>) return m;
    if (m is Map) return Map<String, dynamic>.from(m);
    return null;
  }

  /// 从 Map 提取 plan/text/content 字符串
  static String? _extractPlanFromMap(Map<String, dynamic> m) {
    for (final key in ['plan', 'text', 'content']) {
      final v = m[key];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// 发送消息
  Future<void> sendMessage(String content) async {
    debugPrint(
        '[Chat] sendMessage: "$content" taskId=$_taskId model=${_preferredModelReader()} mode=${state.mode}');
    if (content.trim().isEmpty || state.isResponding || _creating) return;

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
        // createSession 的 model 参数服务器报 Invalid params (格式与文档 §5.5 不符),
        // 改为建会时用工作区默认模型, 建成后立刻 setModel 热切换到用户选的模型。
        _creating = true;
        final desiredModel = _preferredModelReader();
        debugPrint(
            '[Chat] createSession 发起 (默认模型): mode=${state.mode} desired=$desiredModel');
        final session = await _relay.createSession(
          workspacePath: _ref.workspacePath,
          mode: state.mode,
        );
        debugPrint('[Chat] createSession resp keys=${session.keys.toList()}');
        // 响应可能带回模型 → 转发到全局列表 (保留 getAll 未列的 uuid provider)
        final found = <String>{};
        _collectModelIds(session, found);
        if (found.isNotEmpty) _mergeDiscovered(found);
        _taskId = session['session']?['sessionId'] as String? ??
            session['sessionId'] as String?;
        if (_taskId == null) {
          throw Exception('创建会话失败: 未返回 sessionId');
        }
        // 用户选了模型 → 立刻热切换 (新会话默认模型有效, setModel 守卫能过)。
        // 失败不清全局偏好 (它是用户 UI 意图), 回退用工作区默认模型。
        if (desiredModel != null) {
          try {
            await _relay.setSessionModel(
              workspacePath: _ref.workspacePath,
              sessionId: _taskId!,
              model: desiredModel,
            );
            debugPrint('[Chat] 新会话 setModel OK: $desiredModel');
          } catch (e) {
            debugPrint('[Chat] 新会话 setModel 失败, 回退默认模型: $e');
          }
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
      debugPrint('[Chat] 发送失败: $e');
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != aiMsg.id).toList(),
        isResponding: false,
        error: '发送失败: $e',
      );
    } finally {
      _creating = false;
    }
  }

  /// 处理 session 事件 (AI 流式回复)
  ///
  /// 实测自 APP 日志 (2026-06-15), 真实事件序列:
  ///   snapshot → state.updated → turn.started → model.streaming(多条)
  ///   → session.updated → turn.completed
  ///
  /// 文本流: kind=model.streaming, payload.delta=增量, payload.done=完成
  Future<void> _onSessionEvent(SessionEvent event) async {
    // ★ 全量调试日志: 打印每个事件的 kind/type/toolName
    final _toolName = event.payload['toolName'] as String?;
    debugPrint('[Chat] EVT kind=\"${event.kind}\" type=\"${event.type}\" tool=\"$_toolName\" seq=${event.seq} sid=${event.sessionId.substring(0, event.sessionId.length > 12 ? 12 : event.sessionId.length)}');

    // 只处理当前会话的事件 (snapshot/state.updated 的 sid 可能为空, 放行)
    if (event.sessionId.isNotEmpty && event.sessionId != _taskId) return;

    // snapshot 事件 (订阅时一次性全量推送): 抽取模型 → 转发到全局列表。
    // 新会话首发消息 createSession+订阅 后即触发, 保留 getAll 未列的模型。
    if (event.kind == 'snapshot') {
      debugPrint('[Chat] snapshot event: payload keys=${event.payload.keys.toList()}');
      // 尝试从 snapshot 提取消息 (多种可能的数据结构)
      List<dynamic>? rawMessages;
      // 1. event.payload.messages
      rawMessages = event.payload['messages'] as List<dynamic>?;
      // 2. event.payload.snapshot.messages
      if (rawMessages == null) {
        final snapshotData = event.payload['snapshot'] as Map<String, dynamic>?;
        if (snapshotData != null) {
          rawMessages = snapshotData['messages'] as List<dynamic>?;
        }
      }
      // 3. event.payload.session.messages
      if (rawMessages == null) {
        final sessionData = event.payload['session'] as Map<String, dynamic>?;
        if (sessionData != null) {
          rawMessages = sessionData['messages'] as List<dynamic>?;
        }
      }
      debugPrint('[Chat] snapshot: rawMessages count=${rawMessages?.length ?? 0}');

      // 抽取 runtime 计划/权限 (snapshot 事件是全量推送, 权威更新 plan)
      // 诊断: 打印 snapshot 子对象的 keys, 确认 runtime 在哪一层
      final snapObj = event.payload['snapshot'] as Map<String, dynamic>?;
      debugPrint(
          '[Chat] snapshot sub-keys: ${snapObj?.keys.toList()} hasRuntime=${snapObj?.containsKey('runtime')}');
      final rt = _extractRuntime(event.payload);
      // 总是打印 (含空), 便于诊断 runtime 是否被找到
      debugPrint(
          '[Chat] snapshot runtime: plan=${rt.plan.length} permissions=${rt.permissions.length}');
      if (rt.plan.isNotEmpty || rt.permissions.isNotEmpty) {
        state = state.copyWith(
          plan: rt.plan,
          pendingPermissions: rt.permissions,
        );
        debugPrint('[Chat] ★ plan SET in state: ${state.plan.length} items');
      }

      // snapshot 事件的消息格式含 parts[] (含完整 tool activities + ExitPlanMode plan),
      // 比 getTaskSnapshotWithEtag 的精简格式更完整。
      // 只要 snapshot 事件的消息含 parts 就覆盖 (不管 state.messages 是否已有精简数据)。
      if (rawMessages != null && rawMessages.isNotEmpty) {
        // 检查是否是含 parts 的完整格式
        final firstMsg = rawMessages.whereType<Map>().firstOrNull;
        final hasParts = firstMsg != null &&
            (firstMsg as Map).containsKey('parts');
        if (hasParts) {
          final messages = rawMessages
              .whereType<Map>()
              .map((e) => _displayFromHistory(Map<String, dynamic>.from(e)))
              .toList();
          if (messages.isNotEmpty) {
            debugPrint('[Chat] snapshot: loaded ${messages.length} messages from event (parts format, overwriting)');
            state = state.copyWith(
              messages: messages,
              isLoadingHistory: false,
            );
            debugPrint('[Chat] ★ after messages overwrite: plan in state=${state.plan.length}');
            try {
              await MessageCache.saveMessages(_taskId!, messages);
            } catch (_) {}
          }
        } else if (state.messages.isEmpty) {
          // 精简格式, 仅在没有历史时用
          final messages = rawMessages
              .whereType<Map>()
              .map((e) => _displayFromHistory(Map<String, dynamic>.from(e)))
              .toList();
          if (messages.isNotEmpty) {
            debugPrint('[Chat] snapshot: loaded ${messages.length} messages from event (compact format)');
            state = state.copyWith(
              messages: messages,
              isLoadingHistory: false,
            );
            try {
              await MessageCache.saveMessages(_taskId!, messages);
            } catch (_) {}
          }
        }
      }
      
      // 提取标题
      final meta = event.payload['meta'] as Map<String, dynamic>?;
      final sessionInfo = event.payload['session'] as Map<String, dynamic>?;
      final title = meta?['title'] as String? ?? sessionInfo?['title'] as String?;
      if (title != null && title.isNotEmpty && title != state.sessionTitle) {
        state = state.copyWith(sessionTitle: title);
        if (_taskId != null) _onTitleUpdated?.call(_taskId!, title);
      }
      
      final found = <String>{};
      _collectModelIds(event.payload, found);
      if (found.isNotEmpty) _mergeDiscovered(found);
    }

    // state.updated / session.updated — 增量更新 plan。
    // ★ 不碰 pendingPermissions! (网页端实测: permission 由独立的
    // permission.requested/resolved 事件驱动, session.updated 的 projection
    // 在权限等待期间不含 pendingPermissions, 会误清权限卡)
    if (event.kind == 'state.updated' || event.kind == 'session.updated') {
      final rt = _extractRuntime(event.payload);
      if (rt.plan.isNotEmpty) {
        state = state.copyWith(
          plan: rt.plan,
        );
      }
    }

    // ★ permission.requested — AI 请求工具执行权限 (host bundle 实测, 规格 §11.2.4)
    // payload: {requestId, toolCallId, toolName, riskLevel, reason, input, options[]}
    // → 解析 PendingPermission 设到 state, UI 弹确认卡
    if (event.kind == 'permission.requested') {
      final perm = PendingPermission.fromJson(event.payload);
      if (perm.toolName.isNotEmpty) {
        final perms = List<PendingPermission>.from(state.pendingPermissions);
        // 同 toolCallId 的替换, 否则追加
        perms.removeWhere((p) => p.toolCallId == perm.toolCallId);
        perms.add(perm);
        debugPrint('[Chat] ★ permission.requested: ${perm.toolName} risk=${perm.riskLevel} options=${perm.options.length}');
        state = state.copyWith(
          pendingPermissions: perms,
          isResponding: false, // 停止"AI 正在工作", 等待用户确认
        );
      }
      return;
    }

    // ★ permission.resolved — 权限已决定 (用户批准/拒绝, 或超时)
    // payload: {requestId, toolCallId, decision, reason?}
    // → 清除对应的 pendingPermission
    if (event.kind == 'permission.resolved') {
      final toolCallId = event.payload['toolCallId'] as String?;
      final requestId = event.payload['requestId'] as String?;
      final decision = event.payload['decision'] as String?;
      debugPrint('[Chat] permission.resolved: toolCallId=$toolCallId decision=$decision');
      final perms = state.pendingPermissions
          .where((p) =>
              p.toolCallId != toolCallId &&
              p.id != requestId)
          .toList();
      if (perms.length != state.pendingPermissions.length) {
        state = state.copyWith(
          pendingPermissions: perms,
          isResponding: true, // 恢复"AI 正在工作"
        );
      }
      return;
    }

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

    // 一轮完成 → 刷新 plan/todo (session.updated 推送不带 plan 数据,
    // 需主动调 readSession 拉最新 runtime, 见抓包 sample_init_events seq=27/34)
    if (event.isTurnCompleted) {
      _finishAssistantMessage();
      _refreshRuntime();
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
      final toolName = event.toolName ?? '';
      final innerKind = event.payload['kind'] as String? ?? '';
      // ★ 诊断: 每个 tool.updated 的 toolName + innerKind
      if (toolName.toLowerCase().contains('plan') ||
          innerKind == 'started' ||
          innerKind == 'result') {
        debugPrint(
            '[Chat] TOOL-CHECK toolName="$toolName" innerKind="$innerKind" keys=${event.payload.keys.toList()}');
      }

      // ExitPlanMode (网页端逆向 g3e 组件实测 2026-06-20):
      // AI 输出 plan → 调 ExitPlanMode → tool.updated(kind=result, output.plan=markdown)
      //   → permission.requested → 用户选 option → respond_permission
      //
      // ★ ExitPlanMode 的 result 事件含 plan markdown (output.plan/text/content),
      //   需捕获到 ToolActivity.result, UI 渲染为计划卡片。
      //   started 事件 inputOmitted, 跳过。
      // EnterPlanMode 无内容, 直接跳过。
      if (toolName == 'EnterPlanMode') {
        if (!state.isResponding) {
          state = state.copyWith(isResponding: true, activeTurnId: event.turnId);
        }
        return;
      }
      if (toolName == 'ExitPlanMode' ||
          toolName == 'switch_mode' ||
          toolName == 'switchMode') {
        if (innerKind == 'result' || innerKind == 'done' || innerKind == 'completed') {
          // 从 output/input 提取 plan markdown (网页端 gJ/h3e 同款逻辑)
          final planMd = _extractPlanMarkdown(event.payload);
          debugPrint('[Chat] ★ ExitPlanMode result — planMd length=${planMd?.length ?? 0}');
          if (planMd != null && planMd.isNotEmpty) {
            _recordToolActivity(event, planOverride: planMd);
          }
        }
        if (!state.isResponding) {
          state = state.copyWith(isResponding: true, activeTurnId: event.turnId);
        }
        return;
      }

      // AskUserQuestion 特殊处理: AI 向用户提问, 需交互式回答
      if (toolName.toLowerCase().contains('askuser') ||
          toolName == 'AskUserQuestion') {
        _handleAskUserQuestion(event);
        return;
      }

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

  /// 处理 AskUserQuestion 工具事件
  ///
  /// AI 调 AskUserQuestion 时, 事件 payload 含 questions[]。
  /// kind=scheduled/started → 解析问题设到 pendingQuestion (UI 渲染交互卡)。
  /// kind=result/done → 用户已回答 (可能是从网页端回答的), 清除 pending。
  void _handleAskUserQuestion(SessionEvent event) {
    final kind = (event.payload['kind'] as String?) ?? '';
    final callId = event.toolCallId ??
        event.payload['toolCallId'] as String? ??
        event.payload['callId'] as String? ??
        '';

    // 已完成 → 清除待答问题
    if (kind == 'result' || kind == 'done' || kind == 'completed') {
      if (state.pendingQuestion?.callId == callId) {
        state = state.copyWith(pendingQuestion: null);
      }
      return;
    }

    // scheduled/started/running → 解析问题并显示
    final q = AskUserQuestion.fromPayload(callId, event.payload);
    if (q.question.isEmpty) return;
    state = state.copyWith(
      pendingQuestion: q,
      isResponding: false, // 停止"AI 正在工作", 等待用户输入
    );
  }

  /// 用户回答 AskUserQuestion — 把选中的选项作为消息发回
  ///
  /// 发送格式: "{question}"="{answer}" (与捕获的 output 格式一致)
  /// 走 enqueueTaskCommand (type: send_prompt), 服务端将其作为 tool 响应。
  Future<void> answerQuestion(List<String> selectedLabels) async {
    final q = state.pendingQuestion;
    if (q == null || _taskId == null) return;

    // 构造回答文本: 用选中的 label 拼接
    final answer = selectedLabels.join(', ');
    final responseText = '${q.question}=$answer';

    // 清除待答状态
    state = state.copyWith(pendingQuestion: null, isResponding: true);

    try {
      await _relay.enqueueTaskCommand(
        taskId: _taskId!,
        workspacePath: _ref.workspacePath,
        content: responseText,
      );
    } catch (e) {
      state = state.copyWith(
        isResponding: false,
        error: '回答提交失败: $e',
      );
    }
  }

  /// 回答工具权限确认 (build/plan 模式 pendingPermissions)。
  ///
  /// ★ wire 实测 (host bundle 2026-06-19, 规格 §11.2):
  /// 用 enqueueTaskCommand(type: "respond_permission"), 不是文本回灌!
  /// 发送 permissionRequestId + optionId + response.decision。
  ///
  /// [permissionId] = permission.requested 事件的 requestId
  /// [optionId] = 用户选择的 PermissionOption.optionId
  /// [decision] = "allow" | "deny" | "escalate" | "modify"
  Future<void> answerPermission(String permissionId, String optionId, String decision,
      {Map<String, dynamic>? permInput, List<PermissionOption>? permOptions, String? permTraceId}) async {
    debugPrint('[Chat] ★ answerPermission: permId=$permissionId optionId=$optionId decision=$decision');
    debugPrint('[Chat]   _taskId=$_taskId state.pendingPerms=${state.pendingPermissions.length}');

    if (_taskId == null) {
      debugPrint('[Chat] ✗ answerPermission: _taskId is null!');
      return;
    }

    // ★ runId = permission 的 traceId (网页端行为, 不是 turnId/taskId!)
    final runId = permTraceId ?? state.activeTurnId ?? _taskId!;
    debugPrint('[Chat]   runId(permTraceId)=$runId');

    // ★ 从传入的 permOptions 取完整 response (不依赖 state — permission 可能已被清)
    Map<String, dynamic> fullResponse = {'decision': decision};
    if (permOptions != null) {
      final opt = permOptions.where((o) => o.optionId == optionId).firstOrNull;
      if (opt != null && opt.fullResponse.isNotEmpty) {
        fullResponse = opt.fullResponse;
      }
      debugPrint('[Chat]   option found: ${opt != null}');
    } else {
      // 兜底: 从 state 找
      final p = state.pendingPermissions.where((x) => x.id == permissionId).firstOrNull;
      final opt = p?.options.where((o) => o.optionId == optionId).firstOrNull;
      if (opt != null && opt.fullResponse.isNotEmpty) {
        fullResponse = opt.fullResponse;
      }
    }
    debugPrint('[Chat]   fullResponse=$fullResponse');

    // 本地立即移除该项 (避免重复确认), 恢复 isResponding
    state = state.copyWith(
      pendingPermissions: state.pendingPermissions.where((x) => x.id != permissionId).toList(),
      isResponding: true,
    );

    try {
      debugPrint('[Chat] → sending respondPermission RPC (runId=$runId)...');
      await _relay.respondPermission(
        taskId: _taskId!,
        workspacePath: _ref.workspacePath,
        traceId: runId,
        permissionRequestId: permissionId,
        optionId: optionId,
        decision: decision,
        fullResponse: fullResponse,
      );
      debugPrint('[Chat] ✓ respondPermission RPC sent');
      // ★ 批准后重新加载完整历史 — ExitPlanMode status 从 running→completed, 消息列表更新
      await _loadHistory();
      await _refreshRuntime();
    } catch (e) {
      debugPrint('[Chat] ✗ respondPermission FAILED: $e');
      state = state.copyWith(
        isResponding: false,
        error: '权限确认提交失败: $e',
      );
    }
  }

  /// 回答 plan 提议 (ExitPlanMode 工具触发的计划批准)。
  ///
  /// AI 调 ExitPlanMode 提交 plan 后, 后端暂停等用户批准/拒绝。
  /// 用户选择后, 通过文本回灌告知后端 (与 answerQuestion 同范式):
  ///   批准 → "User approved the plan, proceed"
  ///   拒绝 → "User rejected the plan"
  /// ⚠️ wire 上无专门 plan-response RPC, 用 enqueueTaskCommand 文本回灌。
  Future<void> answerPlan(bool approved) async {
    if (state.pendingPlan == null || _taskId == null) return;
    state = state.copyWith(
        pendingPlan: _clearPendingPlan, isResponding: true);
    final responseText = approved
        ? 'User approved the plan, proceed'
        : 'User rejected the plan';
    try {
      await _relay.enqueueTaskCommand(
        taskId: _taskId!,
        workspacePath: _ref.workspacePath,
        content: responseText,
      );
    } catch (e) {
      state = state.copyWith(
        isResponding: false,
        error: 'plan 回答提交失败: $e',
      );
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
  /// 从 tool.updated payload 提取 plan markdown (网页端 gJ/h3e 同款逻辑)。
  /// 搜索优先级: output.plan → output.text → output.content → output(string)
  /// → input.plan → input.text → input.content → input(string) → result(string)
  String? _extractPlanMarkdown(Map<String, dynamic> p) {
    for (final key in ['output', 'input', 'result']) {
      final raw = p[key];
      if (raw == null) continue;
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
      if (raw is Map) {
        for (final field in ['plan', 'text', 'content']) {
          final val = raw[field];
          if (val is String && val.trim().isNotEmpty) return val.trim();
        }
      }
    }
    return null;
  }

  void _recordToolActivity(SessionEvent event, {String? planOverride}) {
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
    // 提取输入参数 (payload.input — Map)
    final inputRaw = p['input'];
    final Map<String, dynamic>? input = inputRaw is Map<String, dynamic>
        ? inputRaw
        : (inputRaw is Map ? Map<String, dynamic>.from(inputRaw) : existing.input);
    // 提取结果 (payload.result 或 payload.output — String)
    // ExitPlanMode 有 planOverride (已从 output/input 提取 plan markdown)
    final resultRaw = p['result'] ?? p['output'];
    final String? result = planOverride ??
        (resultRaw is String
            ? resultRaw
            : (resultRaw != null ? resultRaw.toString() : existing.result));
    final updated = ToolActivity(
      toolCallId: toolCallId,
      toolName: toolName,
      status: status,
      elapsedMs: duration,
      input: input,
      result: result,
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
    // fire-and-forget: AI 回复完成后刷新 Token 用量 (不阻塞主流程)
    _refreshTokenUsage();
  }

  /// 刷新 Token 用量 (调用 getTokenUsage 并写入 state.tokenUsage)。
  /// 失败静默忽略, 不影响对话。
  void _refreshTokenUsage() {
    if (_taskId == null) return;
    getTokenUsage().then((usage) {
      if (!mounted || usage == null) return;
      state = state.copyWith(
        tokenUsage: (input: usage['input'] ?? 0, output: usage['output'] ?? 0),
      );
    });
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

  /// 手动结束当前 AI 回复 — 调 session/stop RPC (真正停止服务端生成)
  Future<void> stopResponding() async {
    // 乐观 UI 更新 (先停本地动画)
    _finishAssistantMessage();
    // 调服务端停止
    if (_taskId != null) {
      try {
        await _relay.stopSession(
          workspacePath: _ref.workspacePath,
          sessionId: _taskId!,
        );
      } catch (e) {
        debugPrint('[Chat] stopSession 失败: $e');
      }
    }
  }

  /// 回退最后一轮对话 — session/rewind
  Future<void> rewindLastTurn() async {
    if (_taskId == null) return;
    state = state.copyWith(isResponding: true, error: null);
    try {
      await _relay.rewindSession(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
      );
      await _loadHistory();
    } catch (e) {
      state = state.copyWith(isResponding: false, error: '回退失败: $e');
    }
  }

  /// 获取 Token 用量
  Future<Map<String, int>?> getTokenUsage() async {
    if (_taskId == null) return null;
    try {
      final resp = await _relay.getSessionUsage(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
      );
      final input = (resp['inputTokens'] as num?)?.toInt() ??
          (resp['input'] as num?)?.toInt() ?? 0;
      final output = (resp['outputTokens'] as num?)?.toInt() ??
          (resp['output'] as num?)?.toInt() ?? 0;
      return {'input': input, 'output': output};
    } catch (_) {
      return null;
    }
  }

  /// 重新加载历史
  Future<void> reload() async {
    await _loadHistory();
  }

  /// bridge 重连后重新订阅 session 事件 (snapshot 事件会带历史消息)
  Future<void> _resubscribe() async {
    try {
      debugPrint('[Chat] _resubscribe: subscribing...');
      final stream = await _relay.subscribeSessionEvents(
        workspacePath: _ref.workspacePath,
        sessionId: _taskId!,
      );
      _eventSub = stream.listen(_onSessionEvent);
      debugPrint('[Chat] _resubscribe: subscribed ✓');
    } catch (e) {
      debugPrint('[Chat] _resubscribe: FAILED: $e');
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _rpcReadySub?.cancel();
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
  return ChatNotifier(
    relay,
    chatRef,
    preferredModelReader: () => ref.read(preferredModelProvider),
    preferredModelSetter: (m) =>
        ref.read(preferredModelProvider.notifier).state = m,
    mergeDiscovered: (ids) =>
        ref.read(modelListProvider.notifier).mergeDiscoveredIds(ids),
    onSessionCreated: (task) {
      // 新会话加到 allTasksProvider 头部, 历史抽屉即时显示
      final tasks = List<Task>.from(ref.read(allTasksProvider));
      if (!tasks.any((t) => t.id == task.id)) {
        ref.read(allTasksProvider.notifier).state = [task, ...tasks];
      }
    },
    onTitleUpdated: (taskId, newTitle) {
      // 服务端标题更新 (snapshot.meta.title): 用 copyWith 刷新对应 task,
      // 历史抽屉 (_HistoryDrawer) 等所有订阅 allTasksProvider 的 UI 自动重绘。
      final tasks = ref.read(allTasksProvider);
      final idx = tasks.indexWhere((t) => t.id == taskId);
      if (idx < 0) return;
      if (tasks[idx].title == newTitle) return; // 无变化, 跳过
      final updated = List<Task>.from(tasks);
      updated[idx] = updated[idx].copyWith(title: newTitle);
      ref.read(allTasksProvider.notifier).state = updated;
    },
  );
});
