# 任务 10 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑测试
- 没有 macOS，没有 Xcode，没有 AppKit，没有 CoreGraphics

因此下面能证明的是标签会话和浮层控制器的先失败、后通过，以及 Linux 上 `HintSession.swift` 和 `HintOverlay.swift` 的覆盖率。不能证明面板真的出现在屏幕上，也不能证明点击落在 Safari、Finder 或系统设置的按钮上。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。

规格里的 200ms 和可访问按钮、链接 90% 覆盖率**没有测**。本文的覆盖率是源码行覆盖率，不是那个验收目标。

## 范围

加了 `SupervimCore` 里的 `HintSession`，以及 `SupervimSystem` 里的 `HintController`。macOS 上另有 `NonActivatingHintPanel`，整段包在 `#if canImport(AppKit)` 里。Linux 上那个文件没有类型。

`EventInterpreter` 增加了 `endHint(_:)`。标签点中或取消时，用它离开 Hint，回到普通模式。不在 Hint 里调用它不会清掉 `g` / `y` 前缀。

没有改 HintLabeler、ModeMachine、KeyParser、CommandMap、AXScanner 或 Actuator 的行为。菜单栏占位程序没有安装事件钩子，也没有创建浮层。现在就安装钩子会把 `j` 这类还不会执行的命令吞掉。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 07:12:59 UTC 到 07:13:10 UTC。命令：`swift test --filter 'HintSessionTests|HintOverlayTests|testCompletedHintReturnsToNormal|testCancelledHintReturnsToNormal|testEndingHintOutsideHint|testEndingHintWhileInsert'`。当时还没有 `HintSession.swift`，也没有 `HintOverlay.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/HintSessionTests.swift:206:71: error: cannot find type 'HintTarget' in scope
Tests/SupervimCoreTests/HintSessionTests.swift:213:31: error: cannot find type 'HintTarget' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：任何目标都没有标签；`handle` 和 `cancel` 永远返回 `inactive`；按键解析永远取消；退格虚拟键是 0；`endHint` 永远返回普通模式放过，但不改模式机；浮层 `consume` 永远是 `unchanged`，刷新永远是不可用，也不读扫描器。`HintOverlayWindow.swift` 只有一行 `#if canImport(AppKit)`。空实现不是最终行为。

系统测试文件一开始找不到 `repoRoot`，因为那个函数在别的测试文件里是 `private`。这是测试辅助函数的可见性，不是浮层行为。已在 `HintOverlayTests.swift` 里加了同名的文件私有函数。期望值没有放宽。

## 第二次运行：断言失败（RED）

时间：2026-11-17 07:14:06 UTC 到 07:14:11 UTC。同一条命令。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'HintOverlayTests' failed at 2026-11-17 07:14:11.103
	 Executed 27 tests, with 51 failures (0 unexpected) in 0.209 (0.209) seconds
Test Suite 'EventInterpreterTests' failed at 2026-11-17 07:14:11.214
	 Executed 4 tests, with 6 failures (0 unexpected) in 0.102 (0.102) seconds
Test Suite 'HintSessionTests' failed at 2026-11-17 07:14:11.318
	 Executed 17 tests, with 21 failures (0 unexpected) in 0.103 (0.103) seconds
```

这一轮过滤器一共跑了 48 个测试，78 次断言失败，0 次 unexpected。失败原因是空实现不显示标签、不点击、不离开 Hint，面板源文件里没有不激活窗口的标志。不是拼写错误。代表输出：

```text
testTypingALabelClicksTheCenterAndLeavesHint : XCTAssertEqual failed: ("unchanged") is not equal to ("activated(... plain ... (x: 14.0, y: 23.0) ... left click ...)")
testFCommandClicksWithCommandAndNotAContextMenu : XCTAssertEqual failed: ("unchanged") is not equal to ("activated(... command ... modifiers: rawValue: 4)")
testPartialPrefixShowsMatchesWithoutActivating : failed - a shared prefix should keep the hint open
testMacOSPanelSourceStaysTransparentAndNonActivating : XCTAssertTrue failed
testCompletedHintReturnsToNormalAndTheNextKeyScrolls : XCTAssertEqual failed: ("hint(.plain)") is not equal to ("normal")
```

`rawValue: 4` 是 `KeyModifiers.command`。点击点 `(14, 23)` 是框 `(10, 20, 8, 6)` 的中心。

有 7 个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testEventHookSourceDoesNotScanClickablesOrPresent`：`EventTap.swift` 本来就没有浮层
- `testPlaceholderDoesNotStartTheOverlay`：占位程序本来就没有浮层
- `testNoOverlayDecisionDoesNothing`：空实现的 `consume` 本来就返回 `unchanged`
- `testEndingHintOutsideHintDoesNotDropAPrefix`：空的 `endHint` 不碰解析器，所以 `gg` 仍能完成
- `testNoTargetsStartInactive` 和 `testAllUnusableFramesStartInactive`：空实现本来就永远不活动
- `testSessionSourceDoesNotTouchTheSystemOrRecordKeys`：空的 `HintSession.swift` 本来就没有系统导入

