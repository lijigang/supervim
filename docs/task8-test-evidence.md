# 任务 8 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit，没有 ApplicationServices

因此下面能证明的是焦点分类、窗口枚举和「把缓存交给 ModeMachine」的先失败、后通过，以及 Linux 上 `AXScanner.swift` 的覆盖率。不能证明 `AXObserver` 真的装上了，也不能证明微信、备忘录或 Safari 地址栏不会吞字。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。写本文时那次 CI 还没有结果。

## 范围

加了 `SupervimSystem` 里的 `AXScanner`：协议替身能读到的焦点被分成可编辑、不可编辑或未知，写进任务 7 已经在用的焦点缓存，再调用 `publishCachedFocus()` 交给 ModeMachine。可点击元素和第一个可编辑输入框只在钩子之外、从协议读到的前台窗口上收集。macOS 上另有 `AXApplicationReader.swift`，用辅助功能读焦点、听焦点通知，并听应用激活。菜单栏占位程序没有启动扫描器，也没有安装事件钩子。

没有改 ModeMachine、KeyParser、CommandMap、EventInterpreter 或 EventTap 的决策。核心仍然只看见 `FocusEditability`。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 06:45:30 UTC 到 06:45:35 UTC。命令：`swift test --filter AXScannerTests`。当时还没有 `AXScanner.swift`，也没有 `AXApplicationReader.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimSystemTests/AXScannerTests.swift:964:19: error: cannot find type 'FocusPipeline' in scope
Tests/SupervimSystemTests/AXScannerTests.swift:992:6: error: cannot find type 'AccessibilityElement' in scope
Tests/SupervimSystemTests/AXScannerTests.swift:1018:50: error: cannot find type 'AccessibilityReading' in scope
Tests/SupervimSystemTests/AXScannerTests.swift:1046:43: error: cannot find type 'FocusChangeSignaling' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：任何元素都判成不可编辑；窗口枚举永远返回不可用；焦点更新不读替身，把缓存写成 bundle id 为 `stub` 的不可编辑；步行上限不夹紧，标准上限是 1 个节点、深度 1。还没有 `AXApplicationReader.swift`。空实现不是最终行为。

空实现的第一次编译没有跑到断言。测试里有一处调用把 `actions` 写在 `children` 前面，Swift 要求默认参数按顺序出现。退出码 1。时间：2026-11-17 06:46:05 UTC 到 06:46:07 UTC。

```text
Tests/SupervimSystemTests/AXScannerTests.swift:497:49: error: argument 'children' must precede argument 'actions'
```

这是测试调用的参数顺序，不是产品行为。已改成 `children` 在前。期望值没有放宽。

## 第二次运行：断言失败（RED）

时间：2026-11-17 06:46:13 UTC 到 06:46:17 UTC。命令：`swift test --filter AXScannerTests`。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'AXScannerTests' failed at 2026-11-17 06:46:17.790
	 Executed 44 tests, with 80 failures (1 unexpected) in 0.622 (0.622) seconds
```

44 个测试里 37 个失败。失败原因是空实现一律不可编辑、不读替身、不给出可点击元素，不是拼写错误。那 1 个 unexpected 是 `AXApplicationReader.swift` 还不存在，源码测试在读文件时抛错。代表输出：

```text
testEditabilityFollowsTheAttributeRoleAndKeyboardOwner : XCTAssertEqual failed: ("["text field: notEditable != editable", "text area: notEditable != editable", ...]") is not equal to ("[]")
testUnavailableFocusStaysUnknownAndPassesTheCommand : XCTAssertEqual failed: ("...notEditable...stub...") is not equal to ("...unknown...com.apple.Safari...")
testClickableElementsFollowTreeOrderAndKeepTheChildPath : XCTAssertEqual failed: ("unavailable") is not equal to ("elements(...)")
testWalkLimitsClampANonPositiveBudget : XCTAssertEqual failed: ("TreeWalkLimits(maxNodes: 0, maxDepth: -3)") is not equal to ("TreeWalkLimits(maxNodes: 1, maxDepth: 0)")
testWalkLimitsClampANonPositiveBudget : XCTAssertEqual failed: ("TreeWalkLimits(maxNodes: 1, maxDepth: 1)") is not equal to ("TreeWalkLimits(maxNodes: 2000, maxDepth: 32)")
```

