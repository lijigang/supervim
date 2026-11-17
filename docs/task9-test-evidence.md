# 任务 9 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑测试
- 没有 macOS，没有 Xcode，没有 AppKit，没有 CoreGraphics

因此下面能证明的是执行器计划的先失败、后通过，以及 Linux 上 `Actuator.swift` 的覆盖率。不能证明指针真的动了，也不能证明辅助功能的 Press 或滚动条在真实控件上生效。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。写本文时那次 CI 还没有结果。

## 范围

加了 `SupervimSystem` 里的 `ActionActuator`。它把 CommandMap 已经产出的 `Action` 变成点击、滚动或快捷键效果，交给一个 poster。测试用记录调用的 `RecordingActuator`，不驱动真实指针。

macOS 上另有 `CGEventActuatorPoster` 和 `AXElementStore`。文件整段包在 `#if canImport(CoreGraphics) && canImport(ApplicationServices)` 里，Linux 上是空文件。合成事件写入 `SynthesizedEventMark.userData`。`EventTapWiring` 看到这个来源标记就放过，不再交给解析器。`CGEventTapSession` 从 `eventSourceUserData` 读出这个字段。

`KeyParser`、`ModeMachine`、`HintLabeler`、`Settings` 的行为没有改。`CommandMap` 只改了一句注释：执行动作的是任务 9，任务 11 负责把事件钩子的决定接上去。菜单栏占位程序没有安装钩子，也没有调用执行器。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 06:42:50 UTC 起。命令：`swift test --filter 'ActuatorTests|EventTapTests'`。当时还没有 `Actuator.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimSystemTests/ActuatorTests.swift:830:57: error: cannot find type 'ActuatorPoint' in scope
Tests/SupervimSystemTests/ActuatorTests.swift:838:6: error: cannot find type 'ActuationContext' in scope
Tests/SupervimSystemTests/ActuatorTests.swift:902:6: error: cannot find type 'ActuatorOutcome' in scope
```

这是缺类型，不是断言失败。06:43:13 UTC 用同一条命令再抓了一遍 `error:`，仍然是这些缺类型，没有跑到断言。

随后加了一个能编译的空实现：`perform` 和 `click` 忽略参数，永远放过，也不调用 poster；`ActuatorRect.contains` 永远返回 false；浏览器名单是空数组；合成标记是 0；`virtualKeyCode(forUnshifted:)` 永远返回 nil。`CGEventActuator.swift` 只有一行 `#if canImport(CoreGraphics) && canImport(ApplicationServices)`，里面没有点击、滚动或 Press。空实现不是最终行为。

空实现的第一次编译没有跑到断言。测试把 `visibleHeight` 写在 `travelDown` 后面，Swift 要求参数按声明顺序出现。退出码 1。时间：2026-11-17 06:43:34 UTC 到 06:43:36 UTC。

```text
Tests/SupervimSystemTests/ActuatorTests.swift:284:13: error: argument 'visibleHeight' must precede argument 'travelDown'
```

后面的 `type 'Equatable' has no member 'performed'` 是这一处解析失败带出来的，不是执行器行为错误。已把那次调用的参数顺序改对。期望值没有放宽。

改完之后又撞上一次崩溃，不是断言失败。`testCommandClickIsALeftClickWithCommandAndNotAContextMenu` 在空实现返回空数组之后，仍然去读 `effects[0]`。XCTest 默认失败后继续执行。时间在 06:43:52 UTC 到 06:43:56 UTC。进程收到信号 4，整组测试被打断：

```text
Swift/ContiguousArrayBuffer.swift:695: Fatal error: Index out of range
```

那个多余的下标已经删掉。点击效果是否是左键加 Command，由整条 `ActuatorEffect` 的相等断言覆盖。

## 第二次运行：断言失败（RED）

时间：2026-11-17 06:45:51 UTC 到 06:45:54 UTC。命令：`swift test --filter 'ActuatorTests|EventTapTests'`。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'ActuatorTests' failed at 2026-11-17 06:45:53.978
	 Executed 40 tests, with 91 failures (0 unexpected) in 0.319 (0.319) seconds
