import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// 语音输入服务 (设备端 STT)
///
/// 基于 speech_to_text 包, 调用系统自带的语音识别 (Android: Google, iOS: 苹果)。
/// 中文识别质量取决于设备引擎, 免服务器、零 API 成本。
///
/// 用法 (按住说话模式):
///   1. startListening(onResult) — 开始监听, 实时回调识别结果
///   2. stopListening() — 停止, 触发最终结果
class VoiceInputService {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  bool _listening = false;

  bool get isAvailable => _available;
  bool get isListening => _listening;

  /// 当前累积的识别文本 (实时更新)
  String _currentText = '';
  String get currentText => _currentText;

  /// 初始化 (检查权限 + 引擎可用性)
  ///
  /// 在没有 Google 语音服务的设备 (如部分 OPPO/华为/小米海外 ROM) 上,
  /// speech_to_text.initialize 会抛 PlatformException(recognizerNotAvailable)。
  /// 这里捕获并返回 false, 让 UI 层把按钮隐藏掉。
  Future<bool> init() async {
    try {
      _available = await _speech.initialize(
        onError: (SpeechRecognitionError error) {
          _listening = false;
        },
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            _listening = false;
          }
        },
      );
    } catch (e) {
      // PlatformException(recognizerNotAvailable, ...) 等
      debugPrint('[Voice] init 失败, 设备无语音识别服务: $e');
      _available = false;
    }
    return _available;
  }

  /// 开始监听 (按住说话时调用)
  ///
  /// [onResult] 实时回调, 每识别出一个词就触发。
  /// finalResult=true 表示该结果是最终结果 (用户停顿后)。
  Future<void> startListening({
    required void Function(String text, bool isFinal) onResult,
    String localeId = 'zh-CN',
  }) async {
    if (!_available || _listening) return;
    _currentText = '';
    _listening = true;
    await _speech.listen(
      onResult: (result) {
        _currentText = result.recognizedWords;
        onResult(result.recognizedWords, result.finalResult);
      },
      localeId: localeId,
      listenMode: ListenMode.dictation,
      cancelOnError: true,
      partialResults: true,
    );
  }

  /// 停止监听 (松开时调用)
  Future<String> stopListening() async {
    if (!_listening) return _currentText;
    await _speech.stop();
    _listening = false;
    return _currentText;
  }

  /// 取消 (放弃本次识别)
  Future<void> cancel() async {
    await _speech.cancel();
    _listening = false;
    _currentText = '';
  }

  /// 获取可用的语言列表 (用于语言切换 UI)
  Future<List<LocaleName>> locales() async {
    return _speech.locales();
  }

  void dispose() {
    _speech.cancel();
  }
}
