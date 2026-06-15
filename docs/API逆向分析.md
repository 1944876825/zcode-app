# ZCode API 逆向分析报告

> 基于 zcode.z.ai web client (app_version=3.0.1) JS bundle 静态分析
> 2026-06-15 订正：第二、三节关于 OAuth/远程控制认证的描述经实测客户端 bundle (`index-DMg1tzSS.js`) 推翻，详见下方标注与 `API协议规格.md §7`

## 一、架构总览

zcode 采用 **Relay 中继远程控制架构**(类 VS Code Server):

```
手机APP (Flutter)          Relay 中继服务器              远程开发环境
  │  zcode.z.ai                │                          (运行 agent/文件系统)
  │                            │                          │
  ├─ WebSocket 长连接 ─────────→│                          │
  ├─ HTTP REST 调用 ──────────→│── RPC 转发 ──────────────→│
  │                            │                          │
  │←── 流式事件推送 (WS) ──────│←── agent 响应 ────────────│
```

客户端是**瘦客户端**:所有文件操作、代码执行、AI 推理都在远程环境完成,
客户端只负责发送指令和渲染结果。

## 二、认证机制

### URL 参数认证 — 两条互斥入口 ⚠️ (2026-06-15 实测订正)

zcode 客户端 (`index-DMg1tzSS.js`) 实测:URL 是否含 `remoteControlToken` 决定走哪条认证路径。

#### 路径 B — WebSocket (本会话所用, `/remote/v3`)
当前 URL 携带的参数即为 WebSocket 会话凭证:
- `sid` = session ID (d_xxx)
- `hash` = 认证哈希 (<base64 hash>)
- `mid` = 机器/设备 ID (<random mid>)
- `name` = 设备名称 (fedora)
- `app_version` = 3.0.1
- `t` = 时间戳
- 认证：4 步 HMAC 握手 + 依赖 cookie (acw_tc 30 分钟过期 + JS 挑战 cookie `_c_WBKFRo`)

#### 路径 A — REST token 直连 (`/web-remote`, 适合 APP)
- URL: `https://zcode.z.ai/web-remote?remoteControlToken=xxx&relayOrigin=xxx`
- token 直接拼进 URL path 调 REST,**无需 cookie/HMAC**
- ⚠️ 未亲测联通 (本会话无 remoteControlToken, 用 sid/mid/hash 当 token 调第三节端点全 404)
- 详见 `API协议规格.md §7.2`

### OAuth 认证 ⚠️ (2026-06-15 实测订正)
- 端点: `POST /api/v1/oauth/token` (实测存在, POST 空 body 返回 `{"code":3001,"msg":"parameter error"}`)
- **用途订正**: OAuth 是**模型供应商授权**(登录智谱 chat.z.ai / bigmodel 账号拿 API key 调 GLM),**不是**设备登录/会话认证。实测证据:
  - `clientId: client_P8X5CMWmlaRO9gyO-KSqtg`、`authorizeUrl` 指向 chat.z.ai
  - 代码全部绑在模型供应商逻辑上 (`oauth_provider_inactive` / `zai-auth→z.ai` / `oauth→bigmodel` / `BigModel 账号未注册`)
- ~~"用于获取 access_token / refresh_token"~~ —— 原描述不准确

### 远程控制认证 ⚠️ (2026-06-15 实测订正)
- `remoteControlToken` - REST 路径的 URL token (路径 A)
- `relayOrigin` - 中继服务器地址 (默认 window.location.origin)
- ~~"两者通过 OAuth 流程获取"~~ —— **此描述错误**。remoteControlToken 与 OAuth 无关,是另一套独立 URL token 体系,来源待从真实 `/web-remote` 会话抓包确认。

## 三、Relay API 端点 (REST 路径 A)

> 以下端点来自客户端 bundle,`${token}` = `remoteControlToken`。
> ⚠️ 本会话属路径 B (WebSocket),**未能用现有身份验证这些 REST 端点** (2026-06-15 实测全 404,因无 remoteControlToken)。
> 需从真实 `/web-remote` 会话抓到 remoteControlToken 后重新验证。