Test Suite 'EventTapTests' failed at 2026-11-17 06:45:54.487
	 Executed 29 tests, with 12 failures (0 unexpected) in 0.509 (0.509) seconds
```

这一轮过滤器一共跑了 69 个测试，103 次断言失败，0 次 unexpected。失败原因是空实现一律放过、不点击、不滚动、不发快捷键，标记是 0，虚拟键永远是 nil，钩子源文件里没有 `eventSourceUserData`。不是拼写错误。代表输出：

```text
testBrowserAllowlistIsTheSingleDecisionList : XCTAssertEqual failed: ("[]") is not equal to ("["com.apple.Safari", "com.google.Chrome", "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.vivaldi.Vivaldi"]")
testCommandClickIsALeftClickWithCommandAndNotAContextMenu : XCTAssertEqual failed: ("passedThrough") is not equal to ("performed([mouseClick(point: (x: 9.0, y: 9.0), button: left, modifiers: rawValue: 4)])")
testPointerStepScrollUsesSignedWheelPixels : XCTAssertEqual failed: ("passedThrough") is not equal to ("performed([pointerScroll(targetID: "page", direction: down, amount: points(60), location: (x: 20.0, y: 30.0), horizontal: 0, vertical: -60)])") - down
testMarkedScrollKeyDoesNotScroll : XCTAssertEqual failed: ("0") is not equal to ("1398164785")
testUnshiftedVirtualKeyRoundTrip : XCTAssertEqual failed: ("nil") is not equal to ("Optional(38)")
```

`1398164785` 是 `0x53564D31`。`38` 是虚拟键 `0x26`，也就是 `j`。日志里的类型名比这里长，数值和方向没有改。

有 8 个执行器测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testNilPointerDoesNotTrustTheContainsPointerFlag`
- `testNoScrollableTargetPassesThrough`
- `testNonFiniteClickIsPassedThrough`
- `testPlaceholderDoesNotPerformActions`：占位程序本来就没有执行器
- `testRejectedSequenceDoesNotPostTheFirstShortcut`
- `testSequencePostsNothingWhenALaterScrollHasNoTarget`
- `testUncomputableFractionsAndRangesPassThrough`
- `testUnknownShortcutCharacterPassesThrough`

这 8 个的期望正好是放过或「占位程序不调用执行器」。空实现本来就永远放过。实现之后它们仍然通过，单独不能证明滚动或快捷键是对的。

`EventTapTests` 里原有的决策测试在这个空实现上仍然通过。真正先失败的是两条合成标记测试、虚拟键往返，以及 macOS 钩子源文件必须读 `eventSourceUserData`。

06:44:14 UTC 还有一轮更早的断言失败：当时执行器测试是 38 个，还没有后加的 `testSequencePostsNothingWhenALaterScrollHasNoTarget` 和 `testUncomputableFractionsAndRangesPassThrough`。这两条在空实现上也会通过，所以上面 8 条里包含它们。失败次数仍是 91。通过的那一轮包含这两条。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 06:47:40 UTC 到 06:47:44 UTC。同一条命令。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'ActuatorTests' passed at 2026-11-17 06:47:43.768
	 Executed 40 tests, with 0 failures (0 unexpected) in 0.219 (0.219) seconds
Test Suite 'EventTapTests' passed at 2026-11-17 06:47:43.977
	 Executed 29 tests, with 0 failures (0 unexpected) in 0.208 (0.208) seconds
```

这一轮还没有把任务 9 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 06:48:46 UTC 到 06:48:54 UTC。命令：`scripts/actuator-coverage.sh`。退出码 0。构建日志里没有编译警告。

脚本里面会再跑一次 `swift test --enable-code-coverage`。系统测试 84 个：`ActuatorTests` 40、`EventTapTests` 29、`MenuBarPreflightTests` 5、`UserDefaultsSettingsStoreTests` 10。`SupervimCoreTests` 266 个（含已经改成任务 9 `done` 的 `TaskGraphTests` 1 个，任务 8 仍是 `pending`）。合计 350 个 XCTest，0 失败。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

同一轮 llvm-cov 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
Actuator.swift line coverage: 99.41% (336/338)
Actuator.swift region coverage: 98.64% (145/147)
Actuator.swift function coverage: 100.00% (38/38)
```

