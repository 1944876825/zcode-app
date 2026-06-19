import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:io' show WebSocket;
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

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
  String? _currentWorkspaceKey;
  String? _currentTaskId;
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
  final _rpcReadyController = StreamController<bool>.broadcast();

  Stream<RelayConnectionState> get onStateChange => _stateController.stream;

  /// AI agent 事件流 (旧, 兼容 chat_screen)
  Stream<AgentEvent> get onAgentEvent => _agentEventController.stream;

  /// session 事件流 (新, 实测的 session.event 推送)
  ///
  /// 所有 onDynamicSessionEvent 订阅的事件都会推到这里。
  /// UI 用 event.type 区分内容 (tool.updated / text 流式 等)。
  Stream<SessionEvent> get onSessionEvent => _sessionEventController.stream;

  Stream<String> get onError => _errorController.stream;

  /// RPC 就绪状态变化: true=bridge open+RPC Init; false=bridge 拆除/socket 关闭。
  /// 全局模型列表等账号级数据据此刷新 (重连/切工作区会自动重载)。
  Stream<bool> get onRpcReadyChange => _rpcReadyController.stream;

  /// 等 RPC ready (同步检查 + stream 等待), 带超时。
  Future<void> waitRpcReady(Duration timeout) async {
    if (_rpcReady) return;
    await onRpcReadyChange
        .firstWhere((ready) => ready)
        .timeout(timeout);
  }

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

    // 其他 data 层消息
    if (zt == 'bridge-degraded') {
      _log('warn', '→ bridge-degraded! payload=${payload.toString().substring(0, payload.toString().length > 500 ? 500 : payload.toString().length)}');
      _log('warn', '  pending RPC: ${_pendingRpc.length}, rpcReady=$_rpcReady, bridgeGen=$_bridgeGeneration');
      _onBridgeDegraded();
      return;
    }
    _log('debug', '→ DATA [$zt] payload=${payload.toString().substring(0, payload.toString().length > 300 ? 300 : payload.toString().length)}');
  }

  int _degradedCount = 0;
  DateTime? _lastReconnectTime;

  /// bridge 降级: 立即 fail 所有 pending RPC, 尝试重连 (带防抖)
  void _onBridgeDegraded() {
    _rpcReady = false;
    _rpcReadyController.add(false);

    // fail 所有 pending RPC
    final pendingRpc = Map<int, Completer<RpcFrame>>.from(_pendingRpc);
    _pendingRpc.clear();
    for (final entry in pendingRpc.entries) {
      if (!entry.value.isCompleted) {
        entry.value.completeError(
          TimeoutException('Bridge degraded'),
        );
      }
    }

    // 防抖: 10 秒内最多重连 3 次，避免死循环
    final now = DateTime.now();
    if (_lastReconnectTime != null &&
        now.difference(_lastReconnectTime!).inSeconds < 10) {
      _degradedCount++;
      if (_degradedCount > 3) {
        _log('warn', 'Bridge degraded ${_degradedCount}x in 10s, stop auto-reconnect');
        return;
      }
    } else {
      _degradedCount = 0;
    }
    _lastReconnectTime = now;

    // 尝试自动重连 bridge (带上 taskId)
    if (_currentWorkspaceKey != null) {
      Future.delayed(const Duration(seconds: 2), () {
        _log('info', 'Auto-reopening bridge: $_currentWorkspaceKey (taskId=${_currentTaskId ?? "none"}, attempt ${_degradedCount + 1})');
        _rpcReadyCompleter = Completer<void>();
        _bridgeGeneration++;
        _seqCounter = 0;  // ★ 重置 seq
        _rpcReqId = 0;    // ★ 重置 RPC ID
        final bridgeSessionId = _genId('bridge');
        _activeBridgeSession = bridgeSessionId;
        _requestResponse('workspace-bridge-open', {
          'bridgeSessionId': bridgeSessionId,
          'bridgeGeneration': _bridgeGeneration,
          'workspaceKey': _currentWorkspaceKey!,
          if (_currentTaskId != null) 'taskId': _currentTaskId!,
        }).then((_) {
          return _rpcReadyCompleter!.future.timeout(
            const Duration(seconds: 15),
            onTimeout: () => throw TimeoutException('RPC init timeout (reconnect)'),
          );
        }).then((_) {
          _log('info', 'Bridge reopened ✓');
          _degradedCount = 0;
        }).catchError((e) {
          _log('error', 'Bridge reopen failed: $e');
        });
      });
    }
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
      _rpcReadyController.add(true);
      return;
    }

    // 成功响应 → 配对的请求
    if (rpc.isOk && rpc.id is int) {
      final id = rpc.id as int;
      final completer = _pendingRpc.remove(id);
      if (completer != null && !completer.isCompleted) {
        final bodyStr = rpc.body?.toString() ?? 'null';
        _log('info', '← RPC #$id OK: body type=${rpc.body.runtimeType}, len=${bodyStr.length}, preview=${bodyStr.substring(0, bodyStr.length > 200 ? 200 : bodyStr.length)}');
        completer.complete(rpc);
        return;
      }
    }

    // 错误响应
    if ((rpc.isError || rpc.isErrorObject) && rpc.id is int) {
      final id = rpc.id as int;
      final completer = _pendingRpc.remove(id);
      _log('error', '← RPC #$id ERROR: ${rpc.errorMessage}');
      if (completer != null && !completer.isCompleted) {
        completer.completeError(RpcException(rpc.errorMessage ?? 'RPC error'));
        return;
      }
      return;
    }

    // 事件推送 (type=204)
    if (rpc.isEvent && rpc.id is int) {
      final subId = rpc.id as int;
      final event = SessionEvent.fromBody(rpc.body);
      // ★ 详细日志: 事件
      debugPrint('[Relay] ← EVENT sub=$subId kind=${event.kind} sid=${event.sessionId}');
      if (event.kind == 'snapshot' || event.kind.contains('snapshot')) {
        final pStr = event.payload.toString();
        debugPrint('[Relay] ← EVENT snapshot payload=${pStr.substring(0, pStr.length > 500 ? 500 : pStr.length)}');
      }

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

    // ★ 详细日志: 发送的 RPC 请求
    final argsStr = args?.toString() ?? 'null';
    _log('info', '→ RPC #$id: $channel.$method args=${argsStr.substring(0, argsStr.length > 300 ? 300 : argsStr.length)}');

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

    // ★ 日志
    final argsStr = args?.toString() ?? 'null';
    _log('info', '→ LISTEN #$id: $channel.$event args=${argsStr.substring(0, argsStr.length > 200 ? 200 : argsStr.length)}');

    // 订阅请求本身可能也有响应 (确认订阅)
    final data = RpcCodec.encodeListen(id, channel, event, args);
    _sendRpcFrameData(data);

    return controller.stream;
  }

  void _sendRpcFrameData(Uint8List data) {
    if (_activeBridgeSession == null) return;
    _seqCounter++;
    debugPrint('[Relay] _sendRpcFrameData: seq=$_seqCounter bridgeGen=$_bridgeGeneration bridgeSession=$_activeBridgeSession');
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
    _rpcReadyController.add(false);
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
    _currentWorkspaceKey = workspaceKey;
    _currentTaskId = taskId;
    _bridgeGeneration++;
    _seqCounter = 0; // ★ 每个 bridge session seq 从 1 开始
    _rpcReqId = 0;   // ★ RPC 请求 ID 也重置
    final bridgeSessionId = _genId('bridge');
    _activeBridgeSession = bridgeSessionId;
    _rpcReady = false;
    _rpcReadyController.add(false);
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

  /// 回答工具权限确认 ★ — enqueueTaskCommand(type: respond_permission)
  ///
  /// wire 实测自 host bundle Zod schema (2026-06-19, 规格 §11.2):
  ///   enqueueTaskCommand type 除了 "send_prompt" 还有 "respond_permission",
  ///   携带 permissionRequestId + optionId + response.decision。
  ///
  /// [permissionRequestId] 来自 permission.requested 事件的 payload.requestId。
  /// [optionId] 来自用户选择的 option.optionId。
  /// [decision] "allow" | "deny" | "escalate" | "modify"。
  Future<Map<String, dynamic>> respondPermission({
    required String taskId,
    required String workspacePath,
    required String traceId,
    required String permissionRequestId,
    required String optionId,
    required String decision,
    String? reason,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0');
    final resp = await _rpcCall('zcode-task', 'enqueueTaskCommand', [
      {
        'workspacePath': workspacePath,
        'workspaceKey': workspacePath,
        'taskId': taskId,
        'runId': traceId,
        'commandRequestId': 'queued_${now}_$rand',
        'type': 'respond_permission',
        'permissionRequestId': permissionRequestId,
        'optionId': optionId,
        'response': {
          'decision': decision,
          if (reason != null) 'reason': reason,
        },
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
    debugPrint('[Relay] getTaskSnapshot: taskId=$taskId limit=$messageLimit');
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
    debugPrint('[Relay] getTaskSnapshot: resp.body type=${resp.body.runtimeType}');
    if (resp.body is Map) {
      final m = resp.body as Map;
      debugPrint('[Relay] getTaskSnapshot: keys=${m.keys.toList()}');
      return Map<String, dynamic>.from(m);
    }
    debugPrint('[Relay] getTaskSnapshot: body is NOT a Map! body=${resp.body}');
    return {'raw': resp.body};
  }

  /// 列出工作区文件 (file.listWorkspaceFiles)
  /// 网页端 @ 文件提及用此方法获取完整文件列表, 客户端做模糊过滤。
  /// 返回 [{path, relativePath, name, type}, ...]
  Future<List<Map<String, dynamic>>> listWorkspaceFiles({
    required String rootPath,
  }) async {
    final resp = await _rpcCall('file', 'listWorkspaceFiles', [
      {'rootPath': rootPath}
    ]);
    if (resp.body is List) {
      return (resp.body as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
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

  /// 切换已有会话的代理模式 ★ (zcode-session.setMode)
  ///
  /// 实测自 host bundle: `request(session/setMode, {sessionId, mode, expectedRevision})`。
  /// **推翻旧结论 "mode 创建时固定"** —— 已有会话也能改 mode。
  /// 新会话仍走 createSession.mode (首发消息时); 此方法用于已有会话热切换。
  Future<Map<String, dynamic>> setSessionMode({
    required String workspacePath,
    required String sessionId,
    required String mode,
    int? expectedRevision,
  }) async {
    final resp = await _rpcCall('zcode-session', 'setMode', [
      {
        'workspacePath': workspacePath,
        'sessionId': sessionId,
        'mode': mode,
        if (expectedRevision != null) 'expectedRevision': expectedRevision,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 压缩对话 (/compact 命令) — zcode-session.compact
  Future<Map<String, dynamic>> compactSession({
    required String workspacePath,
    required String sessionId,
  }) async {
    final resp = await _rpcCall('zcode-session', 'compact', [
      {'workspacePath': workspacePath, 'sessionId': sessionId}
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 读取工作区状态 (含可用模型列表) ★
  ///
  /// host bundle 实测: `readState()` 返回含 `modelProviders`/`bots` 的对象。
  /// 模型 ID 形如 `<providerUuid>/<slug>` (如 `…/glm-5.2`), UUID 为**账号级**
  /// (不在 bundle 里硬编码 → 不能写死), 故可用模型必须运行时从这里取。
  ///
  /// channel: host bundle 的 `readState` 带 `preferZCodeSession` 路由提示,
  /// 故优先 `zcode-session`; `_rpcCall` 遇错误帧会直接抛 RpcException
  /// (不返回错误帧), 因此用 try/catch 回退 `zcode-workspace`。
  Future<Map<String, dynamic>> readWorkspaceState({
    required String workspacePath,
  }) async {
    RpcFrame resp;
    try {
      resp = await _rpcCall('zcode-session', 'readState', [
        {'workspacePath': workspacePath}
      ]);
    } on RpcException {
      resp = await _rpcCall('zcode-workspace', 'readState', [
        {'workspacePath': workspacePath}
      ]);
    }
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body, 'typeCode': resp.typeCode};
  }

  /// 获取模型的**显示顺序**列表 — model-provider.getDisplayOrder (规格 §5.5)。
  /// 桌面端模型下拉用的就是它 (比 getAll 更精简/有序); getAll 会列出所有
  /// provider×模型组合 (含 zai/bigmodel/start-plan 等, 多重复), 显示太杂。
  Future<Map<String, dynamic>> getModelDisplayOrder() async {
    final resp = await _rpcCall('model-provider', 'getDisplayOrder', []);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body, 'typeCode': resp.typeCode};
  }

  /// 获取账号可用模型列表 — model-provider.getAll (规格 §5.5 表)。
  /// 这是模型列表的**权威来源** (区别于 zcode-workspace/readState, 后者在 relay 桥为
  /// Unknown channel)。getAll 失败回退 getAllCached。
  Future<Map<String, dynamic>> getModelProviders() async {
    RpcFrame resp;
    try {
      resp = await _rpcCall('model-provider', 'getAll', []);
    } on RpcException {
      resp = await _rpcCall('model-provider', 'getAllCached', []);
    }
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body, 'typeCode': resp.typeCode};
  }

  /// 热切换会话模型 — zcode-session.setModel
  /// [model] 为完整 ID `<providerUuid>/<slug>` (来自 readWorkspaceState)。
  Future<Map<String, dynamic>> setSessionModel({
    required String workspacePath,
    required String sessionId,
    required String model,
  }) async {
    final resp = await _rpcCall('zcode-session', 'setModel', [
      {'workspacePath': workspacePath, 'sessionId': sessionId, 'model': model}
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 通用 RPC 调用 (兜底, 用于尚未封装的方法)
  Future<RpcFrame> rpcCall(String channel, String method, dynamic args) {
    return _rpcCall(channel, method, args);
  }

  // ================================================================
  // session 域方法 (规格 §5.5 — session/stop, session/messages, etc.)
  // ================================================================

  /// 停止当前生成 ★ — session/stop
  Future<Map<String, dynamic>> stopSession({
    required String workspacePath,
    required String sessionId,
  }) async {
    final resp = await _rpcCall('zcode-session', 'stop', [
      {'workspacePath': workspacePath, 'sessionId': sessionId}
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 加载更多历史消息 (分页) — session/messages
  ///
  /// afterSeq: 返回此序号之后的消息 (用于增量加载)。
  Future<Map<String, dynamic>> getSessionMessages({
    required String workspacePath,
    required String sessionId,
    int? afterSeq,
    int limit = 50,
  }) async {
    final resp = await _rpcCall('zcode-session', 'messages', [
      {
        'workspacePath': workspacePath,
        'sessionId': sessionId,
        if (afterSeq != null) 'afterSeq': afterSeq,
        'limit': limit,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 回退对话 (撤销最后一轮) — session/rewind
  Future<Map<String, dynamic>> rewindSession({
    required String workspacePath,
    required String sessionId,
    int? toTurnIndex,
  }) async {
    final resp = await _rpcCall('zcode-session', 'rewind', [
      {
        'workspacePath': workspacePath,
        'sessionId': sessionId,
        if (toTurnIndex != null) 'toTurnIndex': toTurnIndex,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 关闭/结束会话 — session/close
  Future<Map<String, dynamic>> closeSession({
    required String workspacePath,
    required String sessionId,
  }) async {
    final resp = await _rpcCall('zcode-session', 'close', [
      {'workspacePath': workspacePath, 'sessionId': sessionId}
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 获取 Token 用量 — session/usage
  Future<Map<String, dynamic>> getSessionUsage({
    required String workspacePath,
    required String sessionId,
  }) async {
    final resp = await _rpcCall('zcode-session', 'usage', [
      {'workspacePath': workspacePath, 'sessionId': sessionId}
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 切换思考级别 — session/setThoughtLevel
  Future<Map<String, dynamic>> setSessionThoughtLevel({
    required String workspacePath,
    required String sessionId,
    required String thoughtLevel, // 'max' | 'medium' | 'nothink'
  }) async {
    final resp = await _rpcCall('zcode-session', 'setThoughtLevel', [
      {
        'workspacePath': workspacePath,
        'sessionId': sessionId,
        'thoughtLevel': thoughtLevel,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 列出会话 — session/list
  Future<Map<String, dynamic>> listSessions({
    required String workspacePath,
  }) async {
    final resp = await _rpcCall('zcode-session', 'list', [
      {'workspacePath': workspacePath}
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  // ================================================================
  // skills 域方法 — skills/list, skills/setEnabled
  // ================================================================

  /// 获取技能列表 — skills/list
  ///
  /// 返回 {skills: [...], capability: {...}, diagnostics: [...]}
  /// 每个 skill: {id, name, description, enabled, scope, source}
  Future<Map<String, dynamic>> getSkills({
    required String workspacePath,
    String? workspaceIdentity,
    String provider = 'glm',
  }) async {
    final resp = await _rpcCall('skills', 'list', [
      {
        'workspacePath': workspacePath,
        if (workspaceIdentity != null && workspaceIdentity.isNotEmpty)
          'workspaceIdentity': workspaceIdentity,
        'provider': provider,
      }
    ]);
    if (resp.body is Map) return resp.body as Map<String, dynamic>;
    return {'raw': resp.body};
  }

  /// 启用/禁用技能 — skills/setEnabled
  Future<void> setSkillEnabled({
    required String workspacePath,
    required String skillId,
    required bool enabled,
    String? workspaceIdentity,
    String provider = 'glm',
    String? scope,
  }) async {
    await _rpcCall('skills', 'setEnabled', [
      {
        'workspacePath': workspacePath,
        if (workspaceIdentity != null && workspaceIdentity.isNotEmpty)
          'workspaceIdentity': workspaceIdentity,
        'provider': provider,
        'skillId': skillId,
        'enabled': enabled,
        if (scope != null) 'scope': scope,
      }
    ]);
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
    _rpcReadyController.close();
  }
}

/// RPC 调用异常
class RpcException implements Exception {
  final String message;
  RpcException(this.message);

  @override
  String toString() => 'RpcException: $message';
}
