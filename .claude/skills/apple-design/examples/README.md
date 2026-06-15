# Examples — 用 apple-design 做的真实案例

三个完整项目，全部由 `apple-design` skill 生成，覆盖 Mobile App / Web 官网 / 多调色板多场景。

## 1. HydroFlow · 运动水壶品牌 App

**路径**：[`hydroflow-app/`](./hydroflow-app/)
**设备**：Mobile（430×900 手机原型）
**主题**：自然薄荷绿 + 奶白底
**看点**：圆环饮水进度、7 天柱图、产品横滑、地球日 banner、社区打卡

本地预览：
```bash
open examples/hydroflow-app/index.html
```

---

## 2. PUFFY · 潮玩盲盒品牌 App

**路径**：[`puffy-toy-app/`](./puffy-toy-app/)
**设备**：Mobile（430×900 手机原型）
**主题**：奶油马卡龙（糖果粉 `#FF6BB5` + 蜜桃橙 + 薄荷 + 薰衣紫）
**看点**：抓盒 sticker 风格 hero、IP 圆形头像、抽盒进度卡、收藏 6×2 格、欧气广场 feed

本地预览：
```bash
open examples/puffy-toy-app/index.html
```

---

## 3. NOVA · 新势力电车品牌官网

**路径**：[`nova-cars/`](./nova-cars/)
**设备**：Web Desktop（1440+ 响应式）
**主题**：暗色高级（电光青 `#00D4FF` + 深蓝 `#0066FF`）
**看点**：全屏 Hero + 网格扫描线 + 青色光晕 / 三款车型对比 / 5 卡 Tech Grid / 数据条 / 5 列 Footer

**特殊说明**：所有车型 / 内饰 / 技术特写配图由 **AI（Gemini-3.0-Pro-Image）** 统一生成，品牌视觉 100% 一致。这是 Step 10.0 决策树里"Unsplash 找不到虚构品牌的跨图一致性"场景的最佳实践。

本地预览：
```bash
open examples/nova-cars/index.html
```

---

## 快速全看一遍

```bash
cd examples
python3 -m http.server 8080
# 浏览器打开：
#   http://localhost:8080/hydroflow-app/
#   http://localhost:8080/puffy-toy-app/
#   http://localhost:8080/nova-cars/
```

---

## 这些案例用了 skill 的哪些能力？

| 能力 | HydroFlow | PUFFY | NOVA |
|------|:---:|:---:|:---:|
| Step 1A.2 主题库调色板 | ✅ Nature/Mint | ✅ Pastel/Cotton Candy | ✅ Dark Premium/Midnight Steel |
| Step 5.1 Mobile 间距系统 | ✅ | ✅ | — |
| Step 5.2 双击 Status Bar 切换主题 | ✅ | ✅ | — |
| Step 5.5 Remix Icon | ✅ | ✅ | ✅ |
| Step 5.6 单滚动容器 + Sticky | ✅ | ✅ | — |
| Step 8 Dark Mode | ✅ | ✅ | ✅ |
| Step 9 Content Width 全宽约束 | — | — | ✅ |
| Step 10 图片工作流 | ✅ Unsplash | ✅ Unsplash | ✅ AI 兜底 |

---

想做类似案例？跟 AI 说：
- "做一个薄荷绿运动水壶 App 首页"
- "做一个奶油色潮玩抽盒 App"
- "做一个暗色科技感的新势力汽车官网"

AI 会按 Step 1~10 全流程生成。