没盖住的两行是防御性返回：有限的可见高度乘出了非有限的半页距离，以及有限的内容尺寸减出了非有限的滚动范围。正常的半页、越界半页和未知内容尺寸都走了别的返回。

同一份 profdata 上，`EventTap.swift` 是 99.13%（114/115 行），`CommandMap.swift` 仍是 100%（103/103 行）。事件钩子的官方脚本会在 CI 里再跑一遍。`CGEventActuator.swift` 整文件在 Linux 上不编译进覆盖率，脚本也不把它放进 90% 门槛。

状态文件里的 `updated` 时间改成 `2026-11-17T06:48:54.000Z`，和这一轮结束时间一致。只改了这一处元数据。随后单独再跑 `swift test --filter TaskGraphTests`。时间：2026-11-17 06:49:21 UTC 到 06:49:26 UTC。退出码 0。1 个测试通过。`Actuator.swift` 没有再改，所以上面的覆盖率仍然是这一轮的数字。

## 滚动命中规则

写在 `ScrollHitRule` 的注释里。顺序是固定的。

1. **指针链。** `containsPointer` 为真，并且区域的框包含 `ActuationContext.pointer`。指针是 nil 时，这一链是空的，不能只信那个布尔值。按 `depth` 从深到浅，深度相同则按 `identifier` 升序。取第一个在请求方向上还能移动的区域。
2. **焦点链。** 指针链没有能移动的区域时，再看 `isFocusContainer`。已经在指针链里看过的 identifier 跳过。排序同上。
3. **否则放过。** 不滚动一个既不在指针下、也不包着焦点的窗口。

还能移动，是指该方向的剩余行程大于 0。0 或负数表示已经到边，继续往下找。这和 Vimium 一样：指针下的滚动区域优先于焦点所在的区域。

点和半页，如果目标在指针下，就是一次像素滚轮事件，位置用指针。正的垂直分量向上，正的水平分量向右，和 Quartz 滚轮的符号相同。所以 `j` 向下是垂直 `-60`。剩余行程只要大于 0，就发出完整步长，由系统夹到边界，不把 60 点改成剩余的 0.1 点。

半页是可见边长乘以分子再除以分母，四舍五入，0.5 远离 0。结果必须是至少 1 点，并且放得进 `Int32`。算不出来就跳过这个区域。

点和半页如果只命中焦点区域，就改辅助功能滚动条，不发滚轮。这要求该轴的内容尺寸已知、有限，并且大于可见尺寸。效果里带着像素数，以及 `scrollRange = 内容 - 可见`。macOS poster 用这个范围把像素换成 `AXValue` 的增量。读不到滚动条就不改用滚轮。

到边（`gg` / `G`，以及横向的边）永远设置滚动条到那一端，包括指针正放在区域上的时候。滚轮的有限像素不是范围的尽头。向上或向左设最小值，向下或向右设最大值。

选不到、或者距离算不出来，就放过。不乱滚。

## 点击和快捷键

- 普通点击：元素 id 去掉空白后非空，并且 `canAccessibilityPress` 为真，就只做 AXPress，不合成鼠标。否则是左键按下和抬起，没有修饰键。
- Command 点击：永远是左键加上 Command。即使元素支持 AXPress 也不用它，因为 AXPress 按不住 Command。没有右键。
- 坐标不是有限数的点击放过。
- `beginHint`、帮助、聚焦、放过下一键、Esc、进入 Insert 不是执行器的工作，不产生点击。
- 查找、关闭、新建、刷新是 Command+`f` / `w` / `t` / `r`，不限制应用。
- 历史是 Command+`[` / Command+`]`。标签是 Command+Shift+`[` / Command+Shift+`]`。`yy` 是先 Command+`l` 再 Command+`c`。这三类只对下面的名单承诺。其它应用整段放过，`yy` 不会只发出第一下。
- 单独的 Command+`l` 不是 `yy`，不进这道门槛。
- 序列是全部成功才发出。某一步不能做，就一步都不发。某一步不是执行器的工作，结果是 `notActuatorWork`，也不发。
- 字符在美式虚拟键表里没有对应键，就放过，不发一个错误的键。

