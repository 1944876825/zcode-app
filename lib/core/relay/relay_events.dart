/// Agent 事件流类型 — AI 回复的流式事件
///
/// 通过 workspace-bridge WebSocket 推送
enum AgentEventType {
  taskRunStarted('task_run_started'),
  taskComplete('task_complete'),
  taskError('task_error'),
  taskSnapshotUpdated('task_snapshot_updated'),
  taskTokenUsageDelta('task_token_usage_delta'),

  agentMessageChunk('agent_message_chunk'),
  agentThoughtChunk('agent_thought_chunk'),
  agentActivity('agent_activity'),

  modelTrajectory('model-trajectory'),
  modelChange('model_change'),

  diff('diff'),
  diffLine('diff-line'),

  file('file'),
  command('command'),
  skill('skill'),
  ;

  final String value;
  const AgentEventType(this.value);

  static AgentEventType? fromString(String? value) {
    if (value == null) return null;
    for (final type in AgentEventType.values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// 从原始事件 payload 解析出的事件类型
sealed class AgentEvent {
  final AgentEventType type;
  final DateTime timestamp;

  AgentEvent({required this.type, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

/// AI 回复文本块 (流式)
class AgentMessageChunk extends AgentEvent {
  final String content;
  final String? model;

  AgentMessageChunk({required this.content, this.model})
      : super(type: AgentEventType.agentMessageChunk);
}

/// AI 思考过程文本块
class AgentThoughtChunk extends AgentEvent {
  final String content;

  AgentThoughtChunk({required this.content})
      : super(type: AgentEventType.agentThoughtChunk);
}

/// 任务开始
class TaskRunStarted extends AgentEvent {
  final String taskId;

  TaskRunStarted({required this.taskId})
      : super(type: AgentEventType.taskRunStarted);
}

/// 任务完成
class TaskComplete extends AgentEvent {
  final String taskId;

  TaskComplete({required this.taskId})
      : super(type: AgentEventType.taskComplete);
}

/// 任务错误
class TaskError extends AgentEvent {
  final String taskId;
  final String message;

  TaskError({required this.taskId, required this.message})
      : super(type: AgentEventType.taskError);
}

/// Token 用量增量
class TokenUsageDelta extends AgentEvent {
  final int inputTokens;
  final int outputTokens;

  TokenUsageDelta({required this.inputTokens, required this.outputTokens})
      : super(type: AgentEventType.taskTokenUsageDelta);
}

/// 代码差异
class DiffEvent extends AgentEvent {
  final String filePath;
  final List<DiffLine> lines;

  DiffEvent({required this.filePath, required this.lines})
      : super(type: AgentEventType.diff);
}

class DiffLine {
  final DiffLineType type;
  final int? oldLineNumber;
  final int? newLineNumber;
  final String content;

  DiffLine({
    required this.type,
    this.oldLineNumber,
    this.newLineNumber,
    required this.content,
  });
}

enum DiffLineType { added, removed, context }

/// Agent 活动
class AgentActivity extends AgentEvent {
  final String activity;

  AgentActivity({required this.activity})
      : super(type: AgentEventType.agentActivity);
}

/// 模型切换
class ModelChange extends AgentEvent {
  final String model;

  ModelChange({required this.model})
      : super(type: AgentEventType.modelChange);
}

/// 文件操作事件
class FileEvent extends AgentEvent {
  final String path;
  final String action;

  FileEvent({required this.path, required this.action})
      : super(type: AgentEventType.file);
}

/// 命令执行事件
class CommandEvent extends AgentEvent {
  final String command;
  final String? output;

  CommandEvent({required this.command, this.output})
      : super(type: AgentEventType.command);
}

/// 通用/未识别的 agent 事件
class GenericAgentEvent extends AgentEvent {
  final Map<String, dynamic> raw;

  GenericAgentEvent({required AgentEventType type, required this.raw})
      : super(type: type);
}

/// 从 JSON 解析 Agent 事件
AgentEvent parseAgentEvent(Map<String, dynamic> json) {
  final typeStr = json['type'] as String?;
  final kindStr = json['kind'] as String?;

  // 先按 type 匹配
  final type = AgentEventType.fromString(typeStr) ??
      AgentEventType.fromString(kindStr);

  if (type == null) {
    return GenericAgentEvent(
      type: AgentEventType.agentActivity,
      raw: json,
    );
  }

  return switch (type) {
    AgentEventType.agentMessageChunk => AgentMessageChunk(
        content: json['content'] as String? ?? json['text'] as String? ?? '',
        model: json['model'] as String?,
      ),
    AgentEventType.agentThoughtChunk => AgentThoughtChunk(
        content: json['content'] as String? ?? '',
      ),
    AgentEventType.taskRunStarted => TaskRunStarted(
        taskId: json['taskId'] as String? ?? json['task_id'] as String? ?? '',
      ),
    AgentEventType.taskComplete => TaskComplete(
        taskId: json['taskId'] as String? ?? json['task_id'] as String? ?? '',
      ),
    AgentEventType.taskError => TaskError(
        taskId: json['taskId'] as String? ?? json['task_id'] as String? ?? '',
        message: json['message'] as String? ??
            json['error'] as String? ??
            'Unknown error',
      ),
    AgentEventType.taskTokenUsageDelta => TokenUsageDelta(
        inputTokens: (json['input'] as num?)?.toInt() ??
            (json['inputTokens'] as num?)?.toInt() ??
            0,
        outputTokens: (json['output'] as num?)?.toInt() ??
            (json['outputTokens'] as num?)?.toInt() ??
            0,
      ),
    AgentEventType.modelChange => ModelChange(
        model: json['model'] as String? ?? '',
      ),
    AgentEventType.diff => DiffEvent(
        filePath: json['path'] as String? ?? json['file'] as String? ?? '',
        lines: _parseDiffLines(json['lines'] as List<dynamic>? ?? []),
      ),
    AgentEventType.file => FileEvent(
        path: json['path'] as String? ?? '',
        action: json['action'] as String? ?? '',
      ),
    AgentEventType.command => CommandEvent(
        command: json['command'] as String? ?? '',
        output: json['output'] as String?,
      ),
    AgentEventType.agentActivity => AgentActivity(
        activity: json['activity'] as String? ??
            json['message'] as String? ??
            '',
      ),
    _ => GenericAgentEvent(type: type, raw: json),
  };
}

List<DiffLine> _parseDiffLines(List<dynamic> raw) {
  return raw.map((e) {
    final map = e as Map<String, dynamic>;
    final typeStr = map['type'] as String? ?? 'context';
    return DiffLine(
      type: switch (typeStr) {
        'add' || 'added' || '+' => DiffLineType.added,
        'remove' || 'removed' || '-' || 'del' => DiffLineType.removed,
        _ => DiffLineType.context,
      },
      oldLineNumber: (map['oldLineNumber'] as num?)?.toInt(),
      newLineNumber: (map['newLineNumber'] as num?)?.toInt(),
      content: map['content'] as String? ?? '',
    );
  }).toList();
}

// ================================================================
// session.event 模型 (实测 2026-06-15)
//
// AI 回复的流式推送统一走 zcode-session.onDynamicSessionEvent 订阅,
// 每个事件是一个 session.event, 通过 event.type 区分内容类型。
// 详见 docs/API协议规格.md §5.2
// ================================================================

/// 从 RPC type=204 (EventFire) 解析出的 session 事件
class SessionEvent {
  /// 事件 ID
  final String eventId;

  /// 会话 ID (taskId)
  final String sessionId;

  /// 轮次 ID (同一次提问共享)
  final String turnId;

  /// 事件序号 (单调递增)
  final int seq;

  /// 追踪 ID
  final String? traceId;

  /// 时间戳 (毫秒)
  final int? timestamp;

  /// 投递方式 (web-remote-replayable)
  final String? deliveryKind;

  /// 事件类型 (session.event 外层 type, 如 "session.event")
  final String type;

  /// 业务种类 (event.kind, 实测的关键字段)
  ///
  /// 实测自 APP 日志 (2026-06-15), 真实 kind 体系:
  ///   - snapshot: 订阅时一次性推送 (含历史)
  ///   - state.updated: 状态变更 (prompt_started/running/idle)
  ///   - turn.started: 一轮开始 (payload.input 是用户输入)
  ///   - model.streaming: AI 文本流 (payload.delta 是增量, payload.done 完成标志)
  ///   - session.updated: 会话状态更新
  ///   - turn.completed: 一轮完成
  ///
  /// 注: JS 源码里的 text_delta/reasoning_delta 是客户端内部转换后的名字,
  /// 服务器实际推送的是 model.streaming。
  final String kind;

  /// 事件 payload (结构随 kind 变化, 实测文本在 payload.delta)
  final Map<String, dynamic> payload;

  /// 原始 event JSON
  final Map<String, dynamic> raw;

  SessionEvent({
    required this.eventId,
    required this.sessionId,
    required this.turnId,
    required this.seq,
    this.traceId,
    this.timestamp,
    this.deliveryKind,
    required this.type,
    required this.kind,
    required this.payload,
    required this.raw,
  });

  /// 从 session.event body 解析
  ///
  /// [body] 是 RPC 帧解码后的 body, 形如:
  /// {"type":"session.event", "event":{eventId, sessionId, turnId, seq, kind, delta, ...}}
  ///
  /// 注意: event 对象有 `kind` (业务种类) 和 `delta` (文本增量) 字段,
  /// 还有 `type` (外层, 用于 tool.updated 等少数事件)。
  factory SessionEvent.fromBody(dynamic body) {
    final map = body is Map ? body as Map<String, dynamic> : <String, dynamic>{};
    final event = (map['event'] as Map<String, dynamic>?) ?? map;
    return SessionEvent(
      eventId: event['eventId'] as String? ?? '',
      sessionId: event['sessionId'] as String? ?? '',
      turnId: event['turnId'] as String? ?? '',
      seq: (event['seq'] as num?)?.toInt() ?? 0,
      traceId: event['traceId'] as String?,
      timestamp: (event['timestamp'] as num?)?.toInt(),
      deliveryKind: event['deliveryKind'] as String?,
      type: event['type'] as String? ?? '',
      kind: event['kind'] as String? ?? event['type'] as String? ?? '',
      // 实测: delta/done 在 event.payload 内部 (event.payload.delta)
      // 不是 event 顶层。fromBody 把内层 payload 提取出来。
      payload: (event['payload'] as Map<String, dynamic>?) ?? event,
      raw: event,
    );
  }

  // ── 便捷判断 (基于 kind/type, 实测自 APP 日志 2026-06-15) ──
  //
  // 真实事件序列 (实测):
  //   snapshot          (订阅时一次性推送, 含历史)
  //   state.updated     (状态变更: prompt_started/running/idle)
  //   turn.started      (一轮开始, payload.input 是用户输入)
  //   model.streaming   (AI 文本流, payload.delta 是增量, payload.done 是否完成)
  //   session.updated   (会话状态更新)
  //   turn.completed    (一轮完成)

  /// AI 文本流增量 (实测 kind=model.streaming, 文本在 payload.delta)
  ///
  /// payload 内层 kind 区分正文/思考 (实测自 JS 源码):
  ///   - text_delta: 正文
  ///   - reasoning_delta: 思考
  /// 若 payload 无 kind 字段, 默认当正文处理。
  bool get isTextDelta {
    if (kind != 'model.streaming') return false;
    final innerKind = payload['kind'] as String?;
    return innerKind == null || innerKind == 'text_delta';
  }

  /// AI 思考流增量
  bool get isReasoningDelta =>
      kind == 'model.streaming' && payload['kind'] == 'reasoning_delta';

  /// 文本增量 (从 payload.delta 取, 实测真实位置)
  String? get delta => payload['delta'] as String?;

  /// AI 回复是否完成 (payload.done)
  bool get isDone => payload['done'] == true;

  /// 一轮开始
  bool get isTurnStarted => kind == 'turn.started';

  /// 一轮完成
  bool get isTurnCompleted => kind == 'turn.completed';

  /// 是否是工具调用事件
  bool get isToolEvent =>
      kind.startsWith('tool_') || kind.startsWith('tool.');

  /// 工具名 (仅工具事件)
  String? get toolName => payload['toolName'] as String?;

  /// 工具调用 ID
  String? get toolCallId => payload['toolCallId'] as String?;

  /// 任务完成
  bool get isTaskComplete =>
      kind == 'turn.completed' || kind == 'task_complete';

  /// 任务出错
  bool get isTaskError => kind == 'task_error' || kind == 'turn.error';

  /// Token 用量增量
  bool get isTokenUsageDelta => kind == 'task_token_usage_delta';

  /// assistant 消息 ID (model.streaming 里有, 用于关联同一条 AI 消息)
  String? get assistantMessageId =>
      payload['assistantMessageId'] as String?;

  @override
  String toString() => 'SessionEvent(seq=$seq, kind=$kind, turn=$turnId)';
}

