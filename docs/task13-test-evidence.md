# 任务 13 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit，没有 CoreGraphics

因此下面能证明的是菜单文案、暂停恢复、排除列表和设置写入的先失败、后通过，以及 Linux 上 `MenuBarController.swift` 的覆盖率。不能证明状态栏真的画出来了，也不能证明 `Ctrl+Option+V` 在真机上被系统送到本进程。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。写本文时那次 CI 还没有结果。

## 范围

加了 `SupervimCore` 里的 `MenuBarController`。它根据模式给出状态标题和菜单项的启用状态，把暂停写进 `Settings`，并编辑排除列表和登录启动偏好。AppKit 窗口和状态栏在 `Sources/Supervim`，整段包在 `#if canImport(AppKit)` 里，Linux 上不编译。

`Settings.isPaused` 现在会在 `EventInterpreter` 启动时进入暂停，菜单暂停和暂停键都会把这个布尔值写回内存里的设置。应用目标不安装 `CGEventTap`，也不调用 `SMAppService`。

## 第一次运行：保存的暂停还没接上（RED）

时间：2026-11-17 07:03:14 UTC 到 07:03:23 UTC。命令：`swift test --filter 'EventInterpreterTests/testSavedPauseFlagStartsTheMachinePaused|EventInterpreterTests/testSavedPauseOnAnEditableFieldResumesToInsert'`。当时还没有菜单类型。退出码 1。构建日志里没有编译警告。

这两条测试能编译，因为它们只用已经存在的 `EventInterpreter`。失败原因是保存的 `isPaused` 被忽略，不是拼写错误。

```text
Test Suite 'EventInterpreterTests' failed at 2026-11-17 07:03:23.180
	 Executed 2 tests, with 5 failures (0 unexpected) in 0.002 (0.002) seconds
```

代表输出：

```text
testSavedPauseFlagStartsTheMachinePaused : XCTAssertEqual failed: ("normal") is not equal to ("paused")
testSavedPauseFlagStartsTheMachinePaused : XCTAssertEqual failed: ("...swallow...normal...scroll(...down...") is not equal to ("...passThrough...paused...")
testSavedPauseOnAnEditableFieldResumesToInsert : XCTAssertEqual failed: ("insert") is not equal to ("paused")
```

可编辑焦点上，旧实现先进入 Insert，暂停键再把它暂停，而不是从已经暂停的状态恢复到 Insert。

## 第二次运行：菜单测试没编译过（RED）

时间：2026-11-17 07:03:57 UTC 到 07:03:58 UTC。命令：`swift test --filter MenuBarControllerTests`。当时还没有 `MenuBarController.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/MenuBarControllerTests.swift:333:18: error: cannot find type 'MenuBarController' in scope
Tests/SupervimCoreTests/MenuBarControllerTests.swift:368:15: error: cannot find type 'MenuBarEffect' in scope
Tests/SupervimCoreTests/MenuBarControllerTests.swift:408:37: error: cannot find type 'FrontmostBundleProviding' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：快照标题是空字符串，菜单项是空数组，编辑器列表是空的，任意按键都放过并留在普通模式，暂停和设置都不写存储。空实现不是最终行为。

## 第三次运行：断言失败（RED）

时间：2026-11-17 07:04:12 UTC。命令同时过滤 `MenuBarControllerTests` 和上面两条解释器测试。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'EventInterpreterTests' failed at 2026-11-17 07:04:12.663
	 Executed 2 tests, with 5 failures (0 unexpected) in 0.004 (0.004) seconds
Test Suite 'MenuBarControllerTests' failed at 2026-11-17 07:04:12.773
	 Executed 15 tests, with 397 failures (0 unexpected) in 0.11 (0.11) seconds
Test Suite 'Selected tests' failed at 2026-11-17 07:04:12.773
	 Executed 17 tests, with 402 failures (0 unexpected) in 0.113 (0.113) seconds
```

15 个菜单测试每一个都失败了。代表输出：

```text
testFreshMenuShowsNormalAndKeepsSettingsAndQuitEnabled : XCTAssertEqual failed: ("") is not equal to ("Normal")
testPauseChordUpdatesTheMenuAndPersists : XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
testAddingAndRemovingTheFrontmostAppChangesInterception : XCTAssertEqual failed: ("[]") is not equal to ("[..., "com.example.Notes"]")
testMenuBarAppPresentsTheSnapshotAndDoesNotInstallTheTap : XCTAssertTrue failed
testSavedPauseStartsTheMenuPausedBeforeAnyKey : XCTAssertEqual failed: ("") is not equal to ("Paused")
```

