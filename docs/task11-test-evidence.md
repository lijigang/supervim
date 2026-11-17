# 任务 11 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`
- 没有 macOS，没有 Xcode，没有 AppKit，没有 CoreGraphics，没有 ApplicationServices

因此下面能证明的是命令分流、滚动目录和会话接线的先失败、后通过，以及 Linux 上三个源文件的覆盖率。不能证明页面真的滚动了，也不能证明 `gi` 会把焦点移进微信、备忘录或 Safari 地址栏。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。写本文时那次 CI 还没有结果。

## 范围

加了 `SupervimCore` 里的 `CommandFollowThrough`，以及 `SupervimSystem` 里的 `ScrollAreaCatalog`、`CommandSnapshotBuilder` 和 `NormalCommandSession`。macOS 上的 `AXSystemReader` 会把竖向和横向滚动条读进元素；`AXInputFocuser` 按路径设置焦点。这两个文件整段包在 `canImport(ApplicationServices)` 里，Linux 上不编译进覆盖率。

没有改 KeyParser、ModeMachine、CommandMap、EventInterpreter、ActionActuator 的行为。事件钩子仍然只做决定。菜单栏占位程序没有安装钩子，也没有调用会话。

## 第一次运行：测试没编译过（RED）

`CommandFollowThroughTests` 先单独跑。当时还没有 `CommandFollowThrough.swift`。退出码 1。代表错误：

```text
Tests/SupervimCoreTests/CommandFollowThroughTests.swift:17:32: error: cannot find 'CommandFollowThrough' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：`prepare` 忽略决定，永远返回放过且没有动作；`delivery` 永远返回放过。

系统测试同一时间也编译失败。代表错误：

```text
Tests/SupervimSystemTests/NormalCommandSessionTests.swift:666:15: error: cannot find type 'ScrollBarReading' in scope
Tests/SupervimSystemTests/NormalCommandSessionTests.swift:706:18: error: cannot find type 'NormalCommandSession' in scope
```

空实现：目录永远返回未就绪的空列表；`retarget` 不改标志；焦点中心永远是 nil；会话忽略按键，永远放过，也不调用执行器。另外有一处测试把 `EditableInputTarget` 直接传给了要 `EditableInputQuery` 的参数。那是测试类型写错，期望没有放宽。改成 `.found(...)` 之后才跑到断言。

## 第二次运行：断言失败（RED）

时间：2026-11-17 07:15:30 UTC。命令：`swift test --filter CommandFollowThroughTests`。退出码 1。

```text
Test Suite 'CommandFollowThroughTests' failed at 2026-11-17 07:15:30.868
	 Executed 12 tests, with 48 failures (0 unexpected) in 0.309 (0.309) seconds
```

失败原因是空实现一律放过、不把滚动或快捷键交给执行器，不是拼写错误。代表输出：

```text
testScrollActionsArePreparedForTheActuator : XCTAssertEqual failed: ("[]") is not equal to ("[...scroll(...down...points(60))]")
testShortcutDeclineStaysSwallowed : XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
testFocusFirstInputRequestsFocusAndDoesNotActuate : XCTAssertTrue failed
```

有 3 个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testAMissedScrollGivesTheKeyBack`：空实现的 `delivery` 本来就永远放过
- `testAReleasedKeyStaysReleased`：同样，期望正好是放过
- `testFollowThroughSourceStaysInCore`：空文件里没有 AppKit 或 AX 调用

时间：2026-11-17 07:17:08 UTC。命令：`swift test --filter 'NormalCommandSessionTests|ScrollAreaCatalogTests'`。退出码 1。

```text
Test Suite 'NormalCommandSessionTests' failed at 2026-11-17 07:17:08.994
	 Executed 22 tests, with 143 failures (0 unexpected) in 0.008 (0.008) seconds
Test Suite 'ScrollAreaCatalogTests' failed at 2026-11-17 07:17:08.996
	 Executed 13 tests, with 25 failures (0 unexpected) in 0.002 (0.002) seconds
```

合计 35 个测试，168 次断言失败，0 次 unexpected。失败原因是空会话一律放过、不滚动、不发快捷键、不聚焦，空目录不给出行程。代表输出：

```text
testCopyURLPostsOnlyForThePromisedBrowserList : XCTAssertEqual failed: ("0") is not equal to ("2") - com.apple.Safari
testGIFocusesTheFirstInputAndEntersInsert : XCTAssertEqual failed: ("normal") is not equal to ("insert")
testControlBracketPassesTheNextKeyWithoutPosting : XCTAssertEqual failed: ("nil") is not equal to ("Optional([.passNextKey])")
testContentLengthBecomesPointTravelAndPointerFocusFlags : expected 1 scroll area, ready=false, count=0
```

这一轮之前有一次崩溃，不是断言失败。目录测试在空列表上读 `areas[0]`。XCTest 默认失败后继续执行。进程收到信号。那个下标改成了失败即返回。期望值没有放宽。通过的那一轮包含改过的测试。