有 7 个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testCoreAndHookSourcesDoNotWalkAccessibility`：核心和 EventTap 本来就不读辅助功能树
- `testElementCopiesDoNotShareLaterEdits`：结构体副本本来就不会写回原来那份
- `testPortableScannerSourceDoesNotTouchTheSystem`：空文件里没有系统调用，方法名又是为了能编译而写上的
- `testEarlierTruncatedContainerBlocksALaterField`：空实现的查找永远返回不可用，而这条期望的也是不可用
- `testFirstEditableInputIsUnavailableWhenTheCapHidesEveryField`：同样，空实现永远返回不可用
- `testFocusedGroupDoesNotSearchItsChildren`：空实现不读元素，直接写成不可编辑；`stub` 这个 bundle id 不在排除列表里，所以 `j` 本来就会滚动
- `testManualInsertSurvivesANotEditableFocusReport`：空实现永远不可编辑，手动 Insert 按状态机本来就会留下来

真正先失败的是可编辑进入 Insert、未知焦点放过、文本角色和 `AXEditable` 冲突时放过、菜单放过、弹出按钮进入 Insert、可点击元素的角色和路径、第一个输入框，以及 macOS 适配文件。实现之后这 7 个本来就通过的测试仍然通过，它们单独不能证明扫描器是对的。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 06:50:30 UTC 到 06:50:33 UTC。命令：`swift test --filter AXScannerTests`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'AXScannerTests' passed at 2026-11-17 06:50:33.520
	 Executed 44 tests, with 0 failures (0 unexpected) in 0.318 (0.318) seconds
```

这一轮还没有把任务 8 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 06:51:49 UTC 到 06:51:56 UTC。命令：`scripts/ax-scanner-coverage.sh`。退出码 0。构建日志里没有编译警告。

脚本里面会再跑一次 `swift test --enable-code-coverage`。`AXScannerTests` 44 个、`EventTapTests` 26 个、`MenuBarPreflightTests` 5 个、`UserDefaultsSettingsStoreTests` 10 个，系统测试合计 85 个。`SupervimCoreTests` 266 个（含 `EventInterpreterTests` 40 个、`KeyParserTests` 37 个、`CommandMapTests` 32 个、`HintLabelerTests` 41 个、`ModeMachineTests` 61 个、`SettingsTests` 36 个、`MenuBarManifestTests` 18 个，以及已经改成任务 1–8 都是 `done` 的 `TaskGraphTests` 1 个）全部通过，0 失败。合计 351 个 XCTest。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

同一轮 llvm-cov 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
AXScanner.swift line coverage: 99.09% (327/330)
AXScanner.swift region coverage: 97.69% (127/130)
AXScanner.swift function coverage: 97.73% (43/44)
```

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。`AXApplicationReader.swift` 整文件包在 `#if canImport(ApplicationServices)` 里，Linux 上不计入覆盖率，脚本也不把它放进 90% 门槛。

覆盖率跑完之后，macOS 适配里读取 `AXValue` 的指针写法改成了 `withUnsafeMutablePointer`，避免把 `CGPoint` 的指针直接交给 `UnsafeMutableRawPointer`。`AXScanner.swift` 没有改。时间：2026-11-17 06:52:36 UTC 到 06:52:41 UTC。命令：`swift test --filter AXScannerTests`。退出码 0。没有编译警告。

```text
Test Suite 'AXScannerTests' passed at 2026-11-17 06:52:41.180
	 Executed 44 tests, with 0 failures (0 unexpected) in 0.313 (0.313) seconds
```

这只再证明了源码扫描和分类测试仍然通过。覆盖率数字仍是上面那一轮。

## macOS CI：第一次编译失败

第一次 macOS 运行：<https://github.com/lijigang/supervim/actions/runs/44034625697>，作业 <https://github.com/lijigang/supervim/actions/runs/44034625697/job/133874409846>。提交 `8857e81`。`swift build` 失败，退出码 1。测试还没开始。Xcode 26.6，Swift 6.3.3，`macos-26-arm64`。

两处是错误，不是分类行为不对：

```text
AXApplicationReader.swift:77:50: error: cannot find 'kAXEditableAttribute' in scope
AXApplicationReader.swift:282:18: error: conditional downcast to CoreFoundation type 'AXUIElement' will always succeed
```

另外两处是警告：`unsafeBitCast` 到 `AXValue` 应改成 `unsafeDowncast`。公开 SDK 里没有 `kAXEditableAttribute` 这个常量；属性名仍是 `AXEditable`。`AXUIElement` 在 Swift 6 里不能用 `as?` 从任意 CF 值转出来，要先比 `CFGetTypeID`。

