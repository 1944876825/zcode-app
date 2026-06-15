import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show WebSocket;
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

import 'relay_events.dart';
import 'relay_protocol.dart';
import 'rpc_codec.dart';

/// Relay 连接配置 (实测验证)
class RelayConfig {
  /// WebSocket URL: wss://zcode.z.ai/ws?mid={mid}
  final String wsUrl;

  /// 设备 SID (URL sid 参数, 含 d_ 前缀)
  final String deviceSid;

  /// 密码哈希 (URL hash 参数, URL decode 后)
  final String passHash;

  /// Cookie (会话认证, 至少含 acw_tc)
  final String cookie;

  /// 设备名
  final String deviceName;

  /// 应用版本
  final String appVersion;

  const RelayConfig({
    required this.wsUrl,
    required this.deviceSid,
    required this.passHash,
    required this.cookie,
    this.deviceName = 'mobile-browser',
    this.appVersion = '3.0.1',
  });

  /// 从 URL 参数构建配置
  factory RelayConfig.fromUrl({
    required String mid,
    required String deviceSid,
    required String passHash,
    required String cookie,
    String deviceName = 'mobile-browser',
  }) {
    return RelayConfig(
      wsUrl: 'wss://zcode.z.ai/ws?mid=$mid',
      deviceSid: deviceSid,
      passHash: passHash,
      cookie: cookie,
      deviceName: deviceName,
    );
  }
}

/// ZCode Relay 协议客户端
///
/// 完整实现 (实测 2026-06-15):
/// 1. WebSocket 连接 + 4 步 HMAC 认证
/// 2. Bootstrap (工作区/任务列表)
/// 3. Workspace Bridge + RPC Init 握手
/// 4. RPC 二进制协议 (varint+tag 编解码)
/// 5. 业务方法: 发消息 / 加载历史 / 订阅事件
class RelayClient {
  final RelayConfig config;
  final void Function(String level, String message)? logger;

  WebSocket? _socket;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  RelayConnectionState _state = RelayConnectionState.idle;
  RelayConnectionState get state => _state;

  // requestId → pending completer (data 层请求/响应配对)
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  // RPC 请求 ID → completer (rpc-frame 层配对)
  final Map<int, Completer<RpcFrame>> _pendingRpc = {};

  // RPC 订阅 ID → 事件流控制器 (type=204 事件分发)
  final Map<int, StreamController<SessionEvent>> _eventSubs = {};

  // bridge 状态
  int _bridgeGeneration = 0;
  String? _activeBridgeSession;
  bool _rpcReady = false;
  Completer<void>? _rpcReadyCompleter;

  // 序列号
  int _seqCounter = 0;
  int _rpcReqId = 0;

  // 事件流 (对 UI 暴露)
  final _stateController = StreamController<RelayConnectionState>.broadcast();
  final _agentEventController = StreamController<AgentEvent>.broadcast();
  final _sessionEventController = StreamController<SessionEvent>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  Stream<RelayConnectionState> get onStateChange => _stateController.stream;

  /// AI agent 事件流 (旧, 兼容 chat_screen)
  Stream<AgentEvent> get onAgentEvent => _agentEventController.stream;

  /// session 事件流 (新, 实测的 session.event 推送)
  ///
  /// 所有 onDynamicSessionEvent 订阅的事件都会推到这里。
  /// UI 用 event.type 区分内容 (tool.updated / text 流式 等)。
  Stream<SessionEvent> get onSessionEvent => _sessionEventController.stream;

  Stream<String> get onError => _errorController.stream;

  int _reconnectAttempts = 0;
  bool _intentionallyClosed = false;

  /// 进行中的连接 Future (单飞: 保证同一时刻只开一个 socket)
  /// zcode relay 同一 device_sid 只允许一个终端, 开两个会互相 KICK。
  Future<void>? _connectFuture;

  static const _maxReconnectAttempts = 10;
  static const _heartbeatInterval = Duration(seconds: 30);

  RelayClient({required this.config, this.logger});

  void _log(String level, String msg) => logger?.call(level, msg);

  void _setState(RelayConnectionState s) {
    if (_state == s) return;
    _log('info', 'Relay: ${_state.name} → ${s.name}');
    _state = s;
    _stateController.add(s);
  }

