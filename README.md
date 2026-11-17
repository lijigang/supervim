# Supervim

Supervim 是一个原生 macOS 菜单栏应用，目标是提供 Vimium 风格的系统级键盘控制。它使用 Swift 和 AppKit，不用 Electron，运行时不联网，也不记录击键。

Supervim is a native macOS menu-bar app for Vimium-style, system-wide keyboard control. It uses Swift and AppKit, not Electron. The running app does not use the network and does not record keystrokes.

**任务 13 把菜单栏换成模式显示。** 状态标题是 Normal、Insert 或 Paused。Hint 也显示成 Normal。菜单可以暂停、恢复、打开设置和退出。暂停会写入设置，下次启动仍然暂停。设置窗口可以加入当前前台应用、移除排除项，以及切换登录启动偏好。登录项只保存偏好，不向系统注册。排除列表默认仍是 Terminal、iTerm、Emacs；命中时按键原样放过，包括暂停键。

**Task 13 replaces the menu-bar placeholder with the mode.** The status title is Normal, Insert, or Paused. Hint is shown as Normal. The menu can pause, resume, open settings, and quit. Pause is written to settings and restored on the next launch. The settings window can add the frontmost app, remove an exclusion, and toggle the launch-at-login preference. That preference is stored only; nothing registers a login item. The exclusion list still defaults to Terminal, iTerm, and Emacs, and a match passes every key through, including the pause chord.

**任务 10 为当前窗口里已经扫到的可点击元素显示透明、不抢焦点的标签。** 应用层调用 `HintOverlayControlling`：`refreshClickables()` 在钩子外刷新，`enterHint` 显示标签，`receiveHintKey` 接收后续按键，`cancelHint` 取消。`f` 键入完整标签后，在元素中心左键点击并关掉标签。`F` 用同一套标签，点击时按住 Command，不是右键菜单。Esc、无效输入、没有目标或扫描不可用都会取消，并且不点击。点中或取消后用 `endHint` 回到 Normal。Safari、Finder 和系统设置上的 200ms 与 90% 覆盖率这次没有测量。

**Task 10 shows transparent, non-activating labels on clickable elements already scanned in the current window.** The app calls `HintOverlayControlling`: `refreshClickables()` off the hook, `enterHint` to show labels, `receiveHintKey` for later keys, and `cancelHint` to dismiss. `f` clicks the center of an element with the left button once its full label is typed, then hides the labels. `F` uses the same labels and holds Command for the click. It is not a context menu. Escape, invalid input, no targets, or an unavailable scan all cancel without clicking. A click or a cancel returns to Normal through `endHint`. The 200ms and 90% coverage targets in Safari, Finder, and System Settings were not measured.

**任务 11 把滚动、应用快捷键和 f/F 接到正在运行的钩子。** 有辅助功能和输入监控权限时，先启动 AXScanner，再安装事件钩子。钩子与菜单共用同一个解释器。选不到可滚动区域时，原来的按键交还。进入 Hint 时调用 `HintController` 显示标签，后续按键交给它。`?` 交给 `HelpCommandHandling`，没人认领就放过。`yy` 沿用任务 9 的浏览器名单。权限缺失时不装钩子。微信、备忘录和 Safari 地址栏不吞字仍未测。

**Task 11 connects scrolling, application shortcuts, and f/F to the running hook.** When Accessibility and Input Monitoring are both granted, it starts AXScanner and then installs the event tap. The hook and the menu share one interpreter. A scroll with no target gives the original key back. Entering Hint calls `HintController` to show labels, and later keys go to it. `?` goes to `HelpCommandHandling`, and passes through when nobody claims it. Copy URL keeps task 9's browser list. Missing permissions do not install the hook. Not swallowing characters in WeChat, Notes, and the Safari address bar is still untested.

**任务 12 用 `?` 打开快捷键帮助，再用 `?` 或 Esc 关闭。** 文案从 `CommandMap` 生成。`/`、`F`、`?` 标成与 Vimium 不同，`/` 写成 `Command+F`。帮助和标签共用同一块不激活面板。`MenuHookAssembly` 把 `HelpController` 交给会话的 `help`。普通模式下 Esc 关掉帮助并吞掉这一键；Hint 和 Insert 仍用自己的 Esc。开始 `f` / `F` 时先收起帮助。没有在屏幕上看到这块面板。

**Task 12 opens the shortcut sheet with `?` and closes it with `?` or Esc.** The text comes from `CommandMap`. `/`, `F`, and `?` are marked as different from Vimium, and `/` is written as `Command+F`. Help and hint labels share one non-activating panel. `MenuHookAssembly` passes `HelpController` as the session's `help`. In Normal, Esc closes the sheet and swallows the key. Hint and Insert keep their own Esc. Starting `f` / `F` hides the sheet first. The panel was not seen on a display.