真正先失败的是标签、前缀过滤、左键点击、Command 点击、Esc、无效输入、缓存和面板源文件。实现之后这 7 个本来就通过的测试仍然通过，它们单独不能证明点击是对的。

断言红灯之后、实现之前，又加了 `testUnusableCachedFramesAreNotLabeled`。空实现会返回 `unchanged`。时间：2026-11-17 07:15:37 UTC 到 07:15:39 UTC。命令：`swift test --filter testUnusableCachedFramesAreNotLabeled`。退出码 1。1 个测试，1 次失败，0 次 unexpected。通过的那一轮包含这条。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 07:16:18 UTC 到 07:16:21 UTC。第一次红灯用的那条过滤器。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'HintOverlayTests' passed at 2026-11-17 07:16:21.466
	 Executed 28 tests, with 0 failures (0 unexpected) in 0.109 (0.109) seconds
Test Suite 'EventInterpreterTests' passed at 2026-11-17 07:16:21.575
	 Executed 4 tests, with 0 failures (0 unexpected) in 0.102 (0.102) seconds
Test Suite 'HintSessionTests' passed at 2026-11-17 07:16:21.782
	 Executed 17 tests, with 0 failures (0 unexpected) in 0.207 (0.207) seconds
```

过滤器里的 `EventInterpreterTests` 只有 4 个新测试。全量数字在下一节。这一轮还没有把任务 10 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 07:17:34 UTC 到 07:17:44 UTC。命令：`scripts/hint-overlay-coverage.sh`。退出码 0。构建日志里没有编译警告。

脚本里面会再跑一次 `swift test --enable-code-coverage`。系统测试 156 个：`AXScannerTests` 44、`ActuatorTests` 40、`EventTapTests` 29、`HintOverlayTests` 28、`MenuBarPreflightTests` 5、`UserDefaultsSettingsStoreTests` 10。`SupervimCoreTests` 287 个（含 `HintSessionTests` 17 个、`EventInterpreterTests` 44 个，以及已经改成任务 10 `done` 的 `TaskGraphTests` 1 个）。合计 443 个 XCTest，0 失败。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

同一轮 llvm-cov 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
HintSession.swift line coverage: 97.56% (120/123)
HintSession.swift region coverage: 95.35% (41/43)
HintSession.swift function coverage: 100.00% (18/18)
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
HintOverlay.swift line coverage: 98.51% (132/134)
HintOverlay.swift region coverage: 93.88% (46/49)
HintOverlay.swift function coverage: 100.00% (18/18)
```

没盖住的行是防御性返回：标签器给出的下标不在目标数组里，以及一次输入在会话仍活动时返回 `inactive`。正常的选中、取消和前缀都走了别的返回。

状态文件里的 `updated` 时间改成 `2026-11-17T07:17:44.000Z`，和这一轮结束时间一致。只改了这一处元数据。随后单独再跑 `swift test --filter TaskGraphTests`。时间：2026-11-17 07:18:11 UTC 起，约 5 秒后结束。退出码 0。1 个测试通过。`HintSession.swift` 和 `HintOverlay.swift` 没有再改，所以上面的覆盖率仍然是这一轮的数字。

## 浮层在做什么

`refreshClickables()` 才调用扫描协议。`consume` 只读缓存。