  String _genId(String prefix) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    return '${prefix}_${ts}_$rand';
  }

  String _genUuid() {
    final r = Random();
    final hex = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  // ================================================================
  // 连接 + 认证
  // ================================================================

  /// 连接并完成认证
  ///
  /// 单飞 (single-flight): 并发调用复用同一个进行中的连接 Future,
  /// 保证同一时刻只有一个 socket — 避免违反"单设备"约束导致 self-kick。
  Future<void> connect() async {
    // 已连上: 直接返回
    if (_socket != null && _socket!.readyState == WebSocket.open) {
      return;
    }
    // 复用进行中的连接 (bootstrap/load 并发调用时不再开第二个 socket)
    final pending = _connectFuture;
    if (pending != null) {
      _log('debug', 'connect() 复用进行中的连接');
      return pending;
    }
    final future = _doConnect();
    _connectFuture = future;
    try {
      await future;
    } finally {
      _connectFuture = null;
    }
  }

  Future<void> _doConnect() async {
    _intentionallyClosed = false;
    _setState(RelayConnectionState.connecting);
    _log('info', 'Connecting to ${config.wsUrl}');

    _socket = await WebSocket.connect(
      config.wsUrl,
      headers: {
        'Cookie': config.cookie,
        'Origin': 'https://zcode.z.ai',
        'User-Agent': 'Mozilla/5.0',
      },
    );
    // 协议级心跳: 探针实测无心跳 ~30s 会被服务端空闲关闭
    _socket!.pingInterval = const Duration(seconds: 20);

    _log('info', 'WebSocket connected');
    _setState(RelayConnectionState.connected);

    _socket!.listen(
      _onMessage,
      onError: (e) => _onError(e),
      onDone: () => _onDone(),
      cancelOnError: true,
    );

    // 等待认证完成
    final authCompleter = Completer<void>();
    _authCompleter = authCompleter;

    // Step 1: 发送 auth_init
    _sendRaw({
      'type': 'auth_init',
      'role': 'terminal',
      'device_sid': config.deviceSid,
      'meta': {
        'platform': 'web',
        'version': config.appVersion,
        'name': config.deviceName,
      },
      'client_ts': _ts(),
    });

    await authCompleter.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('Auth timeout'),
    );

    _startHeartbeat();
    // 认证成功才重置退避: 之前每次重连都在这里清零, 导致永远 2s 猛重连
    _reconnectAttempts = 0;
    _setState(RelayConnectionState.ready);
    _log('info', 'Authenticated successfully');
  }

  Completer<void>? _authCompleter;

  /// 断开连接
  Future<void> disconnect() async {
    _intentionallyClosed = true;
    _log('info', 'Disconnecting');
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    await _socket?.close();
    _socket = null;
    for (final c in _pending.values) {
      c.completeError('Disconnected');
    }
    _pending.clear();
    _setState(RelayConnectionState.disconnected);
  }

  // ================================================================
  // 消息处理
  // ================================================================

  int _ts() => DateTime.now().millisecondsSinceEpoch;

  void _sendRaw(Map<String, dynamic> msg) {
    if (_socket == null) return;
    _socket!.add(jsonEncode(msg));
  }

  /// 发送 data 层消息 (认证后的所有消息都通过 data 包裹)
  void _sendPayload(Map<String, dynamic> payload) {
    _sendRaw({
      'type': 'data',
      'payload': payload,
      'client_ts': _ts(),
    });
  }

  /// 发送 data 层消息并等待响应 (requestId 配对)
  Future<Map<String, dynamic>> _requestResponse(
    String zcodeType,
    Map<String, dynamic> extra, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final requestId = extra['requestId'] as String? ?? _genId(zcodeType);
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;

    _sendPayload({
      'zcode_type': zcodeType,
      'requestId': requestId,
      ...extra,
    });

    Future.delayed(timeout, () {
      if (_pending.containsKey(requestId)) {
        _pending.remove(requestId);
        completer.completeError(TimeoutException('Timeout: $zcodeType'));
      }
    });

    return completer.future;
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw);
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;

    switch (type) {
      case 'auth_challenge':
        _handleAuthChallenge(msg);
      case 'auth_ack':
        _handleAuthAck(msg);
      case 'data':
        _handleData(msg['payload'] as Map<String, dynamic>);
      case 'error':
        final code = msg['code'] ?? 'unknown';
        _log('error', 'Server error: $code');
        _errorController.add('Server error: $code');
      default:
        _log('debug', 'RECV [$type]');
    }
  }

  void _handleAuthChallenge(Map<String, dynamic> msg) {
    final nonce = msg['nonce'] as String;
    _log('info', 'Auth challenge received');

    // proof = base64url(HMAC-SHA256(passHash, "nonce|terminal|deviceSid"))
    final dataStr = '$nonce|terminal|${config.deviceSid}';
    final hmac = crypto.Hmac(crypto.sha256, utf8.encode(config.passHash));
    final proof = base64Url
        .encode(hmac.convert(utf8.encode(dataStr)).bytes)
        .replaceAll('=', '');

    _sendRaw({
      'type': 'auth_response',
      'device_sid': config.deviceSid,
      'proof': proof,
      'client_ts': _ts(),
    });
  }

  void _handleAuthAck(Map<String, dynamic> msg) {
    final terminalSid = msg['terminal_sid'] as String?;
    final pairStatus = msg['pair_status'] as String?;
    _log('info', 'Auth ACK: terminal_sid=$terminalSid, pair=$pairStatus');

    if (pairStatus == 'matched') {
      _authCompleter?.complete();
    } else {
      _authCompleter?.completeError('Pair status: $pairStatus');
    }
  }

  void _handleData(Map<String, dynamic> payload) {
    final zt = payload['zcode_type'] as String?;
    final requestId = payload['requestId'] as String?;

    // 配对 data 层请求-响应 (bootstrap / workspace-bridge 等)
    if (requestId != null && _pending.containsKey(requestId)) {
      final completer = _pending.remove(requestId)!;
      completer.complete(payload);
      return;
    }

    // 分发 rpc-frame
    if (zt == 'rpc-frame') {
      _handleRpcFrame(payload);
      return;
    }

    // 其他 data 层消息 (bridge-degraded 等)
    _log('debug', '→ DATA [$zt]');
  }

  // ================================================================
  // RPC 二进制帧处理
  // ================================================================

  void _handleRpcFrame(Map<String, dynamic> frame) {
    final dataBase64 = frame['dataBase64'] as String?;
    if (dataBase64 == null) return;

    final bytes = base64Decode(dataBase64);
    final rpc = RpcCodec.decode(Uint8List.fromList(bytes));

    // RPC Init (bridge 就绪通告)
    if (rpc.isInit && !_rpcReady) {
      _rpcReady = true;
      _log('info', 'RPC ready (bridge init received)');
      _rpcReadyCompleter?.complete();
      return;
    }

    // 成功响应 → 配对的请求
    if (rpc.isOk && rpc.id is int) {
      final id = rpc.id as int;
      final completer = _pendingRpc.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(rpc);
        return;
      }
    }

    // 错误响应
    if ((rpc.isError || rpc.isErrorObject) && rpc.id is int) {
      final id = rpc.id as int;
      final completer = _pendingRpc.remove(id);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(RpcException(rpc.errorMessage ?? 'RPC error'));
        return;
      }
      _log('error', 'RPC error #${rpc.id}: ${rpc.errorMessage}');
      return;
    }

    // 事件推送 (type=204)
    if (rpc.isEvent && rpc.id is int) {
      final subId = rpc.id as int;
      final event = SessionEvent.fromBody(rpc.body);

      // 推到对应订阅的 controller
      final sub = _eventSubs[subId];
      if (sub != null && !sub.isClosed) {
        sub.add(event);
      }

      // 也推到全局 session 事件流
      if (!_sessionEventController.isClosed) {
        _sessionEventController.add(event);
      }
      return;
    }
  }

  /// 发送 RPC 请求并等待 OK 响应
  Future<RpcFrame> _rpcCall(
    String channel,
    String method,
    dynamic args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_rpcReady) {
      throw StateError('RPC not ready (bridge not open)');
    }

    _rpcReqId++;
    final id = _rpcReqId;
    final completer = Completer<RpcFrame>();
    _pendingRpc[id] = completer;

    final data = RpcCodec.encodeRequest(id, channel, method, args);
    _sendRpcFrameData(data);

    Future.delayed(timeout, () {
      if (_pendingRpc.containsKey(id)) {
        _pendingRpc.remove(id);
        completer.completeError(TimeoutException('RPC timeout: $channel.$method'));
      }
    });

    return completer.future;
  }

  /// 订阅 RPC 事件流
  ///
  /// 返回事件 Stream, 同时注册全局 onSessionEvent。
  Future<Stream<SessionEvent>> _rpcSubscribe(
    String channel,
    String event,
    dynamic args,
  ) async {
    if (!_rpcReady) {
      throw StateError('RPC not ready');
    }

    _rpcReqId++;
    final id = _rpcReqId;
    final controller = StreamController<SessionEvent>.broadcast();
    _eventSubs[id] = controller;

    // 订阅请求本身可能也有响应 (确认订阅)
    final data = RpcCodec.encodeListen(id, channel, event, args);
    _sendRpcFrameData(data);

    return controller.stream;
  }

  void _sendRpcFrameData(Uint8List data) {
    if (_activeBridgeSession == null) return;
    _seqCounter++;
    _sendPayload({
      'zcode_type': 'rpc-frame',
      'bridgeSessionId': _activeBridgeSession,
      'bridgeGeneration': _bridgeGeneration,
      'seq': _seqCounter,
      'dataBase64': base64Encode(data),
    });
  }

  // ================================================================
  // 心跳 + 重连
  // ================================================================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      // TODO: 确定心跳格式 (可能不需要, WS 自带 keepalive)
    });
  }

  void _scheduleReconnect() {
    if (_intentionallyClosed) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setState(RelayConnectionState.error);
      return;
    }
    _reconnectAttempts++;
    _setState(RelayConnectionState.reconnecting);
    final delay = Duration(seconds: min(30, pow(2, _reconnectAttempts).toInt()));
    _log('info', 'Reconnect in ${delay.inSeconds}s (#$_reconnectAttempts)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () async {
      try {
        await connect();
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void _onError(dynamic error) {
    _log('error', 'WebSocket error: $error');
    _errorController.add('$error');
    _setState(RelayConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    _log('info', 'WebSocket closed');
    _heartbeatTimer?.cancel();
    _rpcReady = false;
    if (!_intentionallyClosed) {
      _scheduleReconnect();
    } else {
      _setState(RelayConnectionState.disconnected);
    }
  }

  // ================================================================
  // 公开 API — data 层 (不需要 bridge)
  // ================================================================

  /// Bootstrap — 获取工作区和任务列表
  Future<Map<String, dynamic>> bootstrap() {
    return _requestResponse('bootstrap-request', {});
  }

  /// 刷新工作区列表
  Future<Map<String, dynamic>> requestWorkspaceList() {
    return _requestResponse('workspace-list-request', {});
  }

  // ================================================================
  // 公开 API — bridge 层
  // ================================================================

  /// 打开工作区桥接, 等待 RPC Init
  ///
  /// 调用后 _rpcReady 变 true, 才能调 RPC 方法。
  Future<Map<String, dynamic>> openWorkspaceBridge(
    String workspaceKey, {
    String? taskId,
  }) async {
    _bridgeGeneration++;
    final bridgeSessionId = _genId('bridge');
    _activeBridgeSession = bridgeSessionId;
    _rpcReady = false;
    _rpcReadyCompleter = Completer<void>();

    final resp = _requestResponse('workspace-bridge-open', {
      'bridgeSessionId': bridgeSessionId,
      'bridgeGeneration': _bridgeGeneration,
      'workspaceKey': workspaceKey,
      if (taskId != null) 'taskId': taskId,
    });

    // 同时等 bridge-ready + RPC Init
    await resp;

    // 等 RPC Init 帧 (服务器自动推送)
    await _rpcReadyCompleter!.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw TimeoutException('RPC init timeout'),
    );

    return {'bridgeSessionId': bridgeSessionId, 'rpcReady': true};
  }

  /// 更新移动端视图状态
  void updateMobileViewState({
    String? activeTaskId,
    String? activeWorkspaceKey,
    String navigationIntent = 'chat',
  }) {
    _sendPayload({
      'zcode_type': 'mobile-view-state-update',
      if (activeTaskId != null) 'activeTaskId': activeTaskId,
      if (activeWorkspaceKey != null) 'activeWorkspaceKey': activeWorkspaceKey,
      'navigationIntent': navigationIntent,
    });
  }

  // ================================================================
  // 公开 API — RPC 业务方法 (实测, 见 docs/API协议规格.md §5)
  // ================================================================

  /// 发送消息 ★
  ///
  /// 调用 zcode-task.enqueueTaskCommand, 立即返回 {accepted:true}。
  /// AI 的流式回复通过 [subscribeSessionEvents] 接收。
  Future<Map<String, dynamic>> enqueueTaskCommand({
    required String taskId,
    required String workspacePath,
    required String content,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    final resp = await _rpcCall('zcode-task', 'enqueueTaskCommand', [
      {
        'workspacePath': workspacePath,
        'taskId': taskId,
        'commandId': 'queued_${now}_$rand',
        'traceId': _genUuid(),
        'queryId': _genUuid(),
        'type': 'send_prompt',
        'content': content,
        'clientId': 'renderer:${_genUuid()}',
        'clientLabel': config.deviceName,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 加载历史消息 ★
  ///
  /// 调用 zcode-task.getTaskSnapshotWithEtag, 返回 {snapshot, etag}。
  /// snapshot 含 meta + messages[] (见 docs §5.3)。
  Future<Map<String, dynamic>> getTaskSnapshot({
    required String taskId,
    required String workspacePath,
    int messageLimit = 50,
    int byteBudget = 204800,
    String? etag,
  }) async {
    final resp = await _rpcCall('zcode-task', 'getTaskSnapshotWithEtag', [
      {
        'taskId': taskId,
        'workspacePath': workspacePath,
        'messageLimit': messageLimit,
        'byteBudget': byteBudget,
        'clientMode': 'web-remote-replayable',
        if (etag != null) 'etag': etag,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 读取会话详情
  ///
  /// 调用 zcode-session.readSession, 返回完整 session + settings + messages。
  Future<Map<String, dynamic>> readSession({
    required String sessionId,
    required String workspacePath,
    int messageLimit = 1,
  }) async {
    final resp = await _rpcCall('zcode-session', 'readSession', [
      {
        'workspacePath': workspacePath,
        'sessionId': sessionId,
        'messageLimit': messageLimit,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 新建会话/对话 ★
  ///
  /// 调用 zcode-session.createSession, 返回新 session (含 sessionId)。
  /// 参数 (实测自客户端 JS): {workspacePath, workspaceIdentity, mode, model, thoughtLevel}
  Future<Map<String, dynamic>> createSession({
    required String workspacePath,
    String? workspaceIdentity,
    String mode = 'build',
    String? model,
    String thoughtLevel = 'max',
  }) async {
    final resp = await _rpcCall('zcode-session', 'createSession', [
      {
        'workspacePath': workspacePath,
        if (workspaceIdentity != null) 'workspaceIdentity': workspaceIdentity,
        'mode': mode,
        if (model != null) 'model': model,
        'thoughtLevel': thoughtLevel,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 订阅 session 事件流 ★
  ///
  /// 调用 zcode-session.onDynamicSessionEvent 订阅,
  /// 返回事件 Stream。AI 的流式回复 (text_delta / reasoning_delta 等)
  /// 都会推到这里。也可监听全局 [onSessionEvent]。
  ///
  /// 参数 (实测自客户端 index-DMg1tzSS.js):
  ///   {workspacePath, sessionId, deliveryKind, includeSnapshot}
  /// 关键: sessionId 指定要订阅哪个会话的事件, 缺了服务器不推事件。
  Future<Stream<SessionEvent>> subscribeSessionEvents({
    required String workspacePath,
    required String sessionId,
    String deliveryKind = 'web-remote-replayable',
    bool includeSnapshot = true,
  }) {
    return _rpcSubscribe('zcode-session', 'onDynamicSessionEvent', {
      'workspacePath': workspacePath,
      'sessionId': sessionId,
      'deliveryKind': deliveryKind,
      'includeSnapshot': includeSnapshot,
    });
  }

  /// 获取 Token 用量
  Future<Map<String, dynamic>> getTaskTokenUsage({
    required String taskId,
    required String workspacePath,
  }) async {
    final resp = await _rpcCall('zcode-task', 'getTaskTokenUsage', [
      {'taskId': taskId, 'workspacePath': workspacePath}
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 通用 RPC 调用 (兜底, 用于尚未封装的方法)
  Future<RpcFrame> rpcCall(String channel, String method, dynamic args) {
    return _rpcCall(channel, method, args);
  }

  void dispose() {
    disconnect();
    for (final c in _eventSubs.values) {
      c.close();
    }
    _eventSubs.clear();
    _stateController.close();
    _agentEventController.close();
    _sessionEventController.close();
    _errorController.close();
  }
}

/// RPC 调用异常
class RpcException implements Exception {
  final String message;
  RpcException(this.message);

  @override
  String toString() => 'RpcException: $message';
}
