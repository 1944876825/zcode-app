/// ZCode 应用配置常量
class AppConfig {
  AppConfig._();

  /// Relay 服务器地址
  static const String relayOrigin = 'https://zcode.z.ai';

  /// WebSocket 基础地址
  static const String wsBaseUrl = 'wss://zcode.z.ai';

  /// OAuth 端点
  static const String oauthEndpoint = '/api/v1/oauth/token';

  /// Remote Control API 前缀
  static const String remoteControlApiPrefix = '/api/remote-control';

  /// 应用版本
  static const String appVersion = '1.0.0';

  /// WebView 登录页路径
  static const String webRemotePath = '/web-remote';

  /// 安全存储的 key
  static const String keySession = 'zcode_session';
  static const String keyRemoteControlToken = 'zcode_rtc_token';
  static const String keyRelayOrigin = 'zcode_relay_origin';
  static const String keyDeviceId = 'zcode_device_id';
}