有 4 个测试在空实现上直接通过：

- `testUnknownFocusAndExcludedAppsPassTheKey`：空会话本来就放过
- `testNormalEscapePassesWithoutPosting`：同样
- `testAMarkedKeyDoesNotScrollOrConsumePassNext`：空会话对每一键都放过，而这条的期望正好也是放过，没有再要求后面的 `j` 滚动
- `testTruncationDropsEveryArea`：空目录本来就返回未就绪的空列表

实现之后这 4 个仍然通过。它们单独不能证明滚动或 `yy` 是对的。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 07:18:52 UTC 到 07:18:53 UTC。命令：`swift test --filter 'NormalCommandSessionTests|ScrollAreaCatalogTests|CommandFollowThroughTests'`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'NormalCommandSessionTests' passed at 2026-11-17 07:18:53.005
	 Executed 22 tests, with 0 failures (0 unexpected) in 0.108 (0.108) seconds
Test Suite 'ScrollAreaCatalogTests' passed at 2026-11-17 07:18:53.107
	 Executed 13 tests, with 0 failures (0 unexpected) in 0.102 (0.102) seconds
Test Suite 'CommandFollowThroughTests' passed at 2026-11-17 07:18:53.119
	 Executed 12 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
```

这一轮还没有把任务 11 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 07:20:33 UTC 到 07:20:35 UTC。命令：`scripts/command-session-coverage.sh`。退出码 0。构建日志里没有编译警告。

脚本里面会再跑一次 `swift test --enable-code-coverage`。系统测试 163 个（含 `NormalCommandSessionTests` 22 个、`ScrollAreaCatalogTests` 13 个、`ActuatorTests` 40 个、`AXScannerTests` 44 个、`EventTapTests` 29 个）。`SupervimCoreTests` 278 个（含 `CommandFollowThroughTests` 12 个，以及已经改成任务 11 `done` 的 `TaskGraphTests` 1 个）。合计 441 个 XCTest，0 失败。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

同一轮 llvm-cov 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
CommandFollowThrough.swift line coverage: 100.00% (45/45)
CommandFollowThrough.swift region coverage: 100.00% (19/19)
CommandFollowThrough.swift function coverage: 100.00% (6/6)
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
NormalCommandSession.swift line coverage: 94.55% (104/110)
NormalCommandSession.swift region coverage: 94.74% (36/38)
NormalCommandSession.swift function coverage: 93.75% (15/16)
ScrollAreaCatalog.swift line coverage: 96.10% (197/205)
ScrollAreaCatalog.swift region coverage: 92.94% (79/85)
ScrollAreaCatalog.swift function coverage: 100.00% (25/25)
```

没盖住的行是防御性返回：有限的滚动条跨度除出了非有限的行程、有限的内容长度乘出了非正的点数、步行在已经截断之后又遇到兄弟节点，以及执行器报告「不是执行器的工作」。`LockedCommandSnapshot.replace` 没有被测试直接调用；测试在初始化时放入快照，按键路径只读 `current()`。

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。`AXInputFocuser.swift` 整文件在 Linux 上不编译，脚本也不把它放进 90% 门槛。

状态文件里的 `updated` 时间改成 `2026-11-17T07:20:35.000Z`，和这一轮结束时间一致。只改了这一处元数据。`CommandFollowThrough.swift`、`NormalCommandSession.swift` 和 `ScrollAreaCatalog.swift` 没有再改，所以上面的覆盖率仍然是这一轮的数字。

## 滚动区域怎么选

写在 `ScrollAreaCatalog` 的注释里。顺序是固定的。

1. **窗口树在钩子外读好。** 按键路径只读快照，再读一次指针。指针不是辅助功能树。
2. **有可用滚动条的节点才是目标。** 数值、最小值、最大值都有限，并且最大值大于最小值。只有 `AXScrollArea` 角色、没有滚动条，不是目标。没有条就没有可测的行程，滚它是猜测。
3. **行程。** `contentLength` 有限并且大于可见边时，剩余比例乘以「内容减可见」。否则离开那一端的行程是 1，贴在那一端是 0，内容长度保持 nil。任务 9 因此仍会让「只有焦点、又不知道内容长度」的点和半页放过；指针下的点和半页走滚轮。
4. **指针和焦点。** 点落在框内（含边界）才标指针或焦点。按键时用当时的指针和缓存的焦点中心重算这两个标志。过期的 `true` 不作数。焦点中心是焦点框的中心。
5. **标识。** 窗口根是 `root`、深度 0。子节点用从根数下来的下标，用 `/` 接起来，深度是路径长度。
6. **截断就整表丢掉。** 节点上限或 `childrenTruncated` 都算截断。更深的区域可能被切掉，不能拿剩下的去滚。快照标成未就绪，会话把滚动键交还。
7. **然后用任务 9 的 `ScrollHitRule`。** 指针下还能移动的区域优先，然后是焦点所在的区域。都没有，执行器放过，会话把原来的键交还。不滚别的窗口。