## 交给所有者看的决定

规格写了点击、Command 点击、滚动方向，以及 `yy` 只对 Safari 和 Chromium 承诺。没有写步长怎么变成事件、滚动区域在树里怎么选、bundle id，也没有写合成事件怎么避免被自己的钩子吃掉。选择按 Vimium、已经合并的 CommandMap，以及宪法「不确定就放过」。没有改规格正文。

1. **计划在 `ActionActuator`，系统发送在 poster 后面。** 测试注入 `RecordingActuator`，只记录效果的种类和参数。单元测试不构造 `CGEventActuatorPoster`，所以不会动真实指针。
2. **`F` 是左键加 Command，不是右键，也不是 AXPress。** 普通点击在有元素 id 且支持 Press 时用 `kAXPressAction`。
3. **滚动命中按上面的三步。** 指针链先于焦点链。选不到就放过。
4. **点和半页在指针下用像素滚轮，符号跟 Quartz。** 步长仍是 CommandMap 的 60 点。半页仍是可见区域的 1/2，四舍五入，0.5 远离 0。放不进 `Int32` 就放过，不发一个被夹短的距离。
5. **到边不用滚轮。** 设置辅助功能滚动条的最小或最大值。指针正停在区域上时也这样。
6. **焦点上的点和半页要有内容尺寸。** 不知道内容比可见区域大多少，就不把像素猜成滚动条的 0 到 1。读不到滚动条时，poster 不改发滚轮。这条 AX 路径没有在真实控件上跑过。
7. **坐标用调用方的空间，poster 不翻转。** 任务 11 如果要打到正确的视图，需要传入 Quartz 全局点（原点在左下）。这是未确认的选择。
8. **`yy`、历史、标签共用一份名单，只写在 `PromisedApplications.browserBundleIdentifiers`。** 比较是整段相等，不忽略大小写，不去掉空白。名单没有经过所有者确认：Safari `com.apple.Safari`；Chrome `com.google.Chrome`；Chromium `org.chromium.Chromium`；Edge `com.microsoft.edgemac`；Brave `com.brave.Browser`；Arc `company.thebrowser.Browser`；Vivaldi `com.vivaldi.Vivaldi`。规格里的 Chromium 在这里包含这六个 Chromium 家族应用。Firefox 和 Opera 不在里面，会放过。
9. **关闭、新建、刷新、查找不限制应用。** 这沿用任务 5：规格没有像 `yy` 那样限制 `x`。空的 bundle id 也会发这些快捷键。排除名单仍由事件钩子负责，执行器不再查一次。
10. **占位程序不调用执行器，钩子也不在这里执行动作。** 任务 10 用点击，任务 11 把滚动和快捷键接到钩子上。现在就安装钩子并吞掉 `j`，动作仍然发不出去。
11. **合成事件的来源用户数据是 `0x53564D31`（ASCII `SVM1`）。** 钩子在解析之前放过它，所以不会把它当成用户的 `j`，也不会把它算进「放过下一键」。鼠标、滚轮和按键都写这个字段。按键同时按下和抬起，避免键粘住。事件发到 `cghidEventTap`，目标应用能收到；会话钩子会再看见它们，所以标记是必须的。
12. **虚拟键沿用任务 7 的美式表。** 不认识的字符放过。Shift 仍是修饰键，字符保持未按 Shift 的基本键。
13. **没有平滑滚动，也没有 `3j` 这种次数。** 一个动作一次滚动。Vimium 默认的平滑滚动是动画，不是距离。
14. **CoreGraphics 和 ApplicationServices 包在 `canImport` 里。** Linux 仍能构建。没有在 Linux 上编译这两套框架。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit、CoreGraphics 或 ApplicationServices
- 没有移动真实指针，没有发出真实的 CGEvent
- 没有对真实的 AX 元素做 Press，也没有改过真实滚动条
- 没有把执行器接到事件钩子的决定上，那是任务 10 和任务 11
- 没有测量某一页的一半在屏幕上是多少像素
- 没有验证授权、CPU 或内存