| 输入 | 结果 |
| --- | --- |
| 缓存还没刷新，或扫描不可用 | 关掉标签，离开 Hint，不点击 |
| 缓存里没有可用元素 | 同上 |
| `f` | 按任务 4 的主键行标出仍匹配的元素。锚点是元素原点。窗口策略是透明、不激活、忽略鼠标 |
| 键入完整标签 | 在元素中心左键点击，关掉标签，回到普通模式。下一键可以是滚动 |
| `F` 再键入完整标签 | 同样的标签和位置，左键加 Command。不是右键，也不是 `AXPress` |
| 只键入前缀 | 只留下匹配的标签，不点击 |
| 无效字符，或没有键码的无名键 | 取消，不点击，回到普通模式 |
| 无名键且键码是 `0x33` | 当成退格，恢复被滤掉的标签 |
| Esc、暂停、焦点变成可编辑、焦点未知、前台变成排除应用 | 关掉标签，不点击。模式机原有的转移保持不变 |
| `?` | 不显示标签，不点击。帮助仍是任务 12 |
| 元素带 `AXPress` | 仍然是中心左键。快照里没有绑定的 `AXUIElement`，Press 会空操作 |

标签顺序跟可点击快照的顺序，也就是任务 8 的树前序。没有按屏幕坐标重排。截断的快照只标已经返回的元素，不把截断说成 90% 覆盖率。

## 交给所有者看的决定

规格和计划写了透明、不激活的浮层，`f` 点击，`F` 是 Command 点击，Esc 或无效输入取消，扫描不在事件钩子里做。没有写标签锚在框的哪一个角、点击点用中心还是 `AXPress`、退格算不算无效输入，以及占位程序要不要现在就装上钩子。选择按 Vimium、已合并的 HintLabeler / EventTap / Actuator，以及宪法第 2 条（不确定就放过）。没有改规格正文。

1. **会话放在 `HintSession.swift`，显示和点击放在 `HintOverlay.swift`。** 面板只在 macOS 上编译。测试注入扫描协议、presenter 和 `ActionActuator` 的记录 poster。
2. **按键路径不扫描。** `consume` 不调用 `clickableElements()`。缓存要由钩子外面的 `refreshClickables()` 先填上。焦点变化那条现有路径没有改成顺便扫窗口，避免拖慢任务 8 的焦点更新。
3. **菜单进程不安装事件钩子，也不创建面板，也不启动 AXScanner。** 任务 13 已经把入口放在 `Sources/Supervim/SupervimApp.swift`。任务 11 正在做启动时的扫描、钩子和执行器接线，这里不重复。应用层要显示标签时调用 `HintOverlayControlling`：钩子外 `refreshClickables()`，然后 `enterHint(_:)`、`receiveHintKey(_:keyCode:)`、`cancelHint()`。`consume(_:hintKeyCode:)` 只是把已有的 `OverlayUpdate` 转成这三步。`enterHint` 本身不把模式机改成 Hint，调用方先用解释器进入 Hint。`cancelHint` 会隐藏标签并离开 Hint。
4. **`f` 和 `F` 共用 HintLabeler 的标签。** 点击种类在会话开始时定下。提示过程中再按 Command 或 Shift，不把普通点击改成 Command 点击。大小写仍由 HintLabeler 折叠。
5. **点在元素中心，用左键。** `F` 的修饰键只有 Command。`canAccessibilityPress` 固定为 false。路径字符串会放进点击请求的 identifier，但不会走 `AXPress`，因为没有人把 `AXUIElement` 绑进 `AXElementStore`。
6. **锚点是元素原点。** 原点在框的边上。坐标保持扫描器给的空间，不翻转。真机上和 AppKit 窗口是否重合，没有测。
7. **没有目标或扫描不可用就取消，并且不点击。** `f` 这一键已经被解释器吞掉。这是一次没有目标的提示，不是把 `f` 再交还给应用。
8. **退格是 ANSI Delete，虚拟键 `0x33`。** 和任务 7 的虚拟键表一样，没有经过所有者确认，也没有在键盘上按过。解释器交给浮层的 `KeyEvent` 本身分不出退格和方向键；调用方要另外传入这个键码。没有键码的无名键算无效输入，取消提示。
9. **Esc 由模式机结束 Hint。** 浮层看到 `endHint` 只隐藏，不再次改模式。无效输入才会调用 `endHint(.cancelled)`。点中标签调用 `endHint(.completed)`。两种在模式机里都是离开 Hint。
10. **帮助不在这里开关。** `showHelp` 被忽略。任务 12 再复用这块不激活的面板。
11. **面板用 `NSPanel` 的 `.nonactivatingPanel`，背景透明，`ignoresMouseEvents`，并用 `orderFrontRegardless()`。** 源文件里没有 `makeKeyAndOrderFront`，也没有 `NSApp.activate`。Linux 上没有把这个面板跑起来。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit
- 没有在屏幕上看到标签，也没有检查它是否真的不抢焦点
- 没有测量 Safari、Finder、系统设置里标签出现是否在 200ms 内
- 没有测量可访问按钮和链接的覆盖率是否高于 90%。上面的百分比是源码行覆盖率
- 没有把辅助功能坐标转换成 AppKit 坐标
- 没有确认虚拟键 `0x33` 就是这台 Mac 上的退格
- 没有安装 `CGEventTap`，所以占位程序里按 `f` 还不会出标签
- 没有走真实的辅助功能树，也没有让指针真的移动

