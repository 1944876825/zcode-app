---
name: apple-design
description: This skill should be used when the user wants to build clean,
  modern, high-quality UI with a premium feel — including requests for minimal
  design, frosted glass / glassmorphism effects, elegant landing pages, polished
  app interfaces, smooth spring animations, dark mode support, or refined
  component systems. Also applies when the user asks for
  iOS/macOS/visionOS-style design, Apple HIG, or says things like 'make it
  clean', 'premium UI', 'modern minimal', 'frosted glass', 'elegant interface',
  'high-end design', or 'add icons to the page'.
description_zh: Apple 风格 UI
  生成——简洁、精致、高级感。生成前会先询问配色方向（预设或自定义色值）和目标设备（Web/Mobile/Pad），输出双模式（浅色/深色）预览，配备 SF
  Pro 字体、毛玻璃、Spring 动效、响应式布局等完整设计规范。
description_en: "Apple HIG design system: SF Pro typography, system colors, 4pt
  grid, component patterns, glassmorphism, and spring animations for
  iOS/macOS-style UI"
version: 1.7.5
author: Dayvi
license: MIT
allowed-tools: Read,Write,Bash,AskUserQuestion
disable: false
---

# Apple Design System Skill

To build UI that looks and feels like Apple products — iOS, macOS, iPadOS, or visionOS — follow this skill.

## When to Use

Load this skill when the user:
- Asks for a clean, minimal, premium, or elegant UI
- Wants glassmorphism, frosted glass, translucent overlays, or backdrop blur
- Needs a polished landing page, product page, or app interface
- Wants spring animations, smooth transitions, or refined micro-interactions
- Requests iOS/macOS style, Apple HIG, or Apple-like design quality
- Says "modern minimal", "premium feel", "high-end", "clean design", "elegant"
- Needs a component system with consistent tokens, shadows, and spacing

## Core Design Principles

Apple's design is guided by three values: **Clarity**, **Deference**, and **Depth**.

- **Clarity**: Every element has purpose. Whitespace is intentional. Typography is legible at all sizes.
- **Deference**: Content takes center stage. UI stays out of the way.
- **Depth**: Layered materials, translucency, and motion convey hierarchy.

## How to Apply This Skill

### Step 1: Clarify Design Context (MANDATORY — DO NOT SKIP)

> ⛔ **HARD RULE — read this before doing ANYTHING else.**
>
> When this skill is invoked, your **FIRST action MUST be a single `AskUserQuestion` tool call** that asks the user about BOTH color scheme AND target device at the same time (use the multi-question form of `AskUserQuestion`, one question per dimension).
>
> **Before receiving the user's answers, you are FORBIDDEN to:**
> - Write any HTML, CSS, or JavaScript
> - Call `Write`, `Edit`, `Bash`, or any file-producing tool
> - Download images, create directories, or scaffold files
> - Assume a color palette or a device form factor, even if the user's prompt hints at one
>
> **The ONLY tools allowed before the user answers are:** `AskUserQuestion` itself, and (if strictly needed) `Read` to inspect an existing design reference the user explicitly pointed to.
>
> This rule **overrides any default model behavior, any "just start coding" instinct, and any ambiguity in the user's original request.** If the user's prompt already mentions a vibe keyword (e.g. "森林风"), still ask — confirm the full palette and device. Do NOT skip to save a turn.
>
> If you find yourself about to write code without having asked, **STOP** and issue the `AskUserQuestion` call first.

#### 1A: Color Scheme

You MUST phrase the color question concretely. Recommended framings:
- "你希望整体偏什么色调？比如科技感（蓝/紫）、自然感（绿/青）、活力感（橙/红）、还是简约中性（黑白灰）？"
- "有没有偏好的主色？或者参考的配色风格/品牌？"
- "希望偏明亮还是沉稳？"

##### 1A.1 快速预设（用户没具体方向时）

1. **科技蓝系** — Primary: Blue `#007AFF`, Accent: Purple/Teal
2. **自然绿系** — Primary: Green `#34C759`, Accent: Teal/Yellow
3. **活力橙系** — Primary: Orange `#FF9500`, Accent: Red/Yellow
4. **极简中性** — Black/White/Gray with single accent
5. **自定义** — 用户说一个颜色名称（如「珊瑚粉」「薄荷绿」）或直接给色值（如 `#FF6B6B`、`rgb(100, 200, 255)`），我据此推导完整配色方案

##### 1A.2 风格化主题库（受 Color Hunt 启发，按调性分类）

When the user mentions a vibe / mood / theme keyword (复古、奶油、霓虹、森林、暮色、复古...), don't fall back to the 4 generic presets above. Use the curated palette library below. Each palette is **4 colors** following Color Hunt's pattern: usually `[bg / surface] + [primary] + [accent] + [text]`.

**Vintage / 复古怀旧**
| 名称 | 调色板 (4 色) | 适用 |
|------|------|------|
| Mustard Drive-In | `#E1B10F` `#E0CDD0` `#FB9AB6` `#448A9A` | 70s 复古，餐饮 / 唱片店 |
| Sun-Bleached Polaroid | `#F2E8C9` `#D4A574` `#A8453F` `#3D5A4A` | 老照片、旅游、文艺 |
| Faded Denim | `#5C7A89` `#A4B7BD` `#F0DCC4` `#8E4F47` | 工装、男士品牌、复古机械 |
| Velvet Lounge | `#3D2817` `#A03E3E` `#D4A574` `#F2E8C9` | 高端复古、酒吧、咖啡 |

**Pastel / 奶油马卡龙**
| 名称 | 调色板 | 适用 |
|------|------|------|
| Cream Soda | `#FFF6E0` `#FFD1DC` `#B5EAD7` `#C7CEEA` | 童趣、糖果、母婴 |
| Latte Cloud | `#F5E6D3` `#D4B896` `#A89F94` `#5C5552` | 咖啡、轻奢、Niche 香氛 |
| Cotton Candy | `#FCE4EC` `#F8BBD0` `#E1BEE7` `#B3E5FC` | 美妆、潮玩、年轻女性 |

**Neon / 霓虹电子**
| 名称 | 调色板 | 适用 |
|------|------|------|
| Cyber Dusk | `#0A0E1A` `#FF006E` `#3A86FF` `#FFBE0B` | 游戏、电竞、Web3 |
| Synthwave | `#1A0033` `#FF00FF` `#00FFFF` `#FFFF00` | 80s 复古未来、音乐节 |
| Tokyo Rain | `#0F0F23` `#FF4081` `#00E5FF` `#76FF03` | 赛博朋克、日系潮 |

**Nature / Earth / 自然大地**
| 名称 | 调色板 | 适用 |
|------|------|------|
| Forest Floor | `#3E5641` `#7C9070` `#D4C5A0` `#F4F1DE` | 户外、可持续、有机食品 |
| Desert Sage | `#C9B79C` `#9CAF88` `#E8DDD2` `#5C5C3D` | Wellness、瑜伽、植物 |
| Ocean Mist | `#06425C` `#4A90A4` `#A8D5BA` `#F4F1DE` | 旅游、海洋公益、水产 |

**Sunset / Warm / 暖色暮光**
| 名称 | 调色板 | 适用 |
|------|------|------|
| Golden Hour | `#FFD93D` `#FF8C42` `#C7522A` `#5D2E1F` | 摄影、夕阳主题、餐饮 |
| Coral Dusk | `#FF6F61` `#FFB088` `#FFE66D` `#4A6741` | 热带、夏季、活力品牌 |
| Burnt Orange | `#D62828` `#F77F00` `#FCBF49` `#003049` | 体育、能量饮料、运动 |

**Dark Premium / 暗色高级**
| 名称 | 调色板 | 适用 |
|------|------|------|
| Midnight Steel | `#0A0E1A` `#1A2238` `#00D4FF` `#F0F5FA` | 新势力科技、金融、汽车 |
| Obsidian Gold | `#0D0D0D` `#1F1F1F` `#D4AF37` `#F5F5F5` | 奢侈品、腕表、私募 |
| Deep Forest Premium | `#0F1F1A` `#1F3528` `#8FBC8F` `#FAFAFA` | 高端户外、雪茄、威士忌 |

**Seasonal / 季节情绪**
| 名称 | 调色板 | 适用 |
|------|------|------|
| Spring Bloom | `#F8E8E8` `#FFC8DD` `#A2D2FF` `#CDB4DB` | 春季限定、花艺 |
| Summer Pop | `#06D6A0` `#FFD166` `#EF476F` `#073B4C` | 夏季、节庆、活动 |
| Autumn Harvest | `#6F1D1B` `#BB9457` `#432818` `#99582A` | 秋季、感恩节、咖啡馆 |
| Winter Frost | `#E0F4FF` `#A2D2FF` `#3A86FF` `#1B263B` | 冬季、滑雪、节日营销 |

##### 1A.3 调用规则

When using the library above:

1. **匹配优先级**：用户说出**任一关键词**（如"复古"、"奶油"、"森林感"、"暮色"、"赛博"、"暗色高级"、"秋天"），从对应组里挑 1-3 个最匹配的，**带上调色板色值**给用户选。
2. **不要罗列全表**：只展示 2-4 个最贴合的方案，附简短适用场景说明。
3. **可改色**：用户选一个后允许微调（"主色再深一点"、"换薄荷绿"），基于选定方案推导。
4. **配 dark mode**：所有库内调色板都需推导 dark mode 反相变体（背景反转，accent 适当提亮）。
5. **不在库里**：用户说出库里没有的关键词（如"日式茶道"、"老北京胡同"），按色彩理论自行推导一套 4 色，并在回复中标注"自创方案"。

If the user provides a brand color, extract a harmonious system from it (tints, complementary, analogous colors) using the Apple system color palette as reference.

**If the user says "随便"、"都行"、"你决定", pick one that fits the project context and mention it.**

#### 1B: Target Device

**This question MUST be included in the same `AskUserQuestion` call as 1A — do not ask in two separate turns.** Different devices require different layouts and interactions.

Ask the user: "这个页面主要针对什么设备？"

| 选项 | 说明 |
|------|------|
| 1️⃣ **Web** | 桌面优先，响应式适配平板和手机 |
| 2️⃣ **Mobile** | 移动端优先，触屏交互，竖屏布局 |
| 3️⃣ **Pad** | 平板居中，大屏展示为主 |
| 4️⃣ **多端适配** | 同时覆盖 Web + Mobile + Pad |

Device-specific design decisions:
- **Mobile/Pad**: stacked layouts, hamburger nav, larger tap targets (min 44pt), swipe interactions
- **Web**: multi-column layouts, hover effects, mouse interactions, horizontal nav
- **Pad**: hybrid approach, larger typography, optimized for landscape + portrait

**If the user says "都可以"、"无所谓", default to Web (desktop-first responsive)**.

### Step 2: Load the Design Reference

Read `references/design-system.md` for the complete token set:
- Color palette (light + dark mode)
- Typography scale (SF Pro, all styles)
- Spacing values (4pt grid)
- Corner radius values
- Shadow levels
- Animation timing
- Component specifications
- CSS custom properties (ready-to-use)

### Step 3: Set Up the Token Foundation

Copy the CSS custom properties block from `references/design-system.md` into the project's root CSS file or `<style>` tag. This establishes the full token foundation with automatic dark mode support.