空实现一律放过。排除应用「应该放过」的那几条断言因此在空实现上也会过，不能单独当作证据。真正先失败的是菜单标题和启用状态、暂停后保持暂停、暂停键被吞掉并写入 `paused`、加入或移除排除项之后的名单，以及移除排除后 `j` 从放过变成吞掉。应用目标当时还是占位菜单，源码扫描也失败了。

## 第四次运行：实现之后通过（GREEN）

时间：2026-11-17 07:06:29 UTC 到 07:06:32 UTC。同一条过滤命令。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'EventInterpreterTests' passed at 2026-11-17 07:06:32.199
	 Executed 2 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'MenuBarControllerTests' passed at 2026-11-17 07:06:32.212
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.013 (0.013) seconds
```

接着跑了不带过滤的 `swift test`。时间：2026-11-17 07:06:57 UTC。退出码 0。没有编译警告。

```text
Test Suite 'Debug-linux-x86_64.xctest' passed at 2026-11-17 07:06:55.780
	 Executed 84 tests, with 0 failures (0 unexpected) in 1.14 (1.14) seconds
Test Suite 'Debug-linux-x86_64.xctest' passed at 2026-11-17 07:06:57.138
	 Executed 282 tests, with 0 failures (0 unexpected) in 1.346 (1.346) seconds
```

系统测试 84 个：`ActuatorTests` 40、`EventTapTests` 29、`MenuBarPreflightTests` 5、`UserDefaultsSettingsStoreTests` 10。核心测试 282 个：`CommandMapTests` 32、`EventInterpreterTests` 41、`HintLabelerTests` 41、`KeyParserTests` 37、`MenuBarControllerTests` 15、`MenuBarManifestTests` 18、`ModeMachineTests` 61、`SettingsTests` 36、`TaskGraphTests` 1。合计 366 个 XCTest。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

这一轮还没有把「登录启动已经是 false 时再写一次 false」放进测试。那两行是后来补上的，见第六次运行。状态文件和 `TaskGraphTests` 是在第四次通过之后一起改的。

## 第五次运行：覆盖率

时间：2026-11-17 07:08:16 UTC。命令：`scripts/event-tap-coverage.sh`。退出码 0。`EventInterpreter.swift` 在菜单改动之后仍然高于 90%。这一轮之后没有再改这个文件。

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
EventInterpreter.swift line coverage: 98.28% (229/233)
EventInterpreter.swift region coverage: 97.56% (80/82)
EventInterpreter.swift function coverage: 100.00% (26/26)
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
EventTap.swift line coverage: 99.13% (114/115)
EventTap.swift region coverage: 98.28% (57/58)
EventTap.swift function coverage: 100.00% (17/17)
```

`scripts/menu-bar-coverage.sh` 第一次把检查脚本指到了错误的覆盖率文件，退出码 1，报告是 `could not find an instrumented binary containing MenuBarController.swift`。这是脚本写错路径，不是菜单行为失败。改完路径后重跑。

## 第六次运行：补上一次无变化的登录开关，再量菜单覆盖率

时间：2026-11-17 07:09:04 UTC 到 07:09:10 UTC。命令：`scripts/menu-bar-coverage.sh`。退出码 0。构建日志里没有编译警告。脚本里面会再跑一次 `swift test --enable-code-coverage`。计数和第四次相同：系统 84，核心 282，合计 366，0 失败。`MenuBarControllerTests` 仍是 15 个。Swift Testing 仍然是 0。

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
MenuBarController.swift line coverage: 99.41% (169/170)
MenuBarController.swift region coverage: 98.28% (57/58)
MenuBarController.swift function coverage: 100.00% (20/20)
```

没盖住的那一行是 `noticeText` 里「Could not save settings.」的默认分支。空白和重复的 bundle id 在写入之前就被拒绝，不会走到这个分支。非法 id 走的是另一句提示，那一句有测试。

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。`ExclusionSettingsPanel.swift` 和菜单胶水整文件包在 `#if canImport(AppKit)` 里，Linux 上不计入覆盖率，脚本也不把它们放进 90% 门槛。

## 菜单在做什么

| 情况 | 结果 |
| --- | --- |
| 普通模式、Hint | 状态标题 `Normal`。暂停可用，恢复不可用 |
| Insert | 状态标题 `Insert`。暂停可用 |
| Paused | 状态标题 `Paused`。暂停不可用，恢复可用 |
| 菜单项 | Pause、Resume、Settings、分隔线、Quit Supervim。设置和退出始终可用 |
| 菜单暂停 / 恢复 | 调用模式机，并把 `paused` 写进设置。没有改动时不新建文档 |
| 已保存的暂停 | 启动后就是 Paused，`j` 放过。可编辑焦点上，暂停键恢复到 Insert |
| 暂停键 | 焦点已知且应用不在排除列表里时吞掉，并切换暂停、写入设置。未知焦点放过，菜单保持 Normal |
| 排除列表 | 默认 Terminal、iTerm、Emacs 的 bundle id。命中时 `j` 和暂停键都放过。大小写敏感 |
| 加入前台应用 | 去掉两端空白后追加。空白、已经排除、不是合法 bundle id 的都不写盘 |
| 移除 | 按去掉空白后的 id 删除。名单里没有的不改文档 |
| 登录启动 | 只改 `launchAtLogin`。不注册登录项 |
| 退出 | 视图模型返回终止。不改暂停 |

