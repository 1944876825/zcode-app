import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/voice/voice_input_service.dart';
import '../theme/app_design_tokens.dart';

/// 语音输入按钮 (点击开始/再点击结束, 长按也可)
///
/// 交互:
///   - 点击: 开始录音 → 再点击结束 → 转文字填入输入框
///   - 长按: 按住说话 → 松开结束 (备用)
///   - 录音中按钮变红 + 脉冲动画 + 实时文字提示
///   - 设备不支持时自动隐藏
class VoiceInputButton extends StatefulWidget {
  final VoiceInputService service;
  final ValueChanged<String> onTranscribed; // 识别完成回调
  final double size;

  const VoiceInputButton({
    super.key,
    required this.service,
    required this.onTranscribed,
    this.size = AppTouch.min,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton> {
  bool _recording = false;
  String _partialText = '';
  /// null=未检测, true=可用, false=不可用
  bool? _available;

  @override
  void initState() {
    super.initState();
    _checkAvailability();
  }

  Future<void> _checkAvailability() async {
    // service 已缓存过 init 结果 → 同步取值, 避免异步空帧导致按钮闪烁
    if (widget.service.isInitialized) {
      if (mounted) setState(() => _available = widget.service.isAvailable);
      return;
    }
    bool ok;
    try {
      ok = await widget.service.init();
    } catch (e) {
      debugPrint('[Voice] _checkAvailability 异常: $e');
      ok = false;
    }
    if (mounted) setState(() => _available = ok);
  }

  /// 开始录音
  Future<void> _startRecording() async {
    if (!widget.service.isAvailable) return;
    if (widget.service.isListening) return; // 已在录
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _partialText = '';
    });
    try {
      await widget.service.startListening(
        onResult: (text, isFinal) {
          if (mounted) setState(() => _partialText = text);
        },
      );
    } catch (e) {
      debugPrint('[Voice] startListening error: $e');
      if (mounted) {
        setState(() => _recording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('语音识别出错: $e'), duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  /// 结束录音 → 转文字
  Future<void> _stopRecording() async {
    if (!_recording) return;
    HapticFeedback.selectionClick();
    final text = await widget.service.stopListening();
    setState(() => _recording = false);
    if (text.isNotEmpty) {
      widget.onTranscribed(text);
    }
  }

  /// 点击: 切换录音状态 (开始 ↔ 结束)
  Future<void> _toggle() async {
    debugPrint('[Voice] _toggle, _recording=$_recording, available=$_available');
    // init 未完成或不可用 → 提示并退出
    if (_available != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前设备不支持语音识别 (缺少 Google 语音服务)'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 未检测完成或不可用 → 隐藏按钮
    if (_available == false) return const SizedBox.shrink();

    return InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(widget.size / 2),
      customBorder: const CircleBorder(),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // 主按钮 (麦克风/停止 图标)
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              color: _recording
                  ? AppColors.danger.withValues(alpha: 0.15)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              _recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: 20,
              color: _recording
                  ? AppColors.danger
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          // 录音中的脉冲圈
          if (_recording)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1.0, end: 1.6),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOut,
                builder: (_, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.5),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          // 录音中提示气泡 (实时识别文字 / 引导)
          if (_recording)
            Positioned(
              bottom: widget.size + 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  _partialText.isEmpty ? '正在聆听...' : _partialText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
