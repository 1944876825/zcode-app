# ZCode App — UI 优化清单

> 生成时间: 2026-06-16
> 状态: 待处理

---

## 🔴 高优先级（影响体验）

### 1. AI 气泡硬编码深色 → theme-aware
- **位置**: `chat_screen.dart` `_MessageBubble` line ~1819-1823
- **问题**: `aiBg=#1F2024`、`aiInk=#E8EAED` 写死，注释说"强制深色"，但 app 已支持浅色/系统主题切换。切浅色模式 AI 气泡还是黑底白字
- **方案**: 用 `Theme.of(context).brightness` 判断，深色用现有色值，浅色用 `surfaceContainerHigh` + `onSurface`

### 2. HistoryDrawer 搜索框 dark tokens → theme-aware
- **位置**: `chat_screen.dart` `_HistoryDrawer._buildSearchField()` line ~2775-2785
- **问题**: 用 `AppColors.darkSurfaceHigh`、`AppColors.darkBorderSubtle` 等硬编码深色 token，浅色模式不适配
- **方案**: 改用 `theme.colorScheme.surfaceContainerHigh` / `theme.colorScheme.outlineVariant`

### 3. 工具栏窄屏溢出
- **位置**: `chat_screen.dart` `_buildInputArea()` line ~478-536
- **问题**: 底部一行塞了 🎤语音 + 模式选择器 + Spacer + 质量 + 模型选择器，窄屏挤压
- **方案**: 用 `SingleChildScrollView(scrollDirection: horizontal)` 包裹，或去掉质量占位（当前只是 SnackBar）

---

## 🟡 中优先级（视觉提升）

### 4. 消息无时间戳/日期分组
- **位置**: `chat_screen.dart` `_MessageBubble` / `ListView.builder`
- **问题**: 长对话难定位，缺 "今天"/"昨天" 分隔线
- **方案**: ListView itemBuilder 里判断 `msg.createdAt` 日期变化时插入 `_DateSeparator` widget；气泡底部加时间戳 (灰色 11pt)

### 5. 消息无头像
- **位置**: `chat_screen.dart` `_MessageBubble`
- **问题**: AI 和用户消息都无标识，辨识度低
- **方案**: 用户→`Icons.person` 圆形头像；AI→`Icons.auto_awesome` 或 app logo，28pt 圆形

### 6. 加载只有转圈圈 → 骨架屏
- **位置**: `chat_screen.dart` line ~276-277（历史加载）；`workspace_list_screen.dart` line ~100
- **问题**: 只有 `CircularProgressIndicator`
- **方案**: 替换为 shimmer 骨架屏（模拟消息气泡形状 / 工作区卡片形状）

### 7. 技能 Tab 空壳
- **位置**: `main_screen.dart` `_buildSkillsTab()`
- **问题**: 只有图标+文字"即将上线"
- **方案**: 至少做一个好看的占位页（插画 + 功能预告卡片）

### 8. 工作区列表空状态
- **位置**: `workspace_list_screen.dart` `_buildEmpty()`
- **问题**: 居中图标+两行文字，缺乏引导性
- **方案**: 加引导按钮（"刷新"）、步骤说明（"在 ZCode 桌面端创建项目 → 扫码连接"）

---

## 🟢 低优先级（打磨细节）

### 9. 返回箭头风格
- **位置**: `chat_screen.dart` line ~186
- **问题**: `Icons.arrow_back` → 更现代的 `Icons.arrow_back_rounded` 或 `arrow_back_ios`
- **方案**: 全局替换

### 10. 设置页 deviceSid 显示
- **位置**: `settings_screen.dart` line ~63
- **问题**: 直接显示十六进制 `deviceSid`，用户看不懂
- **方案**: 已有 `deviceName` 显示在上方，下方改显示 "设备 ID: xxxx" (截断前8位) 或直接去掉

### 11. 分享按钮空实现
- **位置**: `chat_screen.dart` `_showMessageMenu()` line ~1941-1948
- **问题**: 点击"分享"什么都不做（注释写了 share_plus 未来加）
- **方案**: 添加 `share_plus` 依赖 → `Share.share(message.content)`

---

## 实施顺序建议
1. 先修 #1 + #2（功能 bug，浅色主题不可用）
2. 再做 #5 + #4（头像 + 时间戳，视觉提升最大）
3. 然后 #3 + #11（工具栏 + 分享）
4. 最后 #6-#10 一起批量打磨