**任务 14 在缺少辅助功能或输入监控时显示引导。** 引导列出仍缺的那一项，并提供打开系统设置里对应面板的链接。重新检测发现两项都已授予后，才走任务 11 的启动：先扫描焦点，再安装事件钩子。授权之后，当前进程不保证不用退出重开就能用上该权限；这一点没有在真机上验证。未签名的 Supervim 重新构建后，可能要再授权一次。权限检测放在可注入的接口后面，测试用替身，不申请真实的辅助功能或输入监控权限。

**Task 14 shows guidance when Accessibility or Input Monitoring is missing.** The guide lists each missing permission and links to that pane in System Settings. A later read that finds both granted is what starts task 11's runtime: the focus scanner, then the event tap. Granting a permission does not guarantee this process can use it without quitting and reopening; that behavior is not verified. An unsigned Supervim may need to be allowed again after it is rebuilt. Permission checks sit behind an injectable interface. Tests use a stand-in and do not request the real permissions.

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
- [任务 8 测试记录 / Task 8 test evidence](docs/task8-test-evidence.md)
- [任务 9 测试记录 / Task 9 test evidence](docs/task9-test-evidence.md)
- [任务 10 测试记录 / Task 10 test evidence](docs/task10-test-evidence.md)
- [任务 11 测试记录 / Task 11 test evidence](docs/task11-test-evidence.md)
- [任务 12 测试记录 / Task 12 test evidence](docs/task12-test-evidence.md)
- [任务 13 测试记录 / Task 13 test evidence](docs/task13-test-evidence.md)
- [任务 14 测试记录 / Task 14 test evidence](docs/task14-test-evidence.md)

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

直接 `swift run` 时，系统不会把裸二进制当成带 `LSUIElement` 的应用包。程序会改用 accessory 激活策略，避免开发时出现 Dock 图标。状态栏显示 Normal、Insert 或 Paused，菜单里有暂停、恢复、设置和退出。缺少辅助功能或输入监控时，启动会打开权限引导，菜单里多一项 Permissions，并且不安装事件钩子。两项都授予之后，再重新检测，然后先跑焦点扫描，再安装事件钩子；`f` / `F` 交给标签浮层，`?` 打开帮助。授权不保证不用退出再打开就能生效。

发布构建：

```bash
scripts/assemble-app.sh release
```

## 工程结构 / Layout

```text
Package.swift                 SwiftPM 描述，macOS 13+，Swift 6
Sources/SupervimCore          纯逻辑，不导入 AppKit 或事件框架。含 ModeMachine、KeyParser、HintLabeler、CommandMap、Settings、EventInterpreter、CommandFollowThrough、MenuBarController、HintSession、HelpSheet、PermissionGuide
Sources/SupervimSystem        系统适配。含菜单栏预检、UserDefaults、EventTap、AXScanner、Actuator、标签浮层、帮助浮层、任务 11 的滚动目录和命令会话，以及权限探测。macOS 上另有 CGEvent 合成、不激活面板和输入框聚焦
Sources/Supervim              菜单栏应用。缺权限时显示引导；两项都授予后启动 AXScanner 并安装事件钩子，f/F 交给 HintController，? 交给 HelpController
App/Supervim/Info.plist       应用包清单，含 LSUIElement
scripts/assemble-app.sh       组装未签名 .app
Tests                         XCTest
.github/workflows/ci.yml      macos-latest 上构建、测试、组装
docs                          已批准的中文宪法、规格、计划和任务
.taskmaster/tasks/tasks.json  任务 1–15，供 task-master 读取
```

应用包不把手写 Xcode 工程或 XcodeGen 当作第二份目标定义。原因写在 [计划](docs/plan.md#任务-1-的应用包脚手架)。

## CI

推送和 pull request 都会在 `macos-latest` 上执行 `swift build`、`swift test`、十三个覆盖率脚本和 `scripts/assemble-app.sh`，并检查组装结果里的 `LSUIElement`。覆盖率脚本分别要求 `ModeMachine.swift`、`KeyParser.swift`、`HintLabeler.swift`、`CommandMap.swift`、`Settings.swift`、`UserDefaultsSettingsStore.swift`、`EventInterpreter.swift`、`EventTap.swift`、`Actuator.swift`、`AXScanner.swift`、`MenuBarController.swift`、`HintSession.swift`、`HintOverlay.swift`、`CommandFollowThrough.swift`、`NormalCommandSession.swift`、`ScrollAreaCatalog.swift`、`SupervimRuntime.swift`、`PermissionGuide.swift`、`HelpSheet.swift` 和 `HelpOverlay.swift` 的行覆盖率不低于 90%。`AXApplicationReader.swift`、`CGEventActuator.swift`、`HintOverlayWindow.swift`、`AXInputFocuser.swift`、`PermissionAccess.swift`、`MacHookAssembly.swift` 和菜单与引导的 AppKit 胶水只在 macOS 上编译，不计入这个门槛。

## 工作流工具 / Workflow tools

本仓库没有 spec-kit，也没有 task-master CLI。任务文件是按上游 schema 手写的，说明见 [任务文档](docs/tasks.md#task-master-格式)。测试记录写在 `docs/task1-test-evidence.md` 到 `docs/task14-test-evidence.md`。任务 15 还没有记录。