改法只在 macOS 适配里：可编辑属性用字符串 `AXEditable`；元素和 `AXValue` 在类型号一致后再 `unsafeDowncast`。分类、缓存和测试期望没有改。Linux 上这个文件不编译，所以不能在这里证明 macOS 已经通过。改完之后的 `swift test --filter AXScannerTests` 只证明源码扫描和分类测试仍然通过。macOS 是否编译通过，看这一次之后的 `macos-latest` 运行。

任务 9 在这次失败的同时合并进了 `main`（`2b9fde2`）。本分支变基到那次提交上，任务 8 和任务 9 的状态都保持 `done`。变基之后在 Linux 上再跑 `swift test`。时间：2026-11-17 06:57:30 UTC 到 06:57:36 UTC。退出码 0。系统测试 128 个（含 `AXScannerTests` 44 个、`ActuatorTests` 40 个、`EventTapTests` 29 个），核心测试 266 个，合计 394 个 XCTest，0 失败。覆盖率数字仍是变基前那一轮，因为 `AXScanner.swift` 没有改。

## 扫描器在做什么

焦点更新只读当前焦点元素和前台 bundle id，不读子节点。结果写入 `LockedFocusCache`，再由 `EventTapWiring.publishCachedFocus()` 交给 ModeMachine。按键路径仍然只读缓存。

| 读到的焦点 | 缓存 | 模式机 |
| --- | --- | --- |
| 读失败，bundle id 已知 | 未知 + 该 id | 按键放过，包括 `f` |
| 文本角色或 `AXEditable == true`，bundle id 是受控应用 | 可编辑 | 自动 Insert，按键放过 |
| 明确的非文本角色，例如网页区域、按钮、分组 | 不可编辑 | 普通模式命令可以吞键 |
| 文本角色但 `AXEditable == false` | 未知 | 按键放过 |
| 菜单、菜单项、对话框、sheet | 未知 | 按键放过，Esc 也不 blur |
| `AXPopUpButton` | 可编辑 | 自动 Insert，对齐 Vimium 的 `<select>` |
| 可编辑，但 bundle id 缺失、只有空白，或在排除列表里 | 仍记下可编辑性 | 不进入 Insert，按键放过 |
| 焦点元素是分组，哪怕里面有输入框 | 不可编辑 | 不往下搜。真正的焦点应该就是那个输入框 |

窗口查询不改缓存，也不改模式：

| 查询 | 结果 |
| --- | --- |
| 窗口读失败 | 可点击元素和第一个输入框都是不可用 |
| 前台窗口里的按钮、链接、输入框等 | 树的前序，带角色、动作、屏幕上的 frame，以及从窗口根数下来的子节点路径 |
| 容器角色，哪怕带 `AXPress` | 不进可点击列表。搜索框这种子角色除外 |
| 没有面积，或和窗口没有正面积重叠 | 不进列表。窗口自己没有 frame 时，只要元素有面积就保留 |
| 第一个可编辑输入框 | 前序里第一个在窗口里的可编辑节点。不聚焦，也不进入 Insert |
| 截断发生在找到输入框之前 | 第一个输入框返回不可用，避免把后面的当成第一个 |
| 已经找到输入框之后才截断 | 返回找到的那个 |

`refreshFocus()` 走的是同一条焦点读取，不扫窗口。信号 `start` 之后，后续通知才再读；`stop` 之后通知不再读。

## 交给所有者看的决定

规格和计划写了扫描器在系统适配层、核心只看可编辑 / 不可编辑 / 未知、未知必须放过、可编辑自动 Insert、不要在事件钩子里同步扫整棵树，也写了授权后免重启仍不能当成平台保证。没有写角色表、可点击的判定、`gi` 的查找结果长什么样，以及观察者怎么接到任务 7 的缓存。选择按 Vimium、已合并的 ModeMachine / EventTap，以及宪法第 2 条（不确定就放过）。没有改规格正文。

