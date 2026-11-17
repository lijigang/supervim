# Supervim

Supervim 是一个原生 macOS 菜单栏应用，目标是提供 Vimium 风格的系统级键盘控制。它使用 Swift 和 AppKit，不用 Electron，运行时不联网，也不记录击键。

Supervim is a native macOS menu-bar app for Vimium-style, system-wide keyboard control. It uses Swift and AppKit, not Electron. The running app does not use the network and does not record keystrokes.

**任务 7 把按键接到模式、解析和命令。** 事件回调只读当前模式和已经缓存的焦点，再交给 KeyParser 和 CommandMap，决定放过、吞掉、一个动作或一次浮层更新。未知焦点、未知的普通模式按键，以及排除列表里的前台应用都会把事件交还系统。默认暂停键 Ctrl+Option+V 在解析器之外切换暂停。点击、滚动和浮层绘制还没有做，菜单栏占位程序也不会安装事件钩子。

**Task 7 wires keys to the mode, the parser, and the command map.** The event callback reads only the current mode and a cached focus, then asks KeyParser and CommandMap for a pass-through, a swallow, an action, or an overlay update. Unknown focus, an undefined Normal-mode key, and an excluded frontmost app all give the event back to the system. The default pause chord, Ctrl+Option+V, toggles pause outside the parser. Clicks, scrolling, and overlay drawing are not implemented, and the menu-bar placeholder does not install the tap.

## 文档 / Docs

- [宪法 / Constitution](docs/constitution.md)
- [规格 v0.1 / Spec](docs/spec.md)
- [计划 / Plan](docs/plan.md)
- [任务与依赖 / Tasks](docs/tasks.md)
- [任务 1 测试记录 / Task 1 test evidence](docs/task1-test-evidence.md)
- [任务 2 测试记录 / Task 2 test evidence](docs/task2-test-evidence.md)
- [任务 3 测试记录 / Task 3 test evidence](docs/task3-test-evidence.md)
- [任务 4 测试记录 / Task 4 test evidence](docs/task4-test-evidence.md)
- [任务 5 测试记录 / Task 5 test evidence](docs/task5-test-evidence.md)
- [任务 6 测试记录 / Task 6 test evidence](docs/task6-test-evidence.md)
- [任务 7 测试记录 / Task 7 test evidence](docs/task7-test-evidence.md)

规格文末单独列出了尚未能保证的平台行为。那些条目没有改写已批准的要求。

## 环境 / Requirements

- macOS 13 or later
- Swift 6
- Xcode, which provides the Swift toolchain and AppKit

Linux 可以编译并运行纯逻辑测试。菜单栏进程不能在 Linux 上运行。

## 构建与测试 / Build and test

在 macOS 上：

```bash
swift test
scripts/assemble-app.sh
open build/Supervim.app
```

`swift test` 会编译三个 SwiftPM 目标并运行 XCTest。`scripts/assemble-app.sh` 把调试版二进制装进 `build/Supervim.app`。这个包的 `Info.plist` 设置了 `LSUIElement=true`，所以通过 Finder 或 `open` 启动时没有 Dock 图标。包是未签名的，任务 15 才会做 DMG。

直接 `swift run` 时，系统不会把裸二进制当成带 `LSUIElement` 的应用包。占位程序会改用 accessory 激活策略，避免开发时出现 Dock 图标。占位菜单只有退出，不显示 Normal / Insert / Paused。

发布构建：

```bash
scripts/assemble-app.sh release
```

## 工程结构 / Layout

```text
Package.swift                 SwiftPM 描述，macOS 13+，Swift 6
Sources/SupervimCore          纯逻辑，不导入 AppKit 或事件框架。含 ModeMachine、KeyParser、HintLabeler、CommandMap、Settings、EventInterpreter
Sources/SupervimSystem        系统适配。含菜单栏预检、UserDefaults 设置存储，以及 EventTap 协议和 CGEventTap 适配
Sources/Supervim              菜单栏占位程序
App/Supervim/Info.plist       应用包清单，含 LSUIElement
scripts/assemble-app.sh       组装未签名 .app
Tests                         XCTest
.github/workflows/ci.yml      macos-latest 上构建、测试、组装
docs                          已批准的中文宪法、规格、计划和任务
.taskmaster/tasks/tasks.json  任务 1–15，供 task-master 读取
```

应用包不把手写 Xcode 工程或 XcodeGen 当作第二份目标定义。原因写在 [计划](docs/plan.md#任务-1-的应用包脚手架)。

## CI

推送和 pull request 都会在 `macos-latest` 上执行 `swift build`、`swift test`、六个覆盖率脚本和 `scripts/assemble-app.sh`，并检查组装结果里的 `LSUIElement`。覆盖率脚本分别要求 `ModeMachine.swift`、`KeyParser.swift`、`HintLabeler.swift`、`CommandMap.swift`、`Settings.swift`、`UserDefaultsSettingsStore.swift`、`EventInterpreter.swift` 和 `EventTap.swift` 的行覆盖率不低于 90%。

## 工作流工具 / Workflow tools

本仓库没有 spec-kit，也没有 task-master CLI。任务文件是按上游 schema 手写的，说明见 [任务文档](docs/tasks.md#task-master-格式)。测试记录写在 `docs/task1-test-evidence.md` 到 `docs/task7-test-evidence.md`。