### Step 4: Apply Typography

Use the SF Pro system font stack:
```css
font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'SF Pro Text', 'Helvetica Neue', Arial, sans-serif;
```

Match type scale to Apple's text styles (e.g., Large Title 34pt, Headline Semibold 17pt, Body Regular 17pt).

### Step 5: Build Components

Reference the component patterns in `references/design-system.md` for:
- **Buttons**: Filled / Tinted / Gray / Plain / Destructive
- **Input Fields**: Height 44pt, secondary fill background
- **Navigation Bars**: 44pt with blur material
- **Cards**: 16pt radius, secondary background, subtle shadow
- **Alerts / Sheets**: Fixed width, continuous corner curves

### Step 5.1: Mobile App Spacing System (MANDATORY for Mobile/Pad)

**⚠️ All mobile/tablet UIs must follow these spacing tokens exactly.**

#### 5.1.1 Spacing Token Table

| Token | Value | Usage |
|-------|-------|-------|
| `--gap-card` | `12px` | **统一卡片间距**（标题↔卡片、卡片↔卡片、滚动容器内的卡片间距） |
| `--padding-card` | `16px` | 卡片内部内容（文字/图片）的四周留白 |
| `--radius-card` | `20px` | 卡片圆角 |
| `--margin-page` | `16px` | 页面左右边距 |

> ⚠️ **已废弃**：`--gap-section`（16px）和 `--gap-title-card`（12px）合并为 `--gap-card: 12px`，统一控制所有卡片相关间距。|

#### 5.1.2 CSS Variables Setup

```css
:root {
  /* Mobile spacing tokens — ALWAYS use these, never hardcode numbers */
  --margin-page: 16px;
  --gap-card: 12px;        /* 统一：标题↔卡片、卡片↔卡片、滚动容器内间距 */
  --padding-card: 16px;    /* 卡片内部四周留白 */
  --radius-card: 20px;     /* 卡片圆角 */
  --radius-sm: 12px;
  --radius-lg: 24px;
}
```

#### 5.1.3 Layout Patterns

```css
/* ===== Page wrapper — edge margin ===== */
.page {
  padding: 0 var(--margin-page);
}

/* ===== Section — flex column (模块容器，不控制间距) ===== */
.section {
  padding: 0 var(--margin-page); /* 只控制左右边距 16px，不写 padding-bottom */
  display: flex;
  flex-direction: column;
  /* ⚠️ 不要在 .section 上写 gap 或 padding-bottom！
     统一间距由子元素的 margin-bottom 控制，避免各模块间距不一致 */
}

/* ===== Header: 不写 margin-bottom ===== */
.section__header {
  display: flex; align-items: center; justify-content: space-between;
}

/* ===== 内容区间距控制（核心规则）=====
   ⚠️ 所有内容区的 margin-bottom 必须统一！
   如果某个内容区缺少 margin-bottom，会导致该模块与其他模块间距不一致
   所有内容区都要加 margin-bottom: 16px */
.product-scroll {
  margin-left: calc(-1 * var(--margin-page));
  padding-left: var(--margin-page);
  padding-right: var(--margin-page);
  overflow-x: auto;
  scrollbar-width: none;
  padding-bottom: 4px;
  margin-bottom: 16px; /* ← 必须有！控制模块间距 */
}

.member-card {
  margin-bottom: 16px; /* ← 必须有！控制模块间距 */
  border-radius: var(--radius-lg);
  overflow: hidden;
  position: relative;
}

.quick-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: var(--gap-card);
  margin-bottom: 16px; /* ← 必须有！控制模块间距 */
}

.feed-card {
  margin-bottom: 16px; /* ← 必须有！控制模块间距（位于 .section 内部时不写左右 margin）*/
}

/* ===== Card base — 位于 .section 内部时不写左右 margin ===== */
.card {
  border-radius: var(--radius-card);
  padding: var(--padding-card);
  background: var(--bg-card);
  border: 1px solid var(--border-light);
  box-shadow: var(--shadow-sm);
  /* 在 .section 内部时：只写 margin-bottom，不写左右 margin
     因为 .section 已有 padding: 0 var(--margin-page) */
  margin-bottom: var(--gap-card);
}

/* ===== Feed Card 头部元信息间距规则 ===== */
/* 昵称与时间的间距必须为 4px */
.feed-card__meta {
  display: flex;
  flex-direction: column;
  gap: 0;
}
.feed-card__username {
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary);
  margin: 0 0 4px; /* ← 昵称下间距固定 4px */
  line-height: 1.2;
}
.feed-card__time {
  font-size: 11px;
  color: var(--text-tertiary);
  margin: 0; /* ← 清除默认 margin，避免叠加导致间距过大 */
  line-height: 1.2;
}

/* ===== Banner / Promo Card (首页横幅) — 独立在 .section 外 ===== */
.banner-card {
  margin: 0 var(--margin-page) var(--gap-card);
  border-radius: var(--radius-card);
  overflow: hidden;
  position: relative;
}
.banner-card__content {
  position: relative; z-index: 2;
  padding: var(--padding-card); /* 四周 16px，上下左右统一 */
  display: flex; flex-direction: column; justify-content: center;
}

/* ===== List row card (no inner padding needed for tight rows) ===== */
.card-row {
  border-radius: var(--radius-card);
  padding: var(--padding-card);
  background: var(--bg-card);
  border: 1px solid var(--border-light);
}

/* ===== Horizontal scroll section ===== */
.scroll-section {
  margin-left: calc(-1 * var(--margin-page));
  padding-left: var(--margin-page);
  padding-right: var(--margin-page);
  overflow-x: auto;
  scrollbar-width: none;
}
.scroll-section::-webkit-scrollbar { display: none; }

/* ===== Icon button (nav bar actions) — border-radius matches card ===== */
.icon-btn {
  width: 38px; height: 38px;
  border-radius: var(--radius-card); /* 20px：与卡片圆角统一 */
  background: var(--bg-card);
  border: 1px solid var(--border-light);
  display: flex; align-items: center; justify-content: center;
  cursor: pointer; transition: all 0.2s;
}
.icon-btn:hover { opacity: 0.8; }
.icon-btn:active { transform: scale(0.95); }

/* ===== Decorative elements (triangles/circles) — margin from edges ===== */
/* ⚠️ 装饰元素必须设置边距，禁止直接贴边 */
.deco-triangle::before {
  content: ''; position: absolute;
  top: -20px; right: -20px; /* ← 至少 20px 边距 */
  width: 0; height: 0;
  border-left: 80px solid transparent;
  border-right: 80px solid transparent;
  border-bottom: 140px solid rgba(255,255,255,0.06);
}
.deco-triangle::after {
  content: ''; position: absolute;
  bottom: -16px; left: 24px; /* ← 至少 16px 边距 */
  width: 0; height: 0;
  border-left: 60px solid transparent;
  border-right: 60px solid transparent;
  border-bottom: 100px solid rgba(255,255,255,0.04);
}

/* ===== Tab bar card (smaller radius) ===== */
.tab-card {
  border-radius: var(--radius-sm);
  padding: 10px var(--padding-card);
  background: var(--bg-card);
  border: 1px solid var(--border-light);
}

/* ===== Quick grid (4-column icon + label grid) — inside .section ===== */
.quick-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: var(--gap-card);
  margin-bottom: var(--gap-card); /* ← 只写底部间距，不写左右 margin */
}

/* ===== Scroll container (horizontal scroll) ===== */
/* ⚠️ 必须设置 padding-left 与标题对齐，禁止贴边 */
.product-scroll {
  display: flex;
  gap: 12px;
  overflow-x: auto;
  padding-left: var(--margin-page); /* ← 关键：与页面标题左对齐 */
  padding-bottom: 4px;
  scrollbar-width: none;
}
.product-scroll::-webkit-scrollbar { display: none; }
```

#### 5.1.4 Checklist — Mobile Spacing

- [ ] `margin: 0 var(--margin-page)` on page container
- [ ] All card components use `--radius-card: 20px`
- [ ] All card content padded with `--padding-card: 16px`
- [ ] **统一间距 `--gap-card: 12px`** 控制：标题↔卡片、卡片↔卡片、滚动容器内卡片间距
- [ ] No hardcoded `16px` / `20px` values in component CSS — use variables
- [ ] **滚动容器（`.product-scroll` / `.coupon-scroll` / `.order-status` 等）不需要写 `padding-left`**：父级 `.section` 的 `padding-left: var(--margin-page)` 已提供左对齐，避免双重缩进
- [ ] **滚动容器内部卡片间距通过 `gap: var(--gap-card)` 控制**，不额外加 `padding-right`，最后一卡右边距自动等于 gap
- [ ] **`.section` 上写 `padding: 0 var(--margin-page) var(--gap-card)`**（合并写法），自动控制左右边距 16px + 底部间距 12px
- [ ] **所有区块类卡片模块（`.store-card` / `.product-row` / `.benefit-card` / `.member-card` / `.quick-grid` 等）放在 `.section` 内时**：只写 `margin-bottom: var(--gap-card)`，**不写左右 margin**，否则会产生双倍间距（section 的 padding 16px + 卡片自己的 margin 16px = 32px）
- [ ] **例外 — 社交动态卡片（`.feed-card`）**：需要显式左右边距 `margin: 0 var(--margin-page) var(--gap-card)`，与视觉设计一致（卡片左右有 16px 间距）
- [ ] **滚动容器必须放在 `.section` 内部**（`.section > .section__header + .product-scroll`），不能与 `.section` 并列
- [ ] **Banner Card / Promo Card（独立横幅）**：`margin: 0 var(--margin-page) var(--gap-card)`，内部内容 `.__content { padding: var(--padding-card) }`（16px），**不能硬编码 `24px`**
- [ ] **装饰元素（圆形/三角形）必须设置边距**，禁止直接贴边：`top: -20px; right: -20px` 或 `bottom: -16px; left: 24px`（至少 16px）
- [ ] **Tab Bar（固定底部导航）**：在手机原型内用 **Flex 兄弟节点** 方案（`.app` flex column + `.app__scroll` 独立滚动 + `.tab-bar` `flex-shrink: 0`），**禁止** `position: absolute`（会跟随内容滚动）。详见 Step 5.6。

#### 5.1.5 Section Wrapper — Correct Nesting

**⚠️ 常见错误：滚动容器与 `.section` 并列，导致间距翻倍**

❌ 错误结构（间距 = `padding-bottom` + `margin-bottom`，会偏大）：
```html
<div class="section">
  <div class="section__header">今日推荐</div>
</div>
<div class="product-scroll">  ← OUTSIDE section! BAD!
  ...
</div>
```

✅ 正确结构（间距由 `.__header` 的 `margin-bottom` 精确控制）：
```html
<div class="section">
  <div class="section__header">今日推荐</div>
  <div class="product-scroll">  ← INSIDE section! GOOD!
    ...
  </div>
</div>
```

✅ 同理适用于：`coupon-scroll`、`order-status`、`quick-cats` 等所有滚动容器

#### 5.1.5 Hero / Featured Card — Full-Bleed, Width-Adaptive (MANDATORY)

> ⛔ **HARD RULE: Mobile 原型的顶部 Hero / Banner / Featured 大卡，默认必须"贴边全宽"（full-bleed）且随手机宽度自适应拉伸 —— 两侧禁止留 16px 边距。**

