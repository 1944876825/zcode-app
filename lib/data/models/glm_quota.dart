/// GLM Coding Plan 余量查询结果模型
///
/// 移植自 cc-switch `src-tauri/src/services/coding_plan.rs` 的智谱 GLM 段:
/// - tool 固定为 'coding_plan'
/// - tiers 最多 2 条 (five_hour / weekly_limit)
/// - 解析层不做范围裁剪, utilization 可能负 / 超 100, 原样透传给 UI 层
class GlmQuota {
  final bool success;
  final GlmCredentialStatus credentialStatus;
  final String? credentialMessage; // data.level (套餐等级)
  final List<GlmQuotaTier> tiers;
  final String? error;
  final int? queriedAt; // ms

  const GlmQuota({
    required this.success,
    required this.credentialStatus,
    this.credentialMessage,
    this.tiers = const [],
    this.error,
    this.queriedAt,
  });

  GlmQuota copyWith({
    bool? success,
    GlmCredentialStatus? credentialStatus,
    String? credentialMessage,
    List<GlmQuotaTier>? tiers,
    String? error,
    int? queriedAt,
  }) {
    return GlmQuota(
      success: success ?? this.success,
      credentialStatus: credentialStatus ?? this.credentialStatus,
      credentialMessage: credentialMessage ?? this.credentialMessage,
      tiers: tiers ?? this.tiers,
      error: error ?? this.error,
      queriedAt: queriedAt ?? this.queriedAt,
    );
  }

  /// 5 小时窗口 tier (可能为 null: 老套餐或未返回)
  GlmQuotaTier? get fiveHourTier {
    for (final t in tiers) {
      if (t.name == GlmQuotaTier.fiveHour) return t;
    }
    return null;
  }

  /// 每周窗口 tier (可能为 null)
  GlmQuotaTier? get weeklyTier {
    for (final t in tiers) {
      if (t.name == GlmQuotaTier.weeklyLimit) return t;
    }
    return null;
  }

  /// 是否有可渲染的数据 (至少一条 tier 且无错误)
  bool get hasData => success && tiers.isNotEmpty;
}

/// 一条限额 tier
class GlmQuotaTier {
  static const fiveHour = 'five_hour';
  static const weeklyLimit = 'weekly_limit';

  /// 窗口名 (GlmQuotaTier.fiveHour / GlmQuotaTier.weeklyLimit)
  final String name;
  /// 已用百分比 (0-100, 解析层不裁剪)
  final double utilization;
  /// 重置时间 (ISO 8601, 可空: 0% 状态可能无 reset)
  final String? resetsAt;

  const GlmQuotaTier({
    required this.name,
    required this.utilization,
    this.resetsAt,
  });
}

/// 凭据状态 (对齐 cc-switch CredentialStatus)
enum GlmCredentialStatus {
  valid,
  expired,
  notFound,
}
