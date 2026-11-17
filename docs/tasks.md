# 任务与依赖

批准顺序如下。依赖没有满足时，不开始该任务。一个任务一个 PR，评审和所有者确认之后再进入下一个。

任务 1 到任务 6 已合并，状态是 `done`。任务 7 已实现，状态是 `done`。任务 8 到 15 是 `pending`。机器可读的同一份数据在 [`.taskmaster/tasks/tasks.json`](../.taskmaster/tasks/tasks.json)。

`priority` 只是 task-master 的字段。任务 1 标成 `high`，其余标成 `medium`。执行顺序以依赖为准，不表示其余任务可选。

## 依赖

```text
1 工程骨架、文档与 CI
├── 2 ModeMachine
├── 3 KeyParser ── 5 CommandMap ─┐
├── 4 HintLabeler                │
├── 6 Settings                   │
├── 8 AXScanner                  │
└── 9 Actuator                   │
                                 ▼
                    7 EventTap（依赖 2、3、5）
                                 │
         ┌───────────────────────┼───────────────────────┐
         ▼                       ▼                       ▼
10 Overlay 与 f/F          11 滚动、gi、放过下一键     13 菜单栏、暂停、设置
（依赖 4、7、8、9）         （依赖 7、8、9）            （依赖 6、7）
         │                                                   │
         ▼                                                   ▼
12 帮助                                                14 权限引导
         │                                                   │
         └──────────────────────┬────────────────────────────┘
                                ▼
              15 未签名 DMG、Release 与手工验收
              （依赖 10、11、12、13、14）
```

## 列表

| ID | 标题 | 依赖 | 状态 |
| --- | --- | --- | --- |
| 1 | 工程骨架、文档与 CI | 无 | done |
| 2 | ModeMachine 模式状态机 | 1 | done |
| 3 | KeyParser 按键序列解析 | 1 | done |
| 4 | HintLabeler 最短前缀标签 | 1 | done |
| 5 | CommandMap 命令映射 | 3 | done |
| 6 | Settings 本地设置 | 1 | done |
| 7 | EventTap 与模式、解析、命令接线 | 2、3、5 | done |
| 8 | AXScanner 与自动 Insert | 1 | pending |
| 9 | Actuator 点击、滚动与快捷键执行 | 1 | pending |
| 10 | Overlay 与 f/F 提示 | 4、7、8、9 | pending |
| 11 | 滚动、gi、放过下一键与应用快捷键 | 7、8、9 | pending |
| 12 | 快捷键帮助 | 10 | pending |
| 13 | 菜单栏、暂停、设置与排除列表 | 6、7 | pending |
| 14 | 权限引导 | 13 | pending |
| 15 | 未签名 DMG、Release 与手工验收 | 10、11、12、13、14 | pending |

## task-master 格式

对照过 claude-task-master 默认分支在 2026-11-17 的两处来源：

- `src/schemas/base-schemas.js` 里的 `TaskStatusSchema` 与 `BaseTaskSchema`
- `docs/task-structure.md` 里的 tagged 格式：`{ "master": { "tasks": [ ... ] } }`

两边不一致的地方：文档仍列出状态 `review`，当前 Zod 枚举没有 `review`，但有 `blocked`。本文件只使用两边都有的状态：`pending`、`in-progress`、`done`、`deferred`、`cancelled`。任务 1 用 `in-progress`，没有使用 `review`。

每条任务都有数值 `id`、`title`、`description`、`status`、`dependencies`、`priority`、`details`、`testStrategy` 和 `subtasks`。依赖是同一标签内的任务编号。

没有安装，也没有运行 `task-master` CLI，所以没有 `.taskmaster/config.json` 或 `.taskmaster/state.json`。不要把本文件说成 CLI 生成的。

`TaskGraphTests` 把上表的依赖和当前状态锁进了 XCTest。下一个任务开始时，要同时改 `tasks.json` 里的状态和这项测试，不能只改其中一边。