这条规则来自真实反馈：用户看到顶部大图左右各留 16px 白边时，直觉就是"没做自适应 / 没拉满 / 看起来像半成品"。Hero 是整页的视觉核心，必须"顶满"手机屏幕宽度，才能传达内容主权（content-first）。

**❌ 错误示例（hero 左右留白，像贴了块卡片在页面上）:**
```css
.hero-card {
  margin: 16px var(--margin-page) 0;   /* ❌ 两侧有 page margin */
  border-radius: 20px;                 /* ❌ 圆角 + 边距 = 卡片感 */
}
```

**✅ 正确示例（hero 铺满视口宽度，贴边无缝）:**
```css
.hero-card {
  margin: 16px 0 0;          /* ✅ 左右 margin 为 0，随容器宽度拉伸 */
  border-radius: 0;          /* ✅ 贴边一般无圆角，或仅下方圆角 */
  width: 100%;
  /* 高度用 aspect-ratio 自适应，不要写死 px */
  aspect-ratio: 16 / 11;
  max-height: 420px;
}
```

**通用"宽度自适应"核心原则（写任何 mobile 容器都要遵守）:**

1. **容器宽度一律用百分比 / flex / grid，不要写死 `width: 430px`**（430 只能出现在最外层 phone-mockup 的演示边框上）
2. **图片、卡片、网格使用 `width: 100%` + `aspect-ratio`**，让高度随宽度自动缩放
3. **`.phone-mockup` 改宽度后，内部所有元素应跟着变窄/变宽，0 溢出、0 死区**
4. **Hero / Banner / 封面视频 = full-bleed**（`margin-x: 0`, `border-radius: 0`）；普通内容卡 = inset（左右留 `--margin-page`）
5. **禁止对页面级元素使用 `min-width: Xpx`**，只在细节组件（如 icon、badge）才允许固定尺寸

**Self-check before finalizing:**
- 在浏览器 devtools 拖动 `.phone-mockup` 宽度（375 / 390 / 430 / 500px）
- 观察：Hero 大图是否始终贴边？普通卡片是否始终左右 16px 内缩？图片比例是否不变形？
- 如果 hero 两侧看到背景色，说明 hero 没贴边 → 修 `margin-x` 为 0

### Step 5.2: Preview Device — Single Phone, Double-Click Status Bar to Toggle Theme (MANDATORY)

当 App/页面以手机原型形式展示时，必须严格遵循以下规则：

#### 5.2.1 单台手机，不要左右并排

**⚠️ 禁止**：同时渲染两台手机（一台 Light / 一台 Dark）左右并排展示。
**✅ 必须**：只渲染**一台**手机，通过交互切换主题。

#### 5.2.2 交互：双击 Status Bar 切换主题

模拟 iOS 原生交互 —— **双击（dblclick）顶部 Status Bar 即可切换深/浅主题**。不要在页面右上角放浮动切换按钮。

```javascript
(function () {
  const STORAGE_KEY = 'app-theme';
  const root = document.documentElement;

  // 恢复上次的主题偏好
  const saved = localStorage.getItem(STORAGE_KEY);
  if (saved === 'dark' || saved === 'light') {
    root.setAttribute('data-theme', saved);
  }

  function toggleTheme() {
    const current = root.getAttribute('data-theme') || 'light';
    const next = current === 'dark' ? 'light' : 'dark';
    root.setAttribute('data-theme', next);
    localStorage.setItem(STORAGE_KEY, next);

    // 轻微的点击反馈动画
    document.querySelectorAll('.status-bar').forEach(bar => {
      bar.animate(
        [{ transform: 'scale(1)' }, { transform: 'scale(0.98)' }, { transform: 'scale(1)' }],
        { duration: 220, easing: 'cubic-bezier(0.34, 1.56, 0.64, 1)' }
      );
    });
  }

  document.querySelectorAll('.status-bar').forEach(bar => {
    bar.addEventListener('dblclick', toggleTheme);
  });
})();
```

配合的 CSS —— 给 Status Bar 加手型光标 + 首次加载时的气泡提示：

```css
.status-bar {
  cursor: pointer;
  user-select: none;
  -webkit-user-select: none;
  position: relative;
}

/* 首次加载提示 "双击切换主题"，4.5 秒后自动淡出 */
.status-bar::after {
  content: '双击切换主题';
  position: absolute;
  top: calc(100% + 4px);
  left: 50%;
  transform: translateX(-50%);
  padding: 4px 10px;
  background: var(--accent-primary);
  color: var(--text-on-accent);
  font-size: 10px;
  font-weight: 600;
  border-radius: 999px;
  white-space: nowrap;
  pointer-events: none;
  opacity: 0;
  animation: hintFade 4.5s ease-out 0.5s 1 both;
  z-index: 200;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.2);
}
@keyframes hintFade {
  0%   { opacity: 0; transform: translate(-50%, -4px); }
  15%  { opacity: 1; transform: translate(-50%, 0); }
  80%  { opacity: 1; transform: translate(-50%, 0); }
  100% { opacity: 0; transform: translate(-50%, -4px); }
}
```

#### 5.2.3 外框：直角矩形，不要 iPhone 外壳

**⚠️ 禁止**：给手机原型加 iPhone 形状的大圆角外壳（如 `border-radius: 56px` + 黑色外框 box-shadow）。这只是**预览容器**，不是真机渲染。
**✅ 必须**：使用**直角矩形**（`border-radius: 0`），干净的边缘，可选一点阴影增加立体感。

```css
/* ✅ 推荐：直角矩形 + 固定设备高度（模拟手机屏幕边界） */
.phone-mockup {
  width: 430px;                /* 固定宽度 */
  height: 900px;               /* 固定高度 = 手机屏幕边界（必须，详见 Step 5.6） */
  background: var(--bg-primary);
  border-radius: 0;            /* ← 直角 */
  overflow: hidden;            /* 裁切内部滚动，不让内容溢出 */
  position: relative;
  margin: 0 auto;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);  /* 可选：投影增加立体感 */
}

/* ❌ 禁止：模拟 iPhone 外壳 */
.phone-mockup--wrong {
  border-radius: 56px;                      /* 大圆角 */
  box-shadow:
    0 0 0 8px #1C1C1E,                      /* 黑色外框 */
    0 0 0 9px #2A2A2D,
    0 30px 80px rgba(0,0,0,0.4);
}
```

#### 5.2.4 对比色背景

```css
/* 浅色 App → 页面背景为深色（对比色） */
html[data-theme="light"] { background: #1C1C1E; }
/* 深色 App → 页面背景为浅色（对比色） */
html[data-theme="dark"]  { background: #E8E8ED; }
```

**对比色参考值：**

| App 主题 | App 背景 | 页面背景（对比） |
|---------|---------|-----------------|
| 浅色模式 | `#FFFFFF` | `#1C1C1E`（深灰） |
| 深色模式 | `#080808` | `#E8E8ED`（浅灰） |
| 浅色暖调（咖啡） | `#FFFDF9`（奶白） | `#1A1510`（深棕） |
| 浅色冷调 | `#F0F4FF`（淡蓝） | `#0A0F1E`（深蓝黑） |

**⚠️ 不要让 App 背景色 = 页面背景色，否则 App 内容会"消失"。**

#### 5.2.5 Checklist — Preview Device

- [ ] **一台手机**：单屏单模式，不要左右并排两台（Light + Dark）
- [ ] **双击 Status Bar 切换主题**：绑定 `dblclick` 到 `.status-bar`，翻转 `html[data-theme]`
- [ ] **不要右上角浮动按钮**：主题切换仅通过双击 Status Bar，符合 iOS 原生交互
- [ ] **首次加载提示**：Status Bar 下方气泡 "双击切换主题"，4.5 秒后自动淡出
- [ ] **localStorage 持久化**：刷新后保留上次选择
- [ ] **直角外框**：`.phone-mockup { border-radius: 0 }`，**禁止** iPhone 形状的大圆角和黑色外壳
- [ ] **固定宽度 430px**，居中
- [ ] **对比色背景**：页面底色与 App 底色对比，避免"消失"

### Step 5.3: Text-Background Contrast Rule (MANDATORY)

深色背景必须用浅色字，浅色背景必须用深色字。禁止出现不可读对比。

#### 5.3.1 通用对比规则

| 背景类型 | 必须使用 | 禁止使用 |
|---------|---------|---------|
| 深色背景（`#080808` ~ `#1C1C1E`） | `--text-inverse`（白色/浅色） | `--text-primary`（深色字） |
| 浅色背景（`#FFFFFF` ~ `#F5F0E8`） | `--text-primary`（深色/中性色） | `--text-inverse`（白色） |
| 半透明背景（`rgba(0,0,0,0.5)` 等） | 根据透明度判断：深遮罩→浅字，浅遮罩→深字 | 无 |

#### 5.3.2 CSS 变量定义模板

```css
/* Light mode — 浅色背景用深色字 */
html[data-theme="light"] {
  --bg-primary: #FFFFFF;
  --text-primary: #1A0E08;      /* 深色，用于浅色背景 */
  --text-secondary: #6B4F3A;    /* 中性色，用于浅色背景 */
  --text-inverse: #FFFFFF;       /* 白色，用于深色背景（不要用在浅色背景上） */
  --text-on-accent: #FFFFFF;     /* 强调色按钮上的白色文字 */
}

/* Dark mode — 深色背景用浅色字 */
html[data-theme="dark"] {
  --bg-primary: #0F0A06;
  --text-primary: #F5EDE0;      /* 浅色，用于深色背景 */
  --text-secondary: #C4A882;    /* 中性色，用于深色背景 */
  --text-inverse: #0F0A06;       /* 深色，用于浅色背景（深色模式下是背景色） */
  --text-on-accent: #0F0A06;     /* 深色，用于强调色按钮上 */
}
```

#### 5.3.3 深色背景场景示例

| 场景 | 背景色 | 文字色 | 说明 |
|------|-------|-------|------|
| Hero 大标题 | `--hero-bg: #0A0A0A` | `--hero-title-color: #FFFFFF` | 必须白色 |
| 会员卡背景 | `linear-gradient(#8B5E3C, #C4956A)` | `#FFFFFF` | 渐变中文字必须白 |
| Banner 背景 | `linear-gradient(135deg, #007AFF, #5856D6)` | `#FFFFFF` | 品牌深色渐变用白色字 |
| 深色卡片背景 | `--bg-card: #1A1A1A` | `--text-primary: #F5F0E8` | 浅色字 |
| 底部 Tab Bar | `--tab-bg: rgba(8,8,8,0.92)` | `--tab-text: #F5F0E8`（未选中）/ `--tab-text-active: #FFFFFF` | Tab 图标用浅色 |

#### 5.3.4 Checklist — Contrast

- [ ] **深色背景区块**（Hero / Banner / 会员卡 / 深色卡片）：文字用 `--text-primary`（浅色）或 `#FFFFFF`
- [ ] **浅色背景区块**：文字用 `--text-primary`（深色）
- [ ] **会员卡**等彩色背景：确保文字为白色或高对比度
- [ ] **禁止**：深色背景 + 深色文字（如 `#333` 文字在 `#1C1C1E` 背景上）
- [ ] **禁止**：浅色背景 + 白色文字（除非有彩色遮罩）

