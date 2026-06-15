import 'package:flutter/material.dart';

/// ZCode 设计令牌 (Design Tokens)
///
/// 集中管理所有视觉常量, 避免在组件里散落硬编码。
/// 设计方向: 开发者工具气质 — 精确、密度友好、代码优先、电光蓝强调。
///
/// 所有间距/圆角/字号都从这里取, 不在组件里写魔法数字。

class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

class AppRadius {
  AppRadius._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;
}

/// 移动端触摸目标 (Apple HIG: 最小 44pt)
class AppTouch {
  AppTouch._();
  static const double min = 44;
  static const double comfortable = 48;
}

/// ZCode 品牌色板
///
/// 不用 Material 默认 fromSeed 的 muddy 色, 手调一套精确的深色优先配色。
/// 主强调: 电光蓝 (比默认 #0066FF 更亮更冷, 在深色背景上有冲击力)
class AppColors {
  AppColors._();

  // ── 强调色 (亮暗共用) ──
  /// 电光蓝 — 主强调, 用于按钮/链接/激活态
  static const Color accent = Color(0xFF3B82F6);
  /// 强调悬浮态 (略亮)
  static const Color accentHover = Color(0xFF60A5FA);
  /// 强调按下态 (略暗)
  static const Color accentPressed = Color(0xFF2563EB);
  /// 强调容器背景 (低透明)
  static const Color accentContainer = Color(0x1F3B82F6);

  // ── 状态色 ──
  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);

  // ── 深色主题 (主场, 采纳 Linear 深色质感) ──
  //
  // 核心原则 (Linear): 深色表面用半透明白叠加, 不用实色;
  // 边框用半透明白, 不用实色灰。这样在深色上有空气感。
  static const Color darkBg = Color(0xFF08090A);            // 最底层 (Linear marketing black)

  /// 卡片/面板: 半透明白 0.03 (Linear surface)
  static const Color darkSurface = Color(0x08FFFFFF);       // rgba(255,255,255,0.03)
  /// 高亮面: 半透明白 0.06 (Linear elevated)
  static const Color darkSurfaceHigh = Color(0x10FFFFFF);   // rgba(255,255,255,0.06)
  /// 最高面: 半透明白 0.09 (Linear hover)
  static const Color darkSurfaceHighest = Color(0x17FFFFFF); // rgba(255,255,255,0.09)

  /// 边框: 半透明白 (Linear border standard)
  static const Color darkBorder = Color(0x14FFFFFF);        // rgba(255,255,255,0.08)
  /// 细边框: 半透明白 0.05 (Linear subtle)
  static const Color darkBorderSubtle = Color(0x0DFFFFFF);  // rgba(255,255,255,0.05)

  // 文字 (采纳 Apple alpha 标签体系: 在任何背景上自适应)
  // Apple dark: rgba(235,235,245, alpha) — 微冷白带 alpha
  static const Color darkInk = Color(0xFFF7F8F8);              // 主文字 (近白)
  static const Color darkInkSecondary = Color(0x99EBEBF5);     // 次要 (alpha 0.60)
  static const Color darkInkMuted = Color(0x4DEBEBF5);         // 弱 (alpha 0.30)
  static const Color darkInkSubtle = Color(0x2EEBEBF5);        // 最弱 (alpha 0.18)

  // ── 浅色主题 ──
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceHigh = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightInk = Color(0xFF000000);
  // Apple light labels: rgba(60,60,67, alpha)
  static const Color lightInkSecondary = Color(0x993C3C43);   // alpha 0.60
  static const Color lightInkMuted = Color(0x4D3C3C43);       // alpha 0.30
  static const Color lightInkSubtle = Color(0x2E3C3C43);      // alpha 0.18
}

/// 等宽字体族名 (代码/路径/ID/taskId)
const String kMonoFont = 'JetBrains Mono';
/// UI 字体族名
const String kUiFont = 'Inter';

/// 代码/路径/ID 文本样式快捷构造
class AppText {
  AppText._();

  /// 等宽代码样式 (深色适配)
  static TextStyle mono(BuildContext context, {
    double size = 13,
    Color? color,
    FontWeight weight = FontWeight.w400,
  }) {
    return TextStyle(
      fontFamily: kMonoFont,
      fontFamilyFallback: const ['monospace'],
      fontSize: size,
      fontWeight: weight,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      height: 1.5,
    );
  }
}