1. **分类和查询放在 `AXScanner.swift`，真实辅助功能调用放在 `AXApplicationReader.swift`。** 后者整文件包在 `#if canImport(ApplicationServices)` 里。Linux 上测试注入 `AccessibilityReading` 和 `FocusChangeSignaling`。核心不导入辅助功能。
2. **焦点变化写进任务 7 的缓存，再 `publishCachedFocus()`。** 没有改 `EventTap` 的按键路径。`scanFocus()` 仍然只在 `refreshFocus()` 里被调用。占位程序不启动扫描器。
3. **未知交给现有的 ModeMachine。** 读失败、角色和属性都没有、两者冲突、以及菜单 / 对话框，都记成未知。按键原样放过，不 blur。
4. **Vimium 会进入插入模式的控件记成可编辑。** `AXTextField`、`AXTextArea`、`AXComboBox`、`AXPopUpButton`，以及 `AXSearchField`、`AXSecureTextField`。`AXEditable == true` 也算，所以 contenteditable 的分组可以进 Insert。属性缺失时按角色。属性明确为 false 且角色又像文本时，两边冲突，记成未知而不是不可编辑。
5. **网页区域、窗口、按钮、链接、分组这类已知非文本角色，在没有可编辑属性时记成不可编辑。** 否则 Safari 正文获得焦点时，`j` 永远不会滚动。
6. **菜单、菜单栏、菜单项、sheet 和对话框记成未知，即使 `AXEditable` 为 true。** 这些界面自己要处理 Esc 和字母。记成不可编辑会把 `j` 吃成滚动；记成 Insert 会把 Esc 吞掉并 blur。
7. **焦点读取不看子节点。** 分组获得焦点时，不因为里面有输入框就进入 Insert。辅助功能报告的焦点元素本身就应该是那个输入框。
8. **bundle id 原样放进缓存。** 读不到就用空字符串。Settings 会把空白和排除列表当成排除，于是不会进入 Insert。比较仍是任务 6 的大小写敏感修剪，扫描器不再修一次。
9. **可点击元素和第一个输入框只走窗口读取，不改焦点缓存。** 顺序是树的前序，不对齐屏幕坐标。这接近 Vimium 的 DOM 顺序。每个结果带从窗口根开始的子节点下标，方便以后再找到它，值类型里不保存 `AXUIElement`。
10. **可点击的条件。** 非容器，并且角色是按钮、链接、勾选框、输入框等，或子角色是搜索框、安全输入框、窗口按钮，或动作里有 `AXPress`、`AXConfirm`、`AXPick`。容器即使有 `AXPress` 也不进列表，避免整个网页区域变成一个巨大的标签。frame 必须有正面积，并且和窗口 frame 有正面积重叠。坐标不翻转，仍是读取方给的空间。
11. **`gi` 只查找，不聚焦，也不进入 Insert。** 这和任务 5、任务 7 的决定一致：动作是 `focusFirstInput`，等焦点报告变成可编辑后再进 Insert。找不到是 `none`。窗口读失败，或截断可能藏住了更靠前的输入框，是 `unavailable`，调用方不能把它当成「页面上没有输入框」。
12. **窗口步行上限是 2000 个节点、深度 32。** 这是未确认的安全上限，不是 `f` 的 90% 覆盖率保证。截断会标出来。
13. **真实适配不调用 `AXIsProcessTrustedWithOptions`，也不弹出授权。** 未授权时读取结果是不可用，扫描器记成未知。授权之后当前进程能否立刻信任，规格列为未验证，这里也不写成已经生效。
14. **观察者听 `AXFocusedUIElementChanged`、焦点窗口变化和应用激活。** 回调只通知扫描器再读当前焦点，不在回调里扫子节点。这个文件没有在 Linux 上执行。数组和布尔值用 Swift 桥接；真机上如果桥接拿不到子节点，窗口会看起来没有元素，而不是崩溃。这一点没有测过。
15. **占位程序仍然不安装事件钩子，也不启动扫描器。** 现在就根据真实焦点进入 Insert，会在执行器还不存在时把 Esc 变成 blur。任务 11 和任务 13 再接上。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 ApplicationServices / AppKit
- 没有安装真正的 `AXObserver`，也没有在辅助功能权限下看回调
- 没有验证授权之后不重启就能读到焦点。这一点保持未验证
- 没有在微信、备忘录或 Safari 地址栏里检查会不会吞字
- 没有测量 `f` 的 200ms，也没有测量可点击元素的 90% 覆盖率
- 没有点击、滚动、聚焦输入框或绘制标签
- 没有把暂停状态写回设置，也没有在菜单栏显示模式

## 手工验收时要看的

单元测试不代替下面这些。做不到就保持未测，不改规格。

- 微信、备忘录、Safari 地址栏里输入时，字符不被吞掉
- Safari、Finder、系统设置里，`f` 的标签是否在 200ms 内出现，可访问按钮和链接是否超过 90%
- 用户授予辅助功能之后，当前进程是否要重启才读得到焦点