Hint 显示成 Normal，因为规格只点了 Normal、Insert、Paused 三个词。暂停时如果前面有未完成的 `g`，前缀丢掉，恢复后再按 `g` 不会变成 `gg`。从 Hint 暂停再恢复回到普通模式，`j` 重新是滚动。从手动 Insert 暂停再恢复仍是 Insert。

## 交给所有者看的决定

规格第 8、9、11 条写了模式显示、暂停、恢复、设置、排除列表、全局 `Ctrl+Option+V`，以及登录启动是可选项。没有写设置窗口里有哪些控件，也没有保证热键用哪一个系统 API。没有改规格正文。

1. **状态标题用规格里的三个英文词。** Hint 显示成 Normal。它是普通模式下的短暂提示，不是第四个状态栏文案。
2. **退出留在菜单里。** 规格没有写退出。任务 1 有 Quit Supervim。拿掉它，菜单栏进程就没有退出入口。分隔线只是展示，不响应。
3. **保存的暂停在启动时生效。** 任务 7 故意不读 `Settings.isPaused`，并把测试写成「保存了也不暂停」。本任务把那条测试改成启动即暂停。这是任务 6 留给任务 13 的接线，不是改规格。
4. **暂停键和菜单写的是同一个布尔值。** 按键没有变化时不创建文档。缺文档的用户不会因为按了 `j` 就多出一个设置文件。
5. **未知焦点时，暂停键放过，菜单暂停仍然有效。** 宪法第 2 条：不确定就不要吞键。菜单不是按键。
6. **排除用任务 6 没经过所有者确认的 bundle id。** Terminal `com.apple.Terminal`，iTerm2 `com.googlecode.iterm2`，GNU Emacs `org.gnu.Emacs`。本任务没有新造标识。空白 bundle id 仍然算排除，但是设置窗口拒绝把空白写进名单。
7. **设置窗口只有排除列表和登录启动。** 规格没有把按键超时列进菜单或设置。超时仍留在 `Settings` 里，解释器继续用它。窗口不提供这一项。
8. **登录启动只保存偏好。** 不调用 `SMAppService`。规格把登录项放在任务 15 及相关任务。未签名、还没进「应用程序」文件夹的包，系统并不保证能登记登录项。任务 15 再按这个布尔值注册。
9. **启动时不安装事件钩子。** 任务 8 的焦点扫描还没接上。缓存一直是未知时，钩子会把键放过，暂停键也同样放过，装上它并不能完成全局暂停。一旦缓存被标成不可编辑，`j` 和 `f` 会被吞掉，而菜单进程并没有在钩子里调用执行器。宪法把丢掉按键看得比漏掉快捷键更严重，所以默认不装。`CGEventTapSession` 仍在，测试可以装替身，应用目标的源码里没有 `CGEvent`、`EventTap` 或 `tapCreate`。
10. **全局热键没有单独的注册，也没有标成通过。** 规格要求 `Ctrl+Option+V`。现有路径是事件钩子里的按键决策，需要输入监控权限，并且焦点必须已知、应用不在排除列表里。没有使用 Carbon `RegisterEventHotKey`。菜单栏、未签名的 `LSUIElement` 进程能不能用那套 API 稳定收到热键，计划没有写成保证。本环境没有 Mac，单元测试喂的是 `KeyEvent`，不是系统热键。真机行为保持未验证。
11. **偏好套件打不开，或文档损坏时，菜单改用内存设置。** 不覆盖原来的坏文档。这没有在 macOS 上试过。套件名仍是任务 6 的 `com.lijigang.supervim`。
12. **前台 bundle id 由应用在主线程读 `NSWorkspace`。** 核心只收一个字符串。Linux 测试用替身。没有对真实前台应用试过。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit
- 没有看过状态栏或设置窗口
- 没有安装真正的 `CGEventTap`，也没有验证 `Ctrl+Option+V` 的真机行为。这一项不能标成通过
- 没有注册登录项，也没有调用 `SMAppService`
- 没有测量 CPU、内存或 `f` 的延迟
- 没有走真实的辅助功能树