## 变基到任务 13，并给出应用层接口

`origin/main` 在 `bceff31` 合入了任务 13，入口改到 `Sources/Supervim/SupervimApp.swift`。本分支变基到那次提交。任务 13 保持 `done`，只把任务 10 标成 `done`。任务 11 当时还没有合入，所以菜单进程没有调用浮层，也没有安装事件钩子或启动 AXScanner。

应用层接口是 `HintOverlayControlling`：

- `refreshClickables()`：钩子外刷新可点击元素
- `enterHint(_:)`：用缓存显示标签。不扫描，也不自己把模式机推进 Hint
- `receiveHintKey(_:keyCode:)`：过滤、点中或取消。不传键码时无名键算无效输入
- `cancelHint()`：隐藏标签并离开 Hint

`consume` 只是把解释器已经给出的 `OverlayUpdate` 转成这三步。

直接调用这组方法的测试先没编译过。时间：2026-11-17 07:26:06 UTC。退出码 1。代表错误是 `cannot find type 'HintOverlayControlling' in scope`。

补上协议和方法之后，有一条测试忘了先刷新缓存，`enterHint` 按「扫描不可用」取消。这是测试漏了刷新，不是把不可用改成显示。改完测试再跑。时间：2026-11-17 07:27:01 UTC 到约 07:27:03 UTC。退出码 0。那 3 个测试通过，没有编译警告。

变基之后的全量再跑一次。时间：2026-11-17 07:27:11 UTC 到 07:27:20 UTC。命令：`scripts/hint-overlay-coverage.sh`。退出码 0。没有编译警告。系统测试 158 个（`HintOverlayTests` 30 个），核心测试 303 个，合计 461 个 XCTest，0 失败。Swift Testing 仍是 0。

```text
HintSession.swift line coverage: 97.56% (120/123)
HintOverlay.swift line coverage: 98.68% (149/151)
HintOverlay.swift region coverage: 94.34% (50/53)
```

同一份 profdata 上，`EventInterpreter.swift` 是 98.41%（248/252），`MenuBarController.swift` 是 99.41%（169/170）。任务 13 的菜单覆盖率没有被这次改动拉到 90% 以下。

## macOS CI：第一次编译失败

第一次 macOS 运行：<https://github.com/lijigang/supervim/actions/runs/44037834128>，作业 <https://github.com/lijigang/supervim/actions/runs/44037834128/job/133884918215>。提交 `9dceaf4`。`swift build` 失败，退出码 1。测试还没开始。Xcode 26.6，Swift 6.3.3，`macos-26-arm64`。

错误只有一处，不是点击行为不对：

```text
HintOverlayWindow.swift:28:43: error: escaping closure captures non-escaping parameter 'body'
```

`PanelDispatch.perform` 把调用方的闭包存进了一个变量。存起来的闭包是逃逸的，参数默认不是。Linux 上这个文件整段在 `#if canImport(AppKit)` 里，所以这里编译不到。

改法只在面板调度里：不再把闭包存进变量，主线程和 `DispatchQueue.main.sync` 里直接调用。标签、点击和测试期望没有改。同一份日志里 `AXApplicationReader.swift` 有一条原有的 `unsafeBitCast` 警告，不是这次失败的原因，也没有改那个文件。

改完之后在 Linux 上再跑 `swift test --filter HintOverlayTests`。时间：2026-11-17 07:23:00 UTC 到 07:23:02 UTC。退出码 0。没有编译警告。`HintOverlayTests` 28 个通过。这只证明源码扫描和控制器测试仍然通过。macOS 是否编译通过，看这一次之后的 `macos-latest` 运行。

## 手工验收时要看的

单元测试不代替下面这些。做不到就保持未测，不改规格。

- Safari、Finder、系统设置里，`f` 的标签是否在 200ms 内出现
- 这些应用里，可访问的按钮和链接是否超过 90%
- 标签是否盖住对应控件，以及点击是否打中该控件
- 浮层出现时，原来的窗口是否仍保持焦点
