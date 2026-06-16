import 'dart:convert';

import 'package:hive/hive.dart';

import '../../providers/chat_provider.dart';

/// 消息本地缓存 (离线可见优化, 非数据源)
///
/// 用 Hive 存储每个 task 的消息列表 (精简 JSON 字符串)。
/// key = taskId, value = jsonEncode(List<Map>) (每条含
/// id/role/content/thought/model/createdAt 的 millisecondsSinceEpoch)。
///
/// 简洁起见: 一个 JSON 字符串存一个 task 的全部消息, 不注册 Hive adapter。
class MessageCache {
  static const _boxName = 'message_cache';

  static Box<String>? _box;

  MessageCache._();

  /// 初始化缓存 box (应用启动时调用一次)。
  /// 必须先 await Hive.initFlutter() / Hive.init()。
  static Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<String>(_boxName);
  }

  static Box<String> get _safeBox {
    final box = _box;
    if (box == null || !box.isOpen) {
      throw StateError('MessageCache 未初始化, 请先调用 MessageCache.init()');
    }
    return box;
  }

  /// 缓存一个 task 的消息列表 (覆盖式写入)。
  static Future<void> saveMessages(
    String taskId,
    List<DisplayMessage> messages,
  ) async {
    try {
      final encoded = jsonEncode(
        messages
            .where((m) => !m.isStreaming) // 不缓存正在流式生成的临时消息
            .map(_toJson)
            .toList(),
      );
      await _safeBox.put(taskId, encoded);
    } catch (e) {
      // 缓存只是体验优化, 任何失败都不应影响主流程
      assert(() {
        // ignore: avoid_print
        print('[MessageCache] saveMessages 失败: $e');
        return true;
      }());
    }
  }

  /// 读取一个 task 的缓存消息 (无缓存或解析失败返回空列表)。
  static List<DisplayMessage> loadMessages(String taskId) {
    try {
      final raw = _safeBox.get(taskId);
      if (raw == null || raw.isEmpty) return const [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[MessageCache] loadMessages 失败: $e');
        return true;
      }());
      return const [];
    }
  }

  /// 清除单个 task 的缓存。
  static Future<void> clearTask(String taskId) async {
    try {
      await _safeBox.delete(taskId);
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[MessageCache] clearTask 失败: $e');
        return true;
      }());
    }
  }

  /// 清空全部缓存。
  static Future<void> clearAll() async {
    try {
      await _safeBox.clear();
    } catch (e) {
      assert(() {
        // ignore: avoid_print
        print('[MessageCache] clearAll 失败: $e');
        return true;
      }());
    }
  }

  // ------------------------------ 序列化 ------------------------------

  /// DisplayMessage -> 精简 JSON Map。
  /// 注意: 不修改 DisplayMessage 类, 这里手工挑选字段。
  static Map<String, dynamic> _toJson(DisplayMessage m) => {
        'id': m.id,
        'role': m.role,
        'content': m.content,
        if (m.thought != null) 'thought': m.thought,
        if (m.model != null) 'model': m.model,
        'createdAt': m.createdAt.millisecondsSinceEpoch,
      };

  /// 精简 JSON Map -> DisplayMessage (仅恢复展示所需字段;
  /// activities 等运行时态不还原, 它们会随网络历史重新加载)。
  static DisplayMessage _fromJson(Map<String, dynamic> json) {
    final createdAt = json['createdAt'];
    return DisplayMessage(
      id: json['id'] as String? ?? '',
      role: json['role'] as String? ?? 'assistant',
      content: json['content'] as String? ?? '',
      thought: json['thought'] as String?,
      model: json['model'] as String?,
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null,
    );
  }
}
