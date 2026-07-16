# PeekDock Protocol

Runtime Bridge 是任务状态权威源。Mac 控制台通过 HTTP + WebSocket/SSE 消费状态；物理 PeekDock 通过 USB Serial/JTAG 上的 JSON Lines 消费同一事件。无串口时由 macOS 桌面悬浮小屏消费同一份真实状态；只有显式 `npm run demo` 才使用 Mock 数据。

## 传输

- Mac UI：`WS /ws`，自动回退 `GET /events`（SSE）。
- API：HTTP/JSON，默认 `http://127.0.0.1:4173`。
- ESP32：115200 baud USB Serial/JTAG，每行一个 UTF-8 JSON 对象，以 `\n` 结束。
- 重连：Bridge 发送 `task_snapshot`，设备以它替换四个固定 Agent 槽位。

## 事件类型

- `task_snapshot`：全量任务列表，MVP 最多四项。
- `task_update`：单任务增量，按 `source` 写入对应 Agent 页。
- `transition_event`：`handoff_to_dock`、`return_to_mac` 等视觉转场提示。
- `action_event`：小屏上报用户动作，Mac Bridge 决定是否执行白名单操作。
- `heartbeat`：存活检查。
- `sync_snapshot`：请求权威层重发完整快照。

## Agent 顺序

1. `codex`
2. `claude`
3. `jimeng`
4. `browser`（也接受 `browser_agent`）

## Task Schema

```json
{
  "task_id": "codex_1721200000000",
  "source": "codex",
  "agent_name": "Codex",
  "title": "检查首页按钮并修复布局",
  "task_type": "coding",
  "status": "running",
  "status_text": "using tools...",
  "progress": 54,
  "updated_at": "2026-07-17T08:00:00.000Z",
  "screen_role": "dock_working",
  "agent_scene": "coding_room",
  "animation_key": "codex_running",
  "result_uri": "/demo-results/codex-review.html",
  "actions": []
}
```

状态只使用：`idle`、`running`、`needs_input`、`completed`、`failed`。进度未知时为 `-1`，前端不得伪造精确百分比。

## 示例

Bridge 到设备：

```json
{"type":"task_update","task":{"task_id":"jimeng_1","source":"jimeng","agent_name":"Jimeng","title":"生成产品主视觉","status":"completed","status_text":"老板，我做好啦","progress":100,"animation_key":"jimeng_completed","actions":["open_result"]}}
```

设备到 Bridge：

```json
{"type":"action_event","action":"switch_agent_next","source":"codex"}
```

```json
{"type":"action_event","action":"open_result","source":"jimeng","task_id":"jimeng_1"}
```

小屏永远不直接打开文件、执行命令或控制应用；所有动作由 Mac Bridge 校验并执行。

## Fixtures

- `mock-timeline.json`：结构化 mock 时间线。
- `demo-events.jsonl`：可直接写入串口的逐行事件。
