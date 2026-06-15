// 独立 Relay 连接探针 — 脱离 App, 单连接只监听, 用于判断 KICKED 根因
//
// 用法: dart run tool/relay_probe.dart '<zcode 连接 URL>'
//
// 行为:
//   1. 解析 URL (sid/hash/mid/name)
//   2. HTTP GET 取 Set-Cookie
//   3. WebSocket 连 wss://zcode.z.ai/ws?mid=<mid>
//   4. 4 步 HMAC 认证 (auth_init → challenge → response → ack)
//   5. 连上后只监听 [duration] 秒, 不重连, 统计是否被 KICKED
//
// 握手逻辑严格复制自 lib/core/relay/relay_client.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

String _ts() => DateTime.now().toIso8601String();
void log(String m) => print('[$_ts] $m');

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty ? args.first : '';
  if (url.isEmpty) {
    print('用法: dart run tool/relay_probe.dart "<zcode 连接 URL>"');
    exit(1);
  }
  const durationSec = 45;

  final uri = Uri.parse(url);
  final sid = uri.queryParameters['sid'] ?? '';
  final hashDecoded = Uri.decodeComponent(uri.queryParameters['hash'] ?? '');
  final mid = uri.queryParameters['mid'] ?? '';
  final name = uri.queryParameters['name'] ?? 'mobile-browser';
  final appVersion = uri.queryParameters['app_version'] ?? '3.0.1';

  if (sid.isEmpty || hashDecoded.isEmpty || mid.isEmpty) {
    log('URL 缺少 sid/hash/mid 参数');
    exit(1);
  }
  log('解析: mid=$mid sid=$sid name=$name');

  // 1. 取 cookie
  log('HTTP GET 取 Cookie ...');
  final cookie = await _fetchCookie(url);
  if (cookie.isEmpty) {
    log('服务器未返回 Cookie, 中止');
    exit(1);
  }
  log('拿到 Cookie (长度 ${cookie.length})');

  // 2. WebSocket 连接
  final wsUrl = 'wss://zcode.z.ai/ws?mid=$mid';
  log('WebSocket 连接 $wsUrl ...');
  final sock = await WebSocket.connect(
    wsUrl,
    headers: {
      'Cookie': cookie,
      'Origin': 'https://zcode.z.ai',
      'User-Agent': 'Mozilla/5.0',
    },
  );
  log('WebSocket 已连接');

  var authenticated = false;
  var kicked = 0;
  var errors = 0;
  var dataFrames = 0;
  final connectedAt = DateTime.now();
  final done = Completer<void>();

  final sub = sock.listen(
    (raw) {
      if (raw is! String) return;
      Map<String, dynamic> msg;
      try {
        msg = jsonDecode(raw) as Map<String, dynamic>;
      } catch (_) {
        return;
      }
      final type = msg['type'] as String?;
      switch (type) {
        case 'auth_challenge':
          final nonce = msg['nonce'] as String;
          final dataStr = '$nonce|terminal|$sid';
          final hmac = crypto.Hmac(crypto.sha256, utf8.encode(hashDecoded));
          final proof = base64Url
              .encode(hmac.convert(utf8.encode(dataStr)).bytes)
              .replaceAll('=', '');
          _send(sock, {
            'type': 'auth_response',
            'device_sid': sid,
            'proof': proof,
            'client_ts': DateTime.now().millisecondsSinceEpoch,
          });
          log('收到 auth_challenge → 已回 auth_response');
        case 'auth_ack':
          final pair = msg['pair_status'];
          authenticated = pair == 'matched';
          log('auth_ack: pair_status=$pair terminal_sid=${msg['terminal_sid']} '
              '(认证${authenticated ? "成功" : "失败"})');
        case 'error':
          final code = msg['code'] ?? 'unknown';
          errors++;
          if (code.toString().toUpperCase().contains('KICK')) kicked++;
          log('!! 服务器 error: $code');
        case 'data':
          dataFrames++;
          final p = msg['payload'] as Map<String, dynamic>?;
          final zt = p?['zcode_type'];
          // 只打业务相关的 data 帧, 噪声不打
          if (zt == 'rpc-frame' || zt == 'workspace-bridge-open' || zt == 'bootstrap-request') {
            log('→ data [$zt]');
          }
        default:
          if (type != null) log('RECV [$type]');
      }
    },
    onError: (e) {
      log('stream onError: $e');
      if (!done.isCompleted) done.complete();
    },
    onDone: () {
      log('WebSocket 已关闭 (onDone)');
      if (!done.isCompleted) done.complete();
    },
    cancelOnError: true,
  );

  // 3. 发 auth_init
  _send(sock, {
    'type': 'auth_init',
    'role': 'terminal',
    'device_sid': sid,
    'meta': {'platform': 'web', 'version': appVersion, 'name': name},
    'client_ts': DateTime.now().millisecondsSinceEpoch,
  });
  log('已发 auth_init, 等待 $durationSec 秒观察 ...');

  // 4. 超时结束
  Timer(const Duration(seconds: durationSec), () {
    if (!done.isCompleted) {
      log('观察期结束');
      done.complete();
    }
  });

  await done.future;
  await sub.cancel();
  await sock.close();

  final uptime = DateTime.now().difference(connectedAt);
  log('══════════════ 结果 ══════════════');
  log('认证: ${authenticated ? "成功" : "未成功"}');
  log('连接存活: ${uptime.inSeconds} 秒 (观察期 $durationSec 秒)');
  log('被 KICKED 次数: $kicked');
  log('其他 error 次数: $errors');
  log('收到 data 帧数: $dataFrames');
  if (kicked > 0) {
    log('结论: 单连接也被服务器 KICKED → 不是 App 多开, 而是凭据/服务端单终端策略。');
  } else if (uptime.inSeconds >= durationSec - 1 && authenticated) {
    log('结论: 单连接全程稳定未被踢 → App 里被踢是因为有其它客户端(浏览器)竞争同一 device。');
  } else {
    log('结论: 连接提前关闭但非 KICKED, 需看上面的关闭原因。');
  }
  exit(0);
}

void _send(WebSocket sock, Map<String, dynamic> msg) {
  sock.add(jsonEncode(msg));
}

Future<String> _fetchCookie(String urlString) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(Uri.parse(urlString));
    req.headers.set('user-agent', 'Mozilla/5.0');
    final res = await req.close();
    await res.drain<void>();
    final cookies = <String>[];
    for (final h in res.headers[HttpHeaders.setCookieHeader] ?? <String>[]) {
      final part = h.split(';').first.trim();
      if (part.isNotEmpty) cookies.add(part);
    }
    return cookies.join('; ');
  } finally {
    client.close(force: true);
  }
}