### Step 5.5: Icons — Use Remix Icon (MANDATORY)

**⚠️ All icons MUST come from Remix Icon (https://remixicon.com/).** Do NOT use emoji, Unicode symbols, or custom SVGs drawn from scratch. Remix Icon provides a consistent, professional icon set with both line and fill variants.

#### 5.5.1 How to Include Remix Icon

**Option A — CDN (fastest, recommended for prototyping):**
```html
<link href="https://cdn.jsdelivr.net/npm/remixicon@4.2.0/fonts/remixicon.css" rel="stylesheet" />
```
Then use as: `<i class="ri-[name]-[line|fill]"></i>` (e.g., `<i class="ri-home-line"></i>`)

**Option B — Download individual SVGs:**
```bash
# Search icon names from https://remixicon.com/
# Download SVG and inline directly into HTML
```

#### 5.5.2 Style Rule — Line Default, Fill for Tab Bar

| Context | Style | Class | Example |
|---|---|---|---|
| Header icons (search, notif) | **Line** | `ri-*-line` | `<i class="ri-search-line"></i>` |
| Card/feature icons | **Line** | `ri-*-line` | `<i class="ri-shield-check-line"></i>` |
| Social media icons | **Fill** | `ri-*-fill` | `<i class="ri-twitter-x-fill"></i>` |
| Bottom Tab Bar | **Fill** | `ri-*-fill` | `<i class="ri-home-fill"></i>` |
| Action buttons (like, comment) | **Line** | `ri-*-line` | `<i class="ri-heart-line"></i>` |
| Active tab indicator | **Fill** | `ri-*-fill` | `<i class="ri-compass-fill"></i>` |

**Why:** Line icons are cleaner for content-heavy UI; fill icons have stronger visual weight, ideal for bottom navigation where icons need to "pop" as tap targets.

#### 5.5.3 Icon Existence Guarantee (MANDATORY — NO BLANK SQUARES)

> ⛔ **HARD RULE: NEVER ship an icon class you have not verified exists.**
>
> A single missing icon class renders as a blank square / tofu and ruins the entire design's perceived quality. This has bitten multiple released versions of this skill — including cases where this SKILL.md itself previously listed NON-EXISTENT icons (e.g. `ri-campfire-fill`, `ri-mountain-line`, `ri-terrain-line`) as "verified". **Trust only the mechanical check below, not your memory, not this table, not even a previous version of this skill.**

**The ONLY reliable source of truth is the Remix Icon 4.2.0 CSS itself.**

##### ✅ MANDATORY: Run the verification script before delivering

Every time you output an HTML file containing `ri-*` classes, run:

```bash
bash scripts/verify-icons.sh /path/to/your/index.html
```

The script downloads the real Remix Icon 4.2.0 CSS and greps every `ri-*` class in your HTML against it. It exits non-zero if any icon is missing. **If it fails, fix and rerun before considering the work done.** No exceptions.

(Script lives at `apple-design-local/scripts/verify-icons.sh` in this skill bundle.)

##### Inline one-liner (when the script isn't available)

Before writing unfamiliar icons, paste their names into this check:

```bash
for n in icon1-line icon2-fill icon3-line; do
  curl -s "https://cdn.jsdelivr.net/npm/remixicon@4.2.0/fonts/remixicon.css" | \
    grep -q "\.ri-${n}:before" && echo "✅ $n" || echo "❌ $n"
done
```

##### Rules you MUST follow every time you output an icon

1. **Prefer the pre-verified semantic table below.** These were all checked against Remix Icon 4.2.0 CSS on 2026-04-29.
2. **If a concept isn't in the table — verify first, don't guess.** Run the one-liner or the full script.
3. **Line variants are broader than fill.** When unsure, default to `-line` — nearly every icon has a line version; fill coverage is partial.
4. **Semantic substitution > blank square.** A `footprint` icon for "hiking" beats tofu every time.
5. **Icons you might *think* exist but DO NOT in Remix Icon 4.2:** `ri-mountain-*`, `ri-hiking-*`, `ri-backpack-*`, `ri-campfire-*`, `ri-terrain-*`, `ri-forest-*`. Memorize these — they are the top hallucinations.

##### Pre-verified semantic icon table (checked 2026-04-29 against Remix Icon 4.2.0)

| 语义 Need | ✅ Verified class(es) | ❌ Known non-existent |
|---|---|---|
| 徒步 / Hiking | `ri-footprint-fill` / `ri-footprint-line` / `ri-walk-fill` / `ri-walk-line` | `ri-hiking-*` |
| 跑步 / Run | `ri-run-fill` / `ri-run-line` | — |
| 山 / Mountain / Terrain | **No direct icon** — use `ri-footprint-*` (hiking) or `ri-plant-*` (nature) | `ri-mountain-*`, `ri-terrain-*` |
| 露营 / Camping / 帐篷 | **`ri-tent-fill` / `ri-tent-line`** ✓ | `ri-campfire-*` |
| 背包 / Backpack / Luggage | `ri-briefcase-4-fill` / `ri-briefcase-4-line` / `ri-suitcase-3-fill` / `ri-suitcase-3-line` / `ri-archive-fill` | `ri-backpack-*` |
| 森林 / Nature / Plant | `ri-plant-fill` / `ri-plant-line` / `ri-leaf-fill` / `ri-leaf-line` | `ri-forest-*` |
| 火 / Fire / Hot | `ri-fire-fill` / `ri-fire-line` | — |
| 路线 / Route / Trail | `ri-route-fill` / `ri-route-line` / `ri-map-pin-range-line` | — |
| 首页 / Home | `ri-home-5-fill` / `ri-home-5-line` / `ri-home-line` | — |
| 通知 | `ri-notification-3-fill` / `ri-notification-3-line` | — |
| 搜索 | `ri-search-line` | — |
| 心 / Like | `ri-heart-line` / `ri-heart-fill` | — |
| 书签 / Save | `ri-bookmark-line` / `ri-bookmark-fill` | — |
| 罗盘 / Explore | `ri-compass-3-fill` / `ri-compass-3-line` / `ri-compass-line` | — |
| 用户 | `ri-user-fill` / `ri-user-line` / `ri-group-fill` | — |
| 地图 | `ri-map-2-fill` / `ri-map-2-line` / `ri-map-pin-line` | — |
| 添加 / Plus | `ri-add-line` / `ri-add-circle-fill` | — |
| 认证徽章 | `ri-verified-badge-fill` / `ri-verified-badge-line` | — |
| 自行车 | `ri-e-bike-2-fill` / `ri-riding-fill` | — |
| 咖啡 / Cup | `ri-cup-fill` / `ri-cup-line` | — |
| 星级 | `ri-star-fill` / `ri-star-s-fill` | — |
| 消息 / Chat | `ri-message-3-line` / `ri-message-3-fill` / `ri-chat-3-line` / `ri-chat-3-fill` | — |
| 设置 | `ri-settings-3-line` / `ri-settings-3-fill` | — |
| 分享 | `ri-share-forward-line` / `ri-share-forward-fill` | — |
| Status bar | `ri-signal-tower-fill` / `ri-wifi-fill` / `ri-battery-fill` | — |

##### Image / Photo Missing Guarantee (same rigor as icons)

The same principle applies to `<img>` sources — a broken image ruins the design just as badly as a missing icon. Rules:

1. **Every `<img>` MUST have a real downloaded file on disk** (Unsplash workflow in Step 10), not a hotlinked URL that could 404.
2. **After writing HTML, verify every `src` attribute resolves:**
   ```bash
   # Check every img src exists on disk
   grep -oE 'src="[^"]+\.(jpg|png|webp|svg|jpeg)"' /path/to/index.html | \
     sed 's/src="//;s/"//' | \
     while read f; do [ -f "$(dirname /path/to/index.html)/$f" ] && echo "✅ $f" || echo "❌ $f"; done
   ```
3. **Every `background-image: url(...)` in CSS must also resolve.** Run the same check on CSS `url(...)` references.
4. **Avatar / thumbnail fallbacks:** If you couldn't fetch an image, don't leave a broken `src` — use a colored `div` with the user's initial letter as placeholder.

##### Self-check checklist before delivering

- [ ] Ran `bash scripts/verify-icons.sh <file>` — exit code 0
- [ ] All `<img src>` point to existing local files
- [ ] All CSS `url(...)` point to existing local files
- [ ] Opened the page in a browser — **visually scanned every icon slot**, no blank squares, no tofu, no broken-image placeholders
- [ ] If any icon I wanted didn't exist, I picked a semantic substitute from the table above (not a blank `<i>`)

#### 5.5.2.1 ⚠️ CRITICAL — Do NOT invent icon names

See Section **5.5.3 Icon Existence Guarantee** above — it is the single source of truth for verified icons, hallucination hotspots, and the mandatory `verify-icons.sh` workflow. All previous "common substitution" tables that lived here have been consolidated into 5.5.3 and corrected against real Remix Icon 4.2.0 CSS.

#### 5.5.3-ext Extended Catalogue (secondary reference — still verify before use)

> ⚠️ **These entries are commonly-used candidates but NOT individually re-verified in the last audit.** Prefer the core table in 5.5.3 above. For any icon from this catalogue that isn't in the core table, **run `verify-icons.sh` on your HTML before shipping.**

Always pick the icon that matches the **semantic meaning**, not just the visual shape.

| Meaning | Remix Icon (Line) | Remix Icon (Fill) | Notes |
|---|---|---|---|
| Home | `ri-home-line` | `ri-home-fill` | Tab bar default |
| Search | `ri-search-line` | — | Header/nav |
| User / Profile | `ri-user-line` | `ri-user-fill` | Profile tab |
| Heart / Like | `ri-heart-line` | `ri-heart-fill` | Like action |
| Star / Favorite | `ri-star-line` | `ri-star-fill` | Bookmark/rate |
| Message / Chat | `ri-message-3-line` | `ri-message-3-fill` | DM/chat |
| Settings | `ri-settings-3-line` | `ri-settings-3-fill` | Settings |
| Bell / Notification | `ri-notification-3-line` | `ri-notification-3-fill` | Alerts |
| Menu / Hamburger | `ri-menu-3-line` | — | Mobile nav |
| Close / X | `ri-close-line` | — | Dismiss |
| Arrow left / Back | `ri-arrow-left-line` | — | Navigation |
| Arrow right / Forward | `ri-arrow-right-line` | — | Navigation |
| Check | `ri-check-line` | `ri-check-fill` | Confirm |
| Plus / Add | `ri-add-line` | `ri-add-fill` | Create action |
| Trash / Delete | `ri-delete-bin-line` | `ri-delete-bin-fill` | Remove |
| Edit / Pencil | `ri-edit-line` | `ri-edit-fill` | Edit |
| Eye / View | `ri-eye-line` | `ri-eye-fill` | Show/hide |
| Lock | `ri-lock-line` | `ri-lock-fill` | Security |
| Mail / Email | `ri-mail-line` | `ri-mail-fill` | Contact |
| Phone | `ri-phone-line` | `ri-phone-fill` | Call |
| Location / Pin | `ri-map-pin-line` | `ri-map-pin-fill` | Address |
| Calendar | `ri-calendar-line` | `ri-calendar-fill` | Date |
| Image / Photo | `ri-image-line` | `ri-image-fill` | Gallery |
| Camera | `ri-camera-line` | `ri-camera-fill` | Photo |
| Download | `ri-download-line` | — | Save |
| Share | `ri-share-line` | `ri-share-fill` | Share |
| Link | `ri-link` | — | URL |
| Shopping Bag | `ri-shopping-bag-line` | `ri-shopping-bag-fill` | E-commerce |
| Cart | `ri-shopping-cart-line` | `ri-shopping-cart-fill` | Cart |
| Credit Card | `ri-bank-card-line` | `ri-bank-card-fill` | Payment |
| Filter | `ri-filter-line` | — | Filter |
| Sort | `ri-sort-desc` | — | Sort |
| Refresh | `ri-refresh-line` | — | Reload |
| More / Ellipsis | `ri-more-2-fill` | — | Overflow menu |
| Compass / Discover | `ri-compass-3-line` | `ri-compass-3-fill` | Discover tab |
| Fire / Trending | `ri-fire-line` | `ri-fire-fill` | Hot/trending |
| Lightning | `ri-flashlight-line` | `ri-flashlight-fill` | Flash/speed |
| Award / Badge | `ri-award-line` | `ri-award-fill` | Achievement |
| Globe / Web | `ri-global-line` | — | Website |
| Code | `ri-code-line` | — | Developer |
| Briefcase | `ri-briefcase-line` | `ri-briefcase-fill` | Work |
| Coffee | `ri-cup-line` | `ri-cup-fill` | Cafe/break |
| Car | `ri-car-line` | `ri-car-fill` | Automotive |
| Plane | `ri-plane-line` | `ri-plane-fill` | Travel |
| Moon / Night | `ri-moon-line` | `ri-moon-fill` | Dark mode |
| Sun | `ri-sun-line` | `ri-sun-fill` | Light mode |
| Eye-off | `ri-eye-off-line` | — | Hide |
| User Plus | `ri-user-add-line` | — | Follow |
| Users / Group | `ri-group-line` | `ri-group-fill` | Team |
| Time / Clock | `ri-time-line` | `ri-time-fill` | History |
| Chat AI / Bot | `ri-robot-line` | `ri-robot-fill` | AI features |
| Sparkles | `ri-magic-line` | `ri-magic-fill` | AI/generative |
| Qr code | `ri-qr-code-line` | — | QR scan |
| Send / Arrow up | `ri-send-plane-line` | `ri-send-plane-fill` | Submit/send |
| External link | `ri-external-link-line` | — | Open link |

#### 5.5.4 Icon Sizing & Color

Use CSS for sizing — never set icon font-size via inline HTML attributes:
```css
/* Icon base — inherit text color, match line height */
.icon {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 1em;
  height: 1em;
  vertical-align: middle;
}

/* Size variants */
.icon-sm  { font-size: 16px; }
.icon-md  { font-size: 20px; }
.icon-lg  { font-size: 24px; }
.icon-xl  { font-size: 32px; }

/* In light/dark mode, use text color variable */
.icon {
  color: var(--label-primary); /* adapts to both modes */
}
```

#### 5.5.5 Icon + Badge (notification dot)

Common pattern — notification badge on icons:
```css
.icon-wrap {
  position: relative;
  display: inline-flex;
}
.icon-wrap .badge {
  position: absolute;
  top: -4px;
  right: -4px;
  width: 8px;
  height: 8px;
  background: var(--accent-primary);
  border-radius: 50%;
  border: 1.5px solid var(--bg-primary);
}
```

#### 5.5.6 Tab Bar Specific Rules

Bottom tab bar icons MUST use **fill** style for both active and inactive states to maximize tap target visibility:

```html
<div class="tab-bar">
  <a class="tab-item active">
    <i class="ri-home-fill"></i>   <!-- fill, active -->
    <span>首页</span>
  </a>
  <a class="tab-item">
    <i class="ri-compass-3-fill"></i>  <!-- fill, inactive — same weight as active -->
    <span>发现</span>
  </a>
  <a class="tab-item">
    <i class="ri-add-circle-fill"></i>  <!-- fill, prominent CTA -->
    <span>发动态</span>
  </a>
  <a class="tab-item">
    <i class="ri-message-3-fill"></i>
    <span>消息</span>
  </a>
  <a class="tab-item">
    <i class="ri-user-fill"></i>
    <span>我的</span>
  </a>
</div>
```

#### 5.5.7 Checklist — Icon Quality

- [ ] **Ran `bash scripts/verify-icons.sh <html>` — exit code 0** (MANDATORY before delivery)
- [ ] Every icon comes from Remix Icon (`ri-*` class) — NO emoji, NO Unicode symbols
- [ ] Line icons used for: headers, cards, actions, content UI
- [ ] Fill icons used for: bottom tab bar, social icons, active states
- [ ] Icon color uses CSS variable (`var(--label-primary)` or `var(--accent-primary)`)
- [ ] Icon sizes defined via CSS classes, not inline `style="font-size:..."`
- [ ] Tab bar icons all use fill style for visual consistency
- [ ] Notification badge positioned correctly with border matching background
- [ ] **No `ri-mountain-*`, `ri-hiking-*`, `ri-backpack-*`, `ri-campfire-*`, `ri-terrain-*`, `ri-forest-*` anywhere** — these do NOT exist

### Step 5.6: Mobile App Scroll Architecture (MANDATORY — Sticky 粘在手机屏幕视口)

#### 5.6.0 Phone Mockup Container Contract — HARD RULE (READ FIRST)

> ⛔ **手机原型的外框必须像一台真手机 —— 固定视口 + 内部滚动 —— 不是一张被内容撑高的长图。**
>
> 已观察到的真实失败案例（2026-04 市场版）：手机框被 Field Journal / 会员卡 / 回收故事撑成 2000+ 像素长条，Tab Bar 跟着内容走到底部才露脸，下面露出大片灰色空白；或者反向过度克制 —— 为了"一屏塞完"把内容删剩 3 个模块，整页空旷。两种都是 ❌。

**正确形态（二者必须同时成立）:**

| ✅ 必须做到 | ❌ 禁止 |
|---|---|
| `.phone-mockup` **固定 `height` (建议 812~932px)** | `min-height: 100vh` / `height: auto` 让内容撑高 |
| `.phone-mockup` **设 `overflow: hidden`** 裁切溢出 | `overflow: visible` 让内容溢出到手机框外 |
| `.app` 是唯一滚动容器 (`height: 100%; overflow-y: auto`) | `<body>` 直接滚，或手机外部滚动 |
| 内容 **比视口多**（放心塞 5~8 屏内容），在手机内部上下滑动 | 为了"一屏塞完"把模块删光，或用 `overflow: hidden` 丢失内容 |
| Header/TabBar 用 `position: sticky` | `position: fixed`（穿透到外部）/ `absolute`（跟着滚） |

**判断你做对了的 3 个信号:**
1. 在浏览器里刷新页面，**外部页面本身不会滚动**（scrollbar 只出现在手机框内部，或完全不出现）
2. 手机框在视觉上是一个**尺寸固定的矩形**，不管里面塞多少内容，外框尺寸不变
3. Tab Bar 始终贴在手机屏幕**底边**（不是页面底边），手指上滑时 Tab Bar 纹丝不动

**Preflight Self-Check（在输出 HTML 前默念一遍）:**
- [ ] `.phone-mockup { height: 900px; overflow: hidden }` —— 固定高度 + 裁切
- [ ] `.app { height: 100%; overflow-y: auto }` —— 独立滚动
- [ ] 内容写完后，**心里估算 DOM 总高度 > 900px**（如果低于 900 说明内容太单薄，该补）
- [ ] Header、TabBar 只用 `position: sticky`，没用 `fixed` 或 `absolute`
- [ ] 在 devtools 里把 body 背景改成红色，刷新：**红色不应该在手机框下方出现大块露出**

#### 5.6.1 根本原理：sticky 粘在谁身上？

CSS `position: sticky` 的 "视口" 是 **最近的 scrolling ancestor**（有 `overflow: auto/scroll/hidden` 的祖先）。

- 如果**祖先链上没有滚动容器** → sticky 相对 `<html>` / viewport 粘 → 贴浏览器窗口
- 如果**祖先链上某个元素是滚动容器** → sticky 相对那个元素粘 → 贴那个元素的顶/底

**所以在手机原型里**：要让 Header/Tab 贴在**手机屏幕**的顶/底，就必须让**`.app` 本身是滚动容器**。

#### 5.6.2 正确架构：单滚动容器 + Sticky

```css
/* ===== Phone mockup: 固定设备高度，裁切内容 ===== */
.phone-mockup {
  width: 430px;
  height: 900px;           /* 固定高度 = 手机屏幕边界 */
  background: var(--bg-primary);
  border-radius: 0;        /* 直角外框 */
  overflow: hidden;        /* 裁切超出的内容 */
  position: relative;
  margin: 0 auto;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);
}

/* ===== App: 唯一滚动容器 =====
   sticky 相对 .app 视口粘，同容器内内容从 sticky 下方穿过 → 毛玻璃真生效 */
.app {
  width: 100%;
  height: 100%;            /* 占满 mockup */
  position: relative;
  overflow-y: auto;        /* ← 这里是滚动容器 */
  overflow-x: hidden;
  scrollbar-width: none;
  -webkit-overflow-scrolling: touch;
}
.app::-webkit-scrollbar { display: none; }

/* ===== Header: sticky top:0，贴在 .app 视口顶部 ===== */
.app-header {
  position: sticky;
  top: 0;
  z-index: 100;
  background: var(--nav-bg);                          /* 半透明 0.6~0.82 */
  backdrop-filter: saturate(180%) blur(24px);
  -webkit-backdrop-filter: saturate(180%) blur(24px);
  border-bottom: 0.5px solid var(--border-light);
}

/* ===== Tab Bar: sticky bottom:0 + 负 margin 叠加 ===== */
.tab-bar {
  position: sticky;
  bottom: 0;
  margin-top: -78px;                  /* 关键！等于自身高度，让 Tab 叠在最后一屏上 */
  height: 78px;
  z-index: 100;
  background: var(--tab-bg);                          /* 半透明 0.6~0.82 */
  backdrop-filter: saturate(180%) blur(28px);
  -webkit-backdrop-filter: saturate(180%) blur(28px);
  border-top: 0.5px solid var(--border-light);
  /* ...flex 布局 */
}

/* ===== 页面内容 ===== */
.page {
  padding-bottom: 110px;   /* = 78 Tab + 32 呼吸，避免最后一段内容被 Tab 盖住 */
}
```

```html
<div class="phone-mockup">
  <div class="app">                     <!-- 滚动容器 -->
    <div class="app-header">...</div>   <!-- sticky top -->
    <div class="page">
      <!-- 所有内容，随 .app 滚动 -->
    </div>
    <div class="tab-bar">...</div>      <!-- sticky bottom -->
  </div>
</div>
```

**效果：**
- 往下滚内容时，Header 粘在 mockup 顶部不动 ✅
- Tab Bar 粘在 mockup 底部不动 ✅
- 内容从它们下方穿过 → `backdrop-filter` 毛玻璃真实生效 ✅
- 同时 Tab Bar/Header 都在同一个滚动容器内，不是独立的 flex 兄弟节点（所以毛玻璃能捕获背景）

#### 5.6.3 错误架构对照表

| 方案 | 问题 |
|------|------|
| ❌ `.app` 不滚动 + Tab Bar `position: absolute; bottom: 0` | Tab Bar 跟随内容滚动（因为 `.app` 的 padding box 在滚动） |
| ❌ Flex 三层：`.app__scroll` 独立滚动 + Tab Bar `flex-shrink: 0` 在 flex 流外 | Tab Bar 和内容**物理不同层**，毛玻璃没有背景可模糊 → 视觉是实色 |
| ❌ `.phone-mockup` 不设 height + sticky | sticky 粘在 body/浏览器视口，不是粘在手机屏幕边界，看起来像"没贴" |
| ❌ 预览容器有 `overflow: visible` 但 `.app` 也不是滚动容器 | 和上一条同理 —— sticky 相对 body 粘，不是 mockup |
| ✅ **mockup 固定 height + `.app` 滚动容器 + Header/Tab sticky** | 所有需求同时满足 |

#### 5.6.4 让毛玻璃真正"显形"的必要条件

| 前提 | 说明 |
|------|------|
| **① 元素本身背景半透明** | `--nav-bg: rgba(255,255,255,0.72)`。不要用 0.92 以上，和纯白无异 |
| **② 下方有实际内容可模糊** | 内容必须物理上从元素下方穿过 —— 单滚动容器 + sticky 方案天然满足 |
| **③ sticky 的滚动容器链没被切断** | 本方案里 `.app` 就是滚动容器，Header/Tab sticky 在 `.app` 里，内容也在 `.app` 里，同一层级 |

**推荐 token：**
```css
:root {
  --nav-bg: rgba(255, 255, 255, 0.72);
  --tab-bg: rgba(255, 255, 255, 0.78);
}
html[data-theme="dark"] {
  --nav-bg: rgba(10, 17, 13, 0.72);
  --tab-bg: rgba(10, 17, 13, 0.78);
}
```

#### 5.6.5 Tab Bar `margin-top: -78px` 技巧

`position: sticky; bottom: 0` 在内容不足一屏时会跟内容一起靠到底部，不"浮"。加 `margin-top: -自身高度` 让 Tab Bar 始终叠加在最后一屏内容之上：

```css
.tab-bar {
  position: sticky;
  bottom: 0;
  height: 78px;
  margin-top: -78px;         /* 反向拉回，永远浮在最后内容之上 */
}
.page { padding-bottom: 110px; }   /* 留空间避免被盖 */
```

#### 5.6.6 关于"自适应高度"

之前一版规范推行过"mockup 不设 height，自适应内容整页滚动"的做法。**不再推荐**：

- ❌ 自适应高度下，sticky 相对 body 粘，不是相对手机屏幕边界 → "粘在浏览器窗口顶"而不是"粘在手机顶"
- ❌ 看起来不像真实 App，更像长网页
- ✅ 固定设备高度（如 900px）才能正确模拟 iOS App 的滚动体验

如果真的需要超长内容预览（比如长列表 demo），可把 mockup `height` 设大一些（1200/1500px），但必须保留 `.app` 作为滚动容器。

#### 5.6.7 Checklist

- [ ] `.phone-mockup` **固定 height**（建议 812~900px，模拟真实手机屏幕）+ `overflow: hidden`
- [ ] `.app` 是**唯一滚动容器**：`height: 100%; overflow-y: auto`
- [ ] `.app-header` 用 `position: sticky; top: 0`
- [ ] `.tab-bar` 用 `position: sticky; bottom: 0; margin-top: -自身高度`
- [ ] `--nav-bg / --tab-bg` 半透明（alpha 0.6~0.82）
- [ ] `.page` 底部 `padding-bottom: 110px` 避免内容被 Tab 盖住
- [ ] **测试**：滚动时 Header/Tab 粘在**手机屏幕**顶/底（不是浏览器窗口），且下方内容模糊穿透可见
- [ ] **反面测试**：如果把 `.phone-mockup` 的 `height` 去掉或 `overflow` 改 visible，sticky 就会改为粘浏览器窗口 → 视觉错位，必须恢复

### Step 6: Apply Glassmorphism (when appropriate)

For overlays, modals, sidebars, and floating elements, use Apple's frosted glass:
```css
background: rgba(255, 255, 255, 0.72);
backdrop-filter: saturate(180%) blur(20px);
-webkit-backdrop-filter: saturate(180%) blur(20px);
border: 0.5px solid rgba(255, 255, 255, 0.3);
```

### Step 7: Motion

Use spring-based easing for tactile interactions:
```css
transition: transform 300ms cubic-bezier(0.34, 1.56, 0.64, 1.0);
```

For view transitions: 350–400ms ease-out. For micro interactions: 100–150ms.

Always add:
```css
@media (prefers-reduced-motion: reduce) {
  * { transition-duration: 0.01ms !important; animation-duration: 0.01ms !important; }
}
```

### Step 8: Dark Mode

All color tokens in `references/design-system.md` include dark mode variants via `@media (prefers-color-scheme: dark)`. Always use CSS variables — never hardcode hex values.

**IMPORTANT — Dual Mode Output**: Whenever generating a UI (page, component, section, etc.), always ensure **both Light and Dark Mode styles are fully implemented** so the user can switch between them:
1. **Light Mode** — using light mode color tokens (`:root`)
2. **Dark Mode** — using dark mode color tokens (`html[data-theme="dark"]` override)

**⚠️ 不要左右并排渲染两台手机**（一台 Light + 一台 Dark）。只渲染**一台**手机/页面，通过 **双击 Status Bar 切换主题** 的方式让用户在两种模式间切换（手机原型场景见 Step 5.2；Web 场景可用右下角主题按钮或 `prefers-color-scheme`）。双模式的质量要求并没有降低 —— 两种模式的 token 都必须完整、可读、有对比度。

**IMPORTANT — Visual Elements Must Also Adapt**: Every visual element that has a dark-mode variant (gradient backgrounds, card images, hero sections, icon tints, overlay colors, decorative shapes) must have a corresponding light-mode version. Use `[data-theme="dark"]` / `[data-theme="light"]` attribute selectors or `@media (prefers-color-scheme: dark)` for background gradients, image overlays, and decorative elements. Do NOT hardcode a dark gradient and leave the light mode with the same dark colors — they must be visually appropriate for both modes.

### Step 9: Dual Mode Quality Checklist (MANDATORY — Do This Before Output)

After writing all CSS, **STOP and verify every element in BOTH modes** using the following checklist. If any item fails, fix it before presenting the result.

**Typography & Text:**
- [ ] All text uses CSS variables (`var(--text-primary)`, `var(--text-secondary)`, etc.) — never hardcode `#FFFFFF` or `#000000` for body text
- [ ] Light mode: text on light backgrounds has sufficient contrast (dark text on light bg, NOT white-on-light)
- [ ] Dark mode: text on dark backgrounds is visible (light/white text on dark bg, NOT black-on-dark)
- [ ] Labels, captions, metadata text also use variables and are visible in both modes

**Buttons & Interactive Elements:**
- [ ] Primary buttons use `var(--accent-primary)` and are visible in both light and dark modes
- [ ] If using a dark brand color (e.g., gold, red, deep blue) as button bg, it works on light backgrounds
- [ ] Secondary/outline buttons use a dedicated variable like `var(--cta-btn-secondary-color)` — NOT `var(--text-inverse)` which breaks in light mode
- [ ] Hover/active states are visible in both modes (avoid state-only reliance on dark bg assumptions)

**Hero Sections — Critical:**
- [ ] Hero background: if `:root` has a dark `--hero-bg` value (e.g., `#0A0A0A`), there MUST be an explicit `[data-theme="light"]` block that overrides it to a light value. Do NOT rely on `[data-theme="dark"]` alone — if `[data-theme="light"]` is missing, the hero stays dark in light mode.
- [ ] If the brand intentionally keeps Hero dark in both modes (luxury brands), then `:root --hero-bg` should be light and `[data-theme="dark"] --hero-bg` should be dark — not the reverse.
- [ ] Hero overlay gradients: use CSS variables (`--hero-overlay-gold`, `--hero-overlay-red`) that are defined in BOTH mode blocks, not hardcoded `rgba()` values.
- [ ] Hero title color: use `var(--hero-title-color)` which is defined in both mode blocks — do NOT use `var(--text-primary)` which may conflict with dark hero backgrounds.
- [ ] Hero price tags / floating badges: use `var(--hero-price-text)` instead of hardcoded `color: white`
- [ ] Hero decorative gradients: both light and dark mode versions (e.g., light mode: muted pastel overlay on gray bg; dark mode: gold/red glow on black bg)

**CTA / Call-to-Action Sections:**
- [ ] CTA background uses `var(--cta-bg)` which can differ between modes
- [ ] CTA title uses `var(--cta-text)` — NOT `var(--text-inverse)` or `var(--text-primary)` which breaks in the opposite mode
- [ ] CTA secondary buttons use `var(--cta-btn-secondary-color)` with both mode values
- [ ] CTA description uses `var(--cta-text-muted)`
- [ ] Example: Light CTA → `--cta-bg: #F5F5F7`, `--cta-text: #1A1A1A`, `--cta-text-muted: rgba(26,26,26,0.55)`
- [ ] Example: Dark CTA → `--cta-bg: #1A1A1A`, `--cta-text: #FAFAFA`, `--cta-text-muted: rgba(250,250,250,0.55)`

**Visual Backgrounds & Gradients:**
- [ ] Hero sections: both `[data-theme="light"]` and `[data-theme="dark"]` / `@media` define distinct gradient backgrounds appropriate for each mode
- [ ] Section backgrounds use `var(--bg-primary)`, `var(--bg-secondary)` — adapt automatically
- [ ] Dark CTA sections need a light-mode fallback (do NOT leave `#000` as the only bg)
- [ ] Decorative shapes, dividers, overlays all have both-mode variants

**Cards & Component Surfaces:**
- [ ] Card backgrounds use `var(--bg-tertiary)` or `var(--bg-secondary)` — visible in both modes
- [ ] If using a dark card background on a potentially light section, it MUST have both mode variants: light mode → light gray cards (`#EBEBF0`) with dark text; dark mode → near-black cards (`#1A1A1A`) with light text
- [ ] Card borders use `var(--glass-border)` — subtle in both light and dark
- [ ] Card image areas have gradients for both modes (do NOT hardcode dark-only gradient)
- [ ] Hover states (e.g., `border-color: var(--accent-primary)`) are visible in both modes

**Shadows & Elevation:**
- [ ] Light mode: use `rgba(0,0,0,0.08–0.18)` shadows for elevation
- [ ] Dark mode: use `rgba(0,0,0,0.3–0.6)` shadows (darker = more visible on dark bg)
- [ ] Do NOT use white/bright shadows in dark mode — use black-based shadows
- [ ] Shadow color variables (`--shadow-sm`, `--shadow-md`, etc.) must differ between modes

**Glass / Frosted Elements:**
- [ ] Glass nav bars: `var(--glass-bg)` and `var(--glass-border)` adapt to both modes
- [ ] Translucent cards: both light-mode (`rgba(255,255,255,0.8)`) and dark-mode (`rgba(20,20,20,0.8)`) variants exist

**Icons & Emojis:**
- [ ] Icons/emoji on dark backgrounds are visible (white/light icons)
- [ ] Icons/emoji on light backgrounds are visible (dark/contrasting icons or use text color variable)
- [ ] Icon backgrounds (`rgba(accent, 0.1)`) adapt to both modes

**Newsletter Sections (邮件订阅等深色块):**
- [ ] Newsletter 背景使用 `--newsletter-bg`（`:root` 浅色如 `#F7F6F4`，`[data-theme="dark"]` 深色如 `#111110`）
- [ ] Newsletter 标题使用 `var(--newsletter-text)`，描述使用 `var(--newsletter-text-muted)`，输入框背景/边框/文字各用专用变量
- [ ] Newsletter 输入框 placeholder 颜色也需要两模式适配（`--newsletter-placeholder`）
- [ ] Newsletter 按钮文字硬编码 `#FFFFFF` 无问题（因为按钮背景是 accent 色）

**Social Icons / Footer:**
- [ ] Footer 背景使用 `var(--footer-bg)` — `:root` MUST be light (`#F0F0F4` or similar), `[data-theme="dark"]` MUST be dark (`#1C1C1E` or similar)
- [ ] **CRITICAL: Do NOT swap these values.** `:root` = light mode defaults, `[data-theme="dark"]` = dark mode overrides. Common mistake: writing dark values in `:root` and light values in `[data-theme="dark"]` — this inverts the entire theme.
- [ ] Footer 文字、链接、分割线、社交图标全部使用 CSS 变量：`--footer-text`、`--footer-text-secondary`、`--footer-text-tertiary`、`--footer-border`、`--footer-social-bg`
- [ ] Same rule applies to CTA sections: `--cta-bg` must be light in `:root`, dark in `[data-theme="dark"]`
- [ ] Social icons have both-mode backgrounds (light: white/gray, dark: dark gray)

**Mobile App Fixed Header（移动端 App 固定导航）:**
- [ ] **不要用两个独立的 fixed 元素**（Status Bar + Top Nav 分开），中间会有缝隙露出页面内容
- [ ] **推荐方案**：用一个统一的 `.app-header` 包裹 Status Area + Nav Area，`position: sticky; top: 0`，设置统一背景 + `backdrop-filter`，底部加 `border-bottom`（0.5px `rgba(0,0,0,0.08)`）
- [ ] **Status Area**：放时间、信号、WiFi、电量图标，`height: 44px`
- [ ] **Nav Area**：放 Logo、搜索、通知按钮，`height: 52~56px`
- [ ] **Sticky 架构下不需要 `.page { padding-top }`**：Header 作为 sticky 元素自然占据文档流顶部空间，内容接续即可。只需 `.page { padding-bottom: ~110px }` 给 Tab Bar 留位
- [ ] `--nav-bg` / `--tab-bg` 必须在 `:root` 和 `[data-theme="dark"]` 中分别定义，alpha 0.6~0.82（半透明才有毛玻璃效果）
- [ ] Tab Bar（底部固定导航）：在手机原型内使用 **单滚动容器 + Sticky 架构**（`.phone-mockup` 固定 `height: 900px` + `overflow: hidden`；`.app` 设 `height: 100%; overflow-y: auto` 成为唯一滚动容器；`.tab-bar` 用 `position: sticky; bottom: 0; margin-top: -自身高度`），这样 Tab/Header 粘在**手机屏幕边界**（不是浏览器窗口）、毛玻璃生效、Tab 不跟随滚动。详见 Step 5.6。**不要**用 `position: fixed`（穿透外壳）、`position: absolute`（跟随滚动）、自适应高度（sticky 会粘到浏览器窗口）或 Flex 三层独立滚动（毛玻璃失效）。

**Content Width — 全宽背景 + 内容宽度约束（Web / 多端）:**

核心原则：**背景全宽铺通，内容受限。**

| 元素类型 | 背景 | 内容文字/元素 |
|---------|------|-------------|
| 导航栏 `.nav` | 全宽 `width: 100%` | 内层 `.nav__inner` 约束 `max-width: 1600px` |
| Hero 横幅 | 全宽 `width: 100%` | `.hero__content` 约束 `max-width: 1600px` |
| CTA Banner | 全宽 `width: 100%` | `.cta-banner__inner` 约束 `max-width: 1600px` |
| 普通 Section | 可全宽或约束 | `.section` 约束 `max-width: 1600px` |

**实现方式 — 标准模板：**

```html
<!-- 导航栏结构：外层全宽，内层约束内容 -->
<nav class="nav">
  <div class="nav__inner">
    <a class="nav__logo">Logo</a>
    <div class="nav__links">...</div>
    <a class="nav__cta">购买</a>
  </div>
</nav>

<!-- Hero 结构（__inner 约束，__content 内部排版） -->
<section class="hero">
  <div class="hero__bg"></div>           <!-- 全宽背景 -->
  <div class="hero__gradient"></div>     <!-- 全宽渐变 -->
  <div class="hero__inner">              <!-- 内容约束层 -->
    <div class="hero__content">
      <div class="hero__eyebrow">...</div>
      <h1>标题</h1>
      <p>副标题</p>
      <div class="hero__actions">...</div>
    </div>
  </div>
</section>

<!-- CTA Banner 结构 -->
<section class="cta-banner">
  <div class="cta-banner__inner">
    <div class="cta-banner__text">...</div>
  </div>
</section>
```

```css
/* ===== 全宽背景容器 ===== */
.nav {
  position: fixed;
  top: 0; left: 0; right: 0;
  width: 100%;
  z-index: 100;
  background: var(--nav-bg);
  backdrop-filter: blur(20px) saturate(180%);
  -webkit-backdrop-filter: blur(20px) saturate(180%);
}

/* ===== 内容约束层（关键） ===== */
.nav__inner {
  max-width: 1600px;
  margin: 0 auto;
  padding: 0 48px;
  height: 64px;
  display: flex;
  align-items: center;
  gap: 40px;
}

/* ===== Hero 背景全宽，内容约束 ===== */
.hero {
  width: 100%;
  position: relative;
}

.hero__bg {
  position: absolute; inset: 0;
  /* 全宽背景图 */
}

.hero__gradient {
  position: absolute; inset: 0;
  /* 全宽渐变叠加 */
}

.hero__inner {
  position: relative; z-index: 2;
  max-width: 1600px;
  margin: 0 auto;
  padding: 120px 48px 80px;
  min-height: 600px;
  display: flex;
  flex-direction: column;
  justify-content: center;
}

.hero__content {
  /* 内部排版，不控制宽度 */
}

/* ===== CTA Banner 同理 ===== */
.cta-banner {
  width: 100%;
}

.cta-banner__inner {
  max-width: 1600px;
  margin: 0 auto;
  padding: 80px 48px;
}

/* ===== 普通 Section ===== */
.section {
  width: 100%;
  padding: 80px 0;
}

.section__inner {
  max-width: 1600px;
  margin: 0 auto;
  padding: 0 48px;
}

/* ===== 超宽屏（>1600px）时放宽 ===== */
@media (min-width: 1600px) {
  .nav__inner,
  .hero__content,
  .cta-banner__inner,
  .section {
    max-width: 1600px;
    padding-left: 48px;
    padding-right: 48px;
  }
}

/* ===== 平板（768px~1024px）===== */
@media (max-width: 1024px) {
  .nav__inner,
  .hero__content,
  .cta-banner__inner,
  .section {
    padding-left: 32px;
    padding-right: 32px;
  }
}

/* ===== 移动端（<768px）===== */
@media (max-width: 768px) {
  .nav__inner { padding: 0 24px; }
  .hero__inner { padding: 100px 24px 60px; }
  .cta-banner__inner { padding: 60px 24px; }
  .section__inner { padding: 0 24px; }
}
```

**⚠️ 常见错误（必须避免）：**
- ❌ 直接给 `.nav` 加 `max-width: 1600px` — 背景会缩到中间，两侧露出页面底色
- ❌ Hero 文字 `padding: 0` 贴边 — 大屏（1920px）文字贴到屏幕边缘，可读性极差
- ❌ CTA Banner 背景和内容共用一个容器 — 背景无法全宽延伸
- ✅ **正确结构**：外层全宽容器 + 内层约束内容层（如 `.__inner` / `.__content`）

**Practical test — read your CSS and mentally simulate:**
1. Set `html[data-theme="light"]` — does the hero look right? Are buttons visible? Is text readable? Are there any white-on-light failures?
2. Set `html[data-theme="dark"]` — does the same element still look good? Any black-on-black or white-on-white failures? Do adjacent sections have enough contrast?
3. If something fails → fix both mode values, then re-verify.

**The golden rule: Every hardcoded color that sits on a background must have a counterpart for the opposite mode. If in doubt, use a CSS variable.**

**Strategy for hero sections in luxury/premium brands:**
The safest approach for hero-heavy pages (car brands, luxury, portfolio) is to **keep the hero dark in BOTH modes** — this is standard luxury brand practice. Define hero-specific text variables (`--hero-text`, `--hero-text-muted`) that stay white in both modes, while the rest of the page adapts normally. This avoids the complexity of designing two full hero backgrounds.

### Step 10: Image Sourcing Workflow (MANDATORY — Unsplash First, AI as Fallback)

Every UI page needs real imagery. **Default source = Unsplash.** AI-generated imagery is a **fallback only**, not the default choice.

#### 10.0 Decision Tree — Unsplash vs. AI (MUST follow)

```
需要配图？
│
├── 1. 默认先用 Unsplash（按 10.2 流程）
│
├── 2. 识别 Unsplash 无法胜任的场景（任一命中即触发询问）：
│     a) 需要跨多张图的品牌视觉 100% 一致
│        （同一虚构品牌的不同车型 / 产品 / 系列）
│     b) 小众品牌 / 虚构 IP / 特定人物，Unsplash 搜不到可用资源
│     c) 需要特定构图、光线、色调、材质，实拍库完全匹配不上
│
└── 3. 若命中 2 中任一条 → 先询问用户是否切换到 AI 生成
      │
      └── 询问话术骨架（给 2-3 个选项，不替用户做主）：
          - 继续用 Unsplash 找"风格接近"的图（告知将是不同品牌混搭）
          - 用某个真实品牌拼凑（告知具体品牌名和局限）
          - 用 AI 生成（告知需等待 + 模型选择）
```

**⚠️ 禁止：** 不询问直接切到 AI 生成。即使你判断 Unsplash 效果会很差，也必须先让用户选择。

#### 10.0.1 AI 生图备忘（仅在用户选择"AI"分支时启用）

- **模型优先级**：Gemini-3.0-Pro-Image（稳定）> Hunyuan-Image-V3（队列常满载，容易 timeout）
- **切换命令**：`/model:text-to-image gemini-3.0-pro-image`
- **尺寸建议**：Hero 用 `1536x1024` 横版，卡片/方图用 `1024x1024`
- **保证品牌一致性的关键** —— 统一 prompt 前缀骨架：
  ```
  [主体描述]，[品牌色/材质/光线统一描述]，[氛围统一描述]，
  [美学锚点（如"Porsche Taycan × Lucid Air aesthetic"）]，
  hyper realistic 8k commercial photography
  ```
  每张图只改主体描述，其余部分完全一致，这样 8~10 张图会呈现"同一品牌"的视觉家族感。
- **输出目录**：指定 `output_dir` 到项目 `images/ai-gen/` 再 rename 覆盖目标文件名，避免文件名带时间戳。
- **格式**：Gemini 输出 PNG（1-1.5MB/张），HTML 中改用 `.png` 后缀即可，浏览器原生支持。

#### 10.1 Identify image requirements

When building the page, list every image needed:
- Hero/background image (1 hero photo)
- Section images (e.g., product shots, feature images)
- Card thumbnails (1–3 per card row)
- Team/avatar photos (for About/Team sections)

#### 10.2 Select Unsplash photos

Use Unsplash's curated collections or photo IDs to find high-quality, consistent images. For each image, pick a specific Unsplash photo ID from the table below, or search Unsplash using `web_search` for the right photo.

**Common image types and recommended search terms:**

| Image Type | Unsplash Search Term |
|---|---|
| Luxury car / sports car | `luxury car dark dashboard` or `sports car editorial` |
| Technology / product | `minimal product photography` or `tech device studio` |
| Nature / green energy | `forest sunlight minimal` or `clean energy wind` |
| Portrait / person | `professional portrait studio` or `creative director` |
| Architecture | `modern architecture concrete` or `luxury interior minimal` |
| Abstract / gradient | `abstract gradient purple` or `neon lights dark` |
| Office / workspace | `minimal workspace natural light` |
| Fashion / lifestyle | `editorial fashion photography` |

**Tip:** Use `web_search` to find the right Unsplash photo ID for your specific theme. Search: `site:unsplash.com [description]`.

#### 10.2.1 Check photo dimensions BEFORE downloading

**⚠️ Critical: Always verify photo dimensions before downloading.** A photo with insufficient resolution will be blurry on high-DPI screens.

**Dimension check method — use curl HEAD request:**

```bash
# Check file size of a candidate photo before downloading
curl -sI "https://images.unsplash.com/photo-[PHOTO_ID]?w=1200&q=80" \
  | grep -i content-length
```

- If `content-length` < **300KB** for a card thumbnail → resolution is likely too low, pick a different photo ID
- If `content-length` < **100KB** for an avatar → resolution too low
- If Unsplash returns HTTP 403/404 → photo unavailable, try different ID
- After confirming size is adequate, then proceed with full download

**Dimension reference table:**

| Image type | Min width | Min content-length (估算) | Action if too small |
|---|---|---|---|
| Hero (full-width) | 1200px | ≥ 400KB | Pick different photo |
| Card thumbnail | 600px | ≥ 150KB | Pick different photo |
| Avatar (mobile app) | 300px | ≥ 80KB | Pick different photo |
| Section image | 800px | ≥ 200KB | Pick different photo |

**Decision flow:**
1. Search Unsplash → get candidate photo ID
2. `curl -sI` → check content-length
3. Size OK → download; Size too small → go back to step 1, pick another photo ID
4. Download → verify file size again (`ls -la`)
5. File < 1KB or broken → use Picsum fallback

#### 10.3 Download images to local directory

Create a project-local `images/` folder and download images using `curl`:

```bash
# Create images directory in the project (use workspace-relative paths)
mkdir -p ./[project-name]/images

# Download an image — use the correct Unsplash photo ID
curl -L "https://images.unsplash.com/photo-[PHOTO_ID]?w=1920&q=80&auto=format&fit=crop" \
  -o "./[project-name]/images/hero.jpg"

# For card thumbnails (min 600px wide to avoid blurry on retina)
curl -L "https://images.unsplash.com/photo-[PHOTO_ID]?w=800&q=80&auto=format&fit=crop" \
  -o "./[project-name]/images/card-01.jpg"

# For avatar / portrait (min 300px, mobile app use 400px)
curl -L "https://images.unsplash.com/photo-[PHOTO_ID]?w=400&q=80&auto=format&fit=crop" \
  -o "./[project-name]/images/avatar-01.jpg"

# Fallback: if Unsplash returns a tiny file (<1KB) or is inaccessible,
# use Picsum as a reliable fallback:
curl -L "https://picsum.photos/1920/1080" \
  -o "./[project-name]/images/hero.jpg"
curl -L "https://picsum.photos/800/600" \
  -o "./[project-name]/images/card-01.jpg"
```

**Image sizing guidelines:**
- Hero / full-width background: 1920px wide (`?w=1920&q=80`)
- Section images: 1280px wide (`?w=1280&q=80`)
- Card thumbnails: 800px wide (`?w=800&q=80`) — **minimum 600px**
- Avatar / portrait: 400px wide (`?w=400&q=80`) — **minimum 300px**
- Always add `&auto=format&fit=crop` for optimal format and cropping

**⚠️ Minimum size rule — prevent blurry images:**
**图片尺寸不得小于页面宽度的 50%，否则在高 DPI/Retina 屏幕上显示会模糊。**

推理规则：
- 桌面端页面宽度通常 1200–2560px，图片需 ≥ 600px
- 移动端 App 页面宽度 375–430px，图片需 ≥ 187px（建议取整到 400px 留余量）
- 通用安全值：卡图 ≥ 600px、头像 ≥ 300px（移动端 App ≥ 400px）

**Verification workflow (do BEFORE download):**
```bash
# Step 1: Check content-length via HEAD request
curl -sI "https://images.unsplash.com/photo-[PHOTO_ID]?w=1200&q=80" \
  | grep -i content-length
# Content-Length: 523871 → OK (≥ 300KB)
# Content-Length: 58000 → Too small, pick another photo

# Step 2: Only if size is adequate, download
curl -L "https://images.unsplash.com/photo-[PHOTO_ID]?w=1920&q=80&auto=format&fit=crop" \
  -o "images/hero.jpg"

# Step 3: Post-download double check
ls -la images/
# <1KB → download failed, retry with Picsum or different ID
```

#### 10.4 Dual-mode images (for dual-mode pages)

For pages with dark + light mode, images should adapt:
- **Best approach**: Use CSS `filter` — dark mode images are naturally darker, so adding `filter: brightness(0.9) contrast(1.05)` in `[data-theme="light"]` makes them feel consistent with a light UI
- **Alternative**: Download two versions — a dark version and a bright/editorial version, swap them with `src` changes in JavaScript
- **Avoid**: Never put a bright photo in a dark hero — always use an appropriately toned photo for the dark context

#### 10.5 Reference local images in HTML

Use local paths in the HTML instead of Unsplash hotlinks:

```html
<!-- Hero — dark-appropriate photo, local file -->
<div class="hero-visual">
  <img src="images/hero-car.jpg" alt="Luxury car" />
</div>

<!-- Card — CSS handles dark/light adaptation via filter or dual-src -->
<img src="images/card-product-light.jpg" data-dark-src="images/card-product-dark.jpg" alt="Product" />
```

**Image attribution:** Always credit Unsplash photographers in an `images/credits.txt` file or in the page footer:
```
Photos from Unsplash:
- [Photographer Name](https://unsplash.com/photos/[ID]) — [description]
```

#### 10.6 Rounded corners for all images (MANDATORY)

**Every `<img>` tag MUST have a matching CSS rule applying rounded corners.** Raw rectangular images feel unfinished; rounded corners are a hallmark of polished Apple-style UI.

- Hero images → `border-radius: var(--radius-lg)` (16px)
- Card thumbnails → `border-radius: var(--radius-md)` (12px)
- Avatar / small thumbnails → `border-radius: var(--radius-sm)` (8px)
- Full-bleed section images → `border-radius: var(--radius-xl)` (20px) or larger

Example CSS:
```css
/* Global — every image: cover fill + rounded corners */
img {
  border-radius: var(--radius-md);
  object-fit: cover;       /* fill by shortest edge, crop excess, no gaps */
  object-position: center;  /* crop from center */
}

/* Hero — extra round */
.hero-visual img,
.hero-visual .hero-car {
  border-radius: var(--radius-lg);
}
/* Cards — medium round */
.model-card img,
.card-thumb {
  border-radius: var(--radius-md);
}
/* Avatar — fully round */
.avatar {
  border-radius: 50%;
  object-fit: cover;
}
```

#### 10.7 Do this for every image slot

Never leave `<img>` tags with `src=""` or broken placeholder URLs. Every image slot must be filled with a real, downloaded photo and have rounded corners applied before the page is presented.

## Release Workflow (MANDATORY when packaging for marketplace)

> ⛔ **NEVER hand-roll the zip file.** Every release goes through `scripts/release.sh`, which enforces the agreed 8-step pipeline.

### Directory contract

```
~/.workbuddy/
├── skills/
│   ├── apple-design-local/   ← 本地 fork（在这里开发、迭代）
│   └── apple-design-skill/   ← 市场版干净副本（name: apple-design）
└── releases/
    └── apple-design/         ← 所有历史 zip + RELEASES.md 都归档在这里
```

### Command

```bash
bash scripts/release.sh                     # auto patch bump (1.7.1 → 1.7.2)
bash scripts/release.sh patch               # same as above
bash scripts/release.sh minor               # 1.7.1 → 1.8.0
bash scripts/release.sh major               # 1.7.1 → 2.0.0
bash scripts/release.sh 1.9.0               # explicit version
bash scripts/release.sh patch ref.html      # also smoke-test a reference page
```

### The 8-step pipeline (all automatic)

1. **Preflight on local** — frontmatter complete, `allowed-tools` contains `AskUserQuestion`, no hardcoded `/Users/...` paths, scripts `chmod +x`, **all files have recognised extensions** (skillhub rejects bare `LICENSE` / extensionless files), optional icon smoke test
2. **Bump version** in `apple-design-local/SKILL.md`
3. **`rsync` local → skill** (the market fork)
4. **Rewrite frontmatter** in skill fork: `name: apple-design-local` → `name: apple-design`
5. **Build zip** named `apple-design-v<VERSION>-<sha8>.zip`, archive root = `apple-design/`
6. **Drop artifacts** in `~/.workbuddy/releases/apple-design/`: zip + `.sha256` sidecar
7. **Append RELEASES.md** entry with version / size / SHA256 / bump kind
8. **`open -R`** Finder — cursor lands directly on the new zip, drag to skillhub

Any preflight failure → exit 1 and refuse to build. The failures it catches are the exact same bugs that bricked earlier marketplace versions (no `AskUserQuestion`, hardcoded `/Users/...` paths, blank-square icons).

## Quick Reference

| Need | Token / Value |
|------|---------------|
| Primary action color | `var(--apple-blue)` → `#007AFF` |
| Page background | `var(--bg-primary)` |
| Card background | `var(--bg-secondary)` |
| Body text | `var(--label-primary)` |
| Secondary text | `var(--label-secondary)` |
| Body font | `var(--font-system)` |
| Code font | `var(--font-mono)` |
| Card radius | `var(--radius-lg)` → 16px |
| Touch target | 44px minimum |
| Base grid | 4px |

## Key Differentiators

To achieve authentic Apple quality:
1. **Continuous (squircle) corners** — use `border-radius` with large values, or SVG clip-path for pixel-perfect squircle
2. **System color palette only** — avoid arbitrary hex colors; stick to the token set
3. **4pt grid** — all spacing in multiples of 4px
4. **Spring animations** — never use linear easing for UI motion
5. **Translucency over opacity** — prefer `backdrop-filter` blur over flat overlays
6. **Thin borders** — use 0.5px or 1px borders with low-opacity white/black
7. **SF Symbols aesthetic** — thin, optically balanced icons that match text weight