所有端点的 baseURL = relayOrigin (https://zcode.z.ai)

### 3.1 平台 RPC
```
POST /api/remote-control/platform/${token}
Content-Type: application/json

Body: { "method": "<method_name>", "args": [...] }
Response: { "result": ... }
```
通用 RPC 调用,可执行远程环境上的任意平台方法。

### 3.2 引导 / 工作区列表
```
GET /api/remote-control/windows/bootstrap/${token}
Response: { "workspaces": [...] }
```
获取可用工作区列表,返回所有项目。

### 3.3 工作区桥接 (核心)
```
POST /api/remote-control/windows/${token}/workspace-bridge
```
打开工作区桥接连接,之后通过 WebSocket 持续接收事件流。

### 3.4 移动端视图状态 (已有移动端支持!)
```
POST /api/remote-control/windows/${token}/mobile-view-state
```
更新移动端视图状态,zcode 后端已有此端点。

## 四、通信协议

### 4.1 消息格式
所有消息包含 `zcode_type` 字段标识类型,`requestId` 用于配对请求/响应。

### 4.2 消息类型 (zcode_type)

| 类型 | 方向 | 说明 |
|------|------|------|
| `bootstrap-request` | C→S | 引导请求,初始化连接 |
| `bootstrap-response` | S→C | 引导响应,返回工作区列表 |
| `workspace-list-request` | C→S | 请求工作区列表 |
| `workspace-list-response` | S→C | 工作区列表响应 |
| `workspace-reconnect-request` | C→S | 重连请求 |
| `workspace-reconnect-response` | S→C | 重连响应 |
| `workspace-bridge-open` | C→S | 打开工作区桥接 |
| `workspace-bridge-ready` | S→C | 桥接就绪 |
| `platform-request` | C→S | 平台 RPC 请求 |
| `platform-response` | S→C | 平台 RPC 响应 |
| `rpc-frame` | 双向 | RPC 通信帧 |
| `app-error` | S→C | 应用错误 |
| `workspace-bridge-error` | S→C | 桥接错误 |
| `bridge-degraded` | S→C | 桥接降级 |
| `mobile-diagnostic` | 双向 | 移动端诊断 |
| `mobile-view-state-update` | 双向 | 移动端视图状态 |

### 4.3 事件流 (通过 workspace-bridge WebSocket 推送)

AI Agent 相关:
| type/kind | 说明 |
|-----------|------|
| `agent_message_chunk` | AI 回复文本块 (流式) |
| `agent_thought_chunk` | AI 思考过程文本块 |
| `agent_activity` | Agent 活动状态 |
| `model-trajectory` | 模型调用轨迹 |
| `model_change` | 模型切换 |

Task 生命周期:
| type/kind | 说明 |
|-----------|------|
| `task_run_started` | 任务开始执行 |
| `task_complete` | 任务完成 |
| `task_error` | 任务出错 |
| `task_snapshot_updated` | 任务快照更新 (完整状态) |
| `task_token_usage_delta` | Token 用量增量 |

文件/代码:
| type/kind | 说明 |
|-----------|------|
| `diff` | 代码差异 |
| `diff-line` | 差异行 |
| `file` | 文件操作 |
| `command` | 命令执行 |

## 五、模型 API 格式

zcode 支持三种模型 API 格式 (通过 settings.modelProvider.apiFormat 配置):

| 格式 | 端点 | 用于 |
|------|------|------|
| `anthropic-messages` | `/v1/messages` | Claude 系列 |
| `openai-chat-completions` | `/chat/completions` | OpenAI 兼容 (GLM 等) |
| `openai-responses` | `/responses` | OpenAI Responses API |

当前使用 GLM-5.2,走 openai-chat-completions 格式。

## 六、移动端已有支持

zcode 网页端**已内置移动端概念**,这为原生 APP 开发提供了便利:

- `mobile-view-state` API 端点已存在
- `mobileNavigationIntent`: `chat` / `home` 导航意图
- `MobileTaskHome`: 移动端任务首页组件
- `MobileCompactViewport`: 紧凑视口模式
- `MobileTextInputViewport`: 移动端文本输入视口
- `mobile-task-home-preferences`: 移动端任务首页偏好
- 支持 `organizeBy: workspace` 和 `sortBy` 排序

## 七、数据模型推断

### Workspace (工作区)
```
{
  workspaceKey / workspaceIdentity / workspacePath
  kind: "local" | "remote"
  taskId: string
  canBridge: boolean
}
```

### Task (任务/对话)
```
{
  id: string
  title: string
  workspaceId: string
  status: "running" | "complete" | "error"
  archived: boolean
}
```

### Message (消息)
```
{
  kind: "message"
  role: "user" | "assistant"
  content: string (markdown)
  model: string
  tokenUsage: { input, output, total }
}
```

### Settings
```
{
  modelProvider: {
    apiFormat: "openai-chat-completions" | "anthropic-messages" | "openai-responses"
    apiKey: string
    baseUrl: string
    model: string
  }
  agentMode: "confirm" | "auto-edit" | "plan" | "full-access"
}
```

## 八、实测发现 (probe 14-22)

### 8.1 协议层架构 (已完全验证)

```
WebSocket JSON 层 (type: auth_init/challenge/response/ack, data)
  └─ data.payload (zcode_type)
      ├─ bootstrap-request/response       ← 不需要 bridge
      ├─ workspace-list-request/response ← 不需要 bridge
      ├─ mobile-view-state-update        ← 不需要 bridge (fire-and-forget)
      ├─ workspace-bridge-open/ready/error← 需要 bridge
      └─ rpc-frame                       ← 需要 bridge
          └─ 自描述 varint 二进制序列化
              ├─ type=100 PromiseRequest  (C→S RPC 调用)
              ├─ type=102 EventListen     (C→S 订阅)
              ├─ type=200 Init            (S→C bridge 就绪)
              ├─ type=201 OK              (S→C 成功响应)
              ├─ type=202 Error           (S→C 错误)
              ├─ type=203 ErrorObject     (S→C 错误+stack)
              └─ type=204 EventFire       (S→C 事件推送)
```

### 8.2 不存在的 API

以下在 WebSocket data 层发送后**无任何响应** (不是 404,而是完全被忽略):
- `platform-request` (zcode_type) — 所有变体
- `task-snapshot-request`
- `task-messages-request`
- `task-create-request`
- `agent-prompt-request`
- `mobile-diagnostic`

### 8.3 不存在的 RPC 方法

通过 RPC bridge 发送后返回 "Method not found":
- `zcode-task.getMessages` — **消息不在 task channel**

### 8.4 存在但参数待修正的 RPC 方法

- `zcode-task.getTaskSnapshot` — 报 TypeError: Cannot read properties of undefined (reading 'model')

### 8.5 存在但无直接响应的方法

- `zcode-agent.sendPrompt` — 无报错无响应,可能需要先订阅事件流再发送

### 8.6 Bridge 稳定性问题

Bridge 依赖 ZCode 桌面端 host process 在线。
探测脚本与桌面端共用 device_sid 会导致连接冲突:
- 桌面端可能被踢掉 ("desktop-disconnected")
- 或探测脚本无法建立 bridge

**APP 必须使用独立的 device_sid。**

## 九、对 APP 开发的影响

### 好消息
1. 协议是结构化 JSON + 自描述二进制,易于用 Dart 解析
2. 已有移动端 API 端点,说明后端已考虑移动端
3. WebSocket 流式推送,适合移动端实时渲染
4. 不需要逆向 AI 模型 API,所有 AI 调用都在远程环境完成
5. 认证流程已完全掌握 (4步 HMAC 握手)
6. **(2026-06-15 新增)** 发现 REST token 直连路径 (路径 A),若可用可绕开 cookie 过期问题

### 挑战
1. 需要完整实现 Relay 协议客户端 (WebSocket + RPC bridge)
2. Bridge 连接需要桌面端在线,APP 可能无法独立工作
3. 需要获取独立 device_sid (避免和桌面端冲突)
4. RPC 方法名和参数格式尚未完全掌握
5. sendPrompt 的流式事件接收需要进一步验证
6. **(2026-06-15 新增)** 凭据保鲜是最大阻塞点: 路径 B 的 acw_tc 30 分钟过期 + `_c_WBKFRo` 需 JS 挑战; 路径 A 的 remoteControlToken 来源未知

### 下一步
1. **优先验证路径 A (REST)**: 从真实 `/web-remote` 会话抓 `remoteControlToken`,验证第三节端点能否联通 —— 若通,APP 用此路径最省事
2. 在桌面端保持在线时,用独立 device_sid 重新探测所有 RPC 方法
3. 重点关注 sendPrompt + EventListen 的组合使用
4. 找到加载任务历史消息的正确方法
5. 验证 getTaskSnapshot 的正确参数格式
