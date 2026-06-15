import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/zcode_session.dart';

/// 安全存储 — 管理 session/token 的持久化
class SecureStorageService {
  final FlutterSecureStorage _secure;

  static const _keySession = 'zcode_session';
  static const _keyDeviceId = 'zcode_device_id';

  SecureStorageService([FlutterSecureStorage? storage])
      : _secure = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// 保存会话
  Future<void> saveSession(ZcodeSession session) async {
    final json = jsonEncode(session.toJson());
    await _secure.write(key: _keySession, value: json);
  }

  /// 读取会话
  Future<ZcodeSession?> getSession() async {
    final json = await _secure.read(key: _keySession);
    if (json == null) return null;
    try {
      return ZcodeSession.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 清除会话
  Future<void> clearSession() async {
    await _secure.delete(key: _keySession);
  }

  /// 获取或生成设备 ID
  Future<String> getOrCreateDeviceId() async {
    var id = await _secure.read(key: _keyDeviceId);
    if (id == null || id.isEmpty) {
      // 生成简单设备 ID
      final ts = DateTime.now().millisecondsSinceEpoch;
      final rand = DateTime.now().microsecond;
      id = '${ts.toRadixString(36)}${rand.toRadixString(36)}';
      await _secure.write(key: _keyDeviceId, value: id);
    }
    return id;
  }
}

/// 偏好设置存储
class PreferencesService {
  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String get themeMode => _prefs.getString('themeMode') ?? 'system';

  set themeMode(String mode) => _prefs.setString('themeMode', mode);

  String get defaultModel => _prefs.getString('defaultModel') ?? 'GLM-5.2';

  set defaultModel(String model) => _prefs.setString('defaultModel', model);

  String get defaultMode => _prefs.getString('defaultMode') ?? 'confirm';

  set defaultMode(String mode) => _prefs.setString('defaultMode', mode);

  bool get organizeByWorkspace =>
      _prefs.getBool('organizeByWorkspace') ?? true;

  set organizeByWorkspace(bool v) => _prefs.setBool('organizeByWorkspace', v);
}