`gg` 仍是向上到边，`G` 仍是向下到边。到边设置滚动条，不用有限像素去假装尽头。

## gi、放过下一键、yy

| 按键 | 结果 |
| --- | --- |
| `j` `k` `h` `l` `d` `u` `gg` `G`，目录就绪且命中 | 吞掉，把 CommandMap 的动作交给 `ActionActuator` |
| 同上，目录空、未就绪，或重算后没有能移动的区域 | 原键放过，不发滚动 |
| `H` `L` `J` `K`，bundle id 在任务 9 的名单里 | 吞掉，发出对应快捷键 |
| 同上，不在名单里 | 吞掉，一步都不发 |
| `x` `t` `r` `/` | 不限应用，吞掉并发出快捷键 |
| `yy`，名单内 | 吞掉，先 Command+`l` 再 Command+`c` |
| `yy`，名单外 | 吞掉，两下都不发 |
| `gi`，缓存里有第一个输入框，聚焦成功，随后焦点可编辑 | 吞掉，进入 Insert。下一键放过 |
| `gi`，查询是 `none` 或 `unavailable` | 吞掉，不聚焦，留在普通模式 |
| `gi`，聚焦调用返回失败 | 不发布焦点，留在普通模式 |
| `gi`，聚焦成功但焦点仍不可编辑 | 留在普通模式，下一键仍可以滚动 |
| `Ctrl+]` | 吞掉，不发给执行器。下一键放过，再下一键恢复 |
| 带来源标记的合成键 | 放过，不算进「放过下一键」，也不滚动 |

`yy`、历史和标签的名单就是 `PromisedApplications.browserBundleIdentifiers`。比较仍是整段相等。没有另写一份。

## 交给所有者看的决定

规格写了滚动方向、作用在指针或焦点所在的可滚动区域、选不到必须放过、`gi` 聚焦第一个输入框并进入 Insert、`Ctrl+]` 放过下一键、`yy` 只对 Safari 和 Chromium 承诺。没有写滚动条怎么变成行程、截断怎么办、聚焦失败时进不进 Insert。选择按任务 8、任务 9 和宪法「不确定就放过」。没有改规格正文。

1. **分流在 `CommandFollowThrough`，执行在 `NormalCommandSession`。** 核心不导入辅助功能或事件框架。滚动条树在 `ScrollAreaCatalog`，因为它用的是系统层已经复制好的元素。
2. **选不到滚动目标时，原键交还。** 这是规格第 6 条歧义的「放过」。快捷键被名单拒绝时不交还：`y` 已经作为前缀吞掉，只放回第二下会打出一个多余的字符。执行器一步都不发。
3. **`x` 仍是 Command+`w`，不限浏览器。** 沿用任务 5 和任务 9。规格没有像 `yy` 那样限制关闭。
4. **没有平滑滚动。** 一个动作一次滚动。步长仍是 60 点，半页仍是可见区域的 1/2。
5. **macOS 读取不填 `contentLength`。** 没有稳定的公开常量表示滚动内容的点数。不把 0...1 的滚动条猜成像素。指针下仍走滚轮。这条 AX 路径没有在真实控件上跑过。
6. **截断的树不滚动。** 上限仍是任务 8 的 2000 个节点、深度 32。大页面可能因此放过 `j`。这是未确认的选择。
7. **焦点点用框的中心。** 坐标不翻转。任务 9 已经要求调用方传入 Quartz 全局点。
8. **`gi` 不发 `manualInsert`。** 聚焦之后走任务 8 的焦点分类。可编辑才自动进入 Insert。`unavailable` 不当成「页面上没有输入框」，也不聚焦一个更靠后的控件。
9. **按键路径不扫窗口。** `CommandSnapshotBuilder` 在钩子外建快照。占位程序没有调用它。
10. **占位程序和 `CGEventTapSession` 仍不执行动作。** 现在就安装钩子，会在微信、备忘录和 Safari 地址栏的不吞字验收完成之前吞掉 `j`。那三项保持未测。
11. **`yy` 的 bundle id 沿用任务 9，不新列一份。** Safari `com.apple.Safari`；Chrome `com.google.Chrome`；Chromium `org.chromium.Chromium`；Edge `com.microsoft.edgemac`；Brave `com.brave.Browser`；Arc `company.thebrowser.Browser`；Vivaldi `com.vivaldi.Vivaldi`。这些标识没有经过所有者确认。Firefox 和 Opera 不在里面。大小写和空白都要完全一致。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit、CoreGraphics 或 ApplicationServices
- 没有移动真实指针，没有发出真实的 CGEvent，没有改过真实滚动条
- 没有在真实应用里聚焦第一个输入框，也没有看到因此进入 Insert
- 没有在真实应用里确认 `Ctrl+]` 会把下一键交给前台
- 微信、备忘录、Safari 地址栏里输入时字符不被吞掉：未测
- 没有验证授权之后不重启就能读到滚动条或焦点
- 没有测量 CPU 或内存
- 菜单栏占位程序没有安装事件钩子，也没有启动这条会话
