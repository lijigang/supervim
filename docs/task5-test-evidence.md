# 任务 5 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit

因此下面能证明的是 CommandMap 的先失败、后通过，以及 Linux 上 `CommandMap.swift` 的覆盖率。不能证明快捷键会发到前台应用，也不能证明页面会滚动。那是任务 7 和任务 11。macOS 上的同一组测试和覆盖率交给 GitHub Actions。本文写完时，那次 CI 还没有结果；PR 说明里的检查状态才是实际结果。

## 范围

只加了 `SupervimCore` 里的 `CommandMap`。没有 EventTap，没有 Actuator，没有改 KeyParser、ModeMachine 或 HintLabeler。`Sources/SupervimCore` 仍然不导入 AppKit 或其他系统界面、事件框架；原有的边界测试在通过的那一轮里仍然通过。

映射的输入是 KeyParser 已经产出的 `KeyCommand` 和 `KeyParseResult`。本类型不读模式，也不调用 ModeMachine。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 05:35:57 UTC 到 05:36:01 UTC。命令：`swift test --filter CommandMapTests`。当时还没有 `CommandMap.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/CommandMapTests.swift:368:17: error: cannot find type 'Action' in scope
Tests/SupervimCoreTests/CommandMapTests.swift:374:20: error: cannot find 'ScrollAmount' in scope
Tests/SupervimCoreTests/CommandMapTests.swift:377:77: error: cannot find type 'Action' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：`action(for:)` 忽略命令，永远返回向左滚动 0 点；`disposition(for:)` 永远返回放过；`bindings` 永远是空数组。步长记成 0，半页记成 0/1。空实现不是最终行为。

## 第二次运行：断言失败（RED）

时间：2026-11-17 05:36:22 UTC 到 05:36:27 UTC。命令：`swift test --filter CommandMapTests`。退出码 1。

```text
Test Suite 'CommandMapTests' failed at 2026-11-17 05:36:27.434
	 Executed 32 tests, with 110 failures (0 unexpected) in 0.209 (0.209) seconds
```

32 个测试里 26 个失败，110 次断言失败。失败原因是空实现不产生滚动、快捷键、提示或帮助，不是拼写错误。代表输出：

```text
testScrollStepIsSixtyPoints : XCTAssertEqual failed: ("0") is not equal to ("60")
testHalfPageIsOneHalfOfTheVisiblePage : XCTAssertEqual failed: ("0") is not equal to ("1")
testEveryCommandTokenMapsToTheApprovedAction : XCTAssertEqual failed: ("scroll(...left...points(0))") is not equal to ("scroll(...down...points(60))") - j
testEveryCommandTokenMapsToTheApprovedAction : XCTAssertEqual failed: ("scroll(...left...points(0))") is not equal to ("beginHint(...command)") - F
testCopyURLIsCommandLThenCommandC : XCTAssertEqual failed: ("scroll(...left...points(0))") is not equal to ("sequence([sendShortcut(l), sendShortcut(c)])")
testHeldPrefixIsSwallowed : XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
testBindingsFollowTheSpecOrder : XCTAssertEqual failed: ("[]") is not equal to ("["j", "k", "h", "l", ...]")
```

有六个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testBindingKeysRoundTripThroughKeyParser`：空的 `bindings` 让循环一次都不跑
- `testLookupIsStable`：常量函数本来就稳定
- `testSingleShortcutsUseTheUnshiftedBaseCharacter`：空的 `bindings` 没有快捷键可检查
- `testUnknownKeysPassThrough`、`testModifiedPlainKeysPassThrough`、`testPauseChordIsNotACommandAction`：空实现的 `disposition` 本来就永远返回放过，而这三处的期望正好是放过

真正先失败的是 24 条命令的动作、半页和页边、快捷键、`F` 的 Command 点击、`yy` 的两步序列、前缀吞掉，以及帮助表。实现之后这六个本来就通过的测试仍然通过，它们单独不能证明映射是对的。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 05:37:25 UTC 到 05:37:28 UTC。命令：`swift test --filter CommandMapTests`。退出码 0。构建日志里没有编译警告。

这一轮之前有一次编译错误：`halfPage` 写成了实例成员。那不是断言失败。改成 `Self.halfPage` 之后才跑到测试。

```text
Test Suite 'CommandMapTests' passed at 2026-11-17 05:37:28.687
	 Executed 32 tests, with 0 failures (0 unexpected) in 0.106 (0.106) seconds
```

这一轮还没有把任务 5 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 05:38:56 UTC 到 05:39:00 UTC。命令：`scripts/command-map-coverage.sh`。退出码 0。

脚本里面会再跑一次 `swift test --enable-code-coverage`。`MenuBarPreflightTests` 5 个、`SupervimCoreTests` 189 个（含 `CommandMapTests` 32 个、`HintLabelerTests` 41 个、`KeyParserTests` 36 个、`ModeMachineTests` 61 个、`MenuBarManifestTests` 18 个，以及已经改成任务 5 `done` 的 `TaskGraphTests`）全部通过，0 失败。合计 194 个 XCTest。Swift Testing 库另外报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。构建日志里没有编译警告。

同一轮 llvm-cov 对 `Sources/SupervimCore/CommandMap.swift` 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
CommandMap.swift line coverage: 100.00% (103/103)
CommandMap.swift region coverage: 100.00% (37/37)
CommandMap.swift function coverage: 100.00% (8/8)
```

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。写本文时 CI 还没有跑完。

状态文件里的 `updated` 时间在这一轮之后改成 `2026-11-17T05:39:00.000Z`。只改了这一处元数据。随后单独再跑 `swift test --filter TaskGraphTests`，1 个测试通过。`CommandMap.swift` 没有再改，所以上面的覆盖率仍然是这一轮的数字。

## 给任务 7 和任务 11 用的值

全是值类型。查一次表不会改到原来那份。

| 入口 | 作用 |
| --- | --- |
| `CommandMap().action(for:)` | 一个 `KeyCommand` 变成一个 `Action` |
| `CommandMap().disposition(for:)` | 一个 `KeyParseResult` 变成执行、放过或吞掉 |
| `CommandMap().bindings` | 24 行帮助表，顺序固定。含按键、动作、摘要、是否偏离 Vimium、承诺的应用名 |
| `CommandMap.scrollStepPoints` | 60。`j` / `k` / `h` / `l` 都用它 |
| `CommandMap.halfPageNumerator` / `halfPageDenominator` | 1 和 2。`d` / `u` 用可见区域的一半 |

`Action` 的样子：

- `.scroll(direction:amount:)`：方向是左、下、上、右。数量是 `.points`、`.fractionOfPage(numerator:denominator:)` 或 `.edge`
- `.sendShortcut(KeyCombo)`：一个应用快捷键。字符是未按 Shift 的基本键
- `.sequence([Action])`：按顺序做。`yy` 是两下快捷键，里面不再套序列
- `.beginHint(HintClick)`：`f` 是 `.plain`，`F` 是 `.command`
- `.showHelp`、`.focusFirstInput`、`.passNextKey`、`.escape`、`.enterInsert`

`CommandDisposition`：`.perform(Action)`、`.passThrough`、`.swallow`。未知键是放过。尚未完成的前缀，以及被取消的前缀，是吞掉，不补发给应用。

向上加 `.edge` 是滚动范围的起点（顶部）。向下加 `.edge` 是终点（底部）。任务 11 按这个解释，不要把顶部做成向下滚。

## 命令表

24 行，和 KeyParser 的命令记号一一对应。`hint` 有普通和 Command 两种。

| 按键 | 记号 | 动作 |
| --- | --- | --- |
| `j` / `k` / `h` / `l` | 下 / 上 / 左 / 右 | 滚动 60 点 |
| `d` / `u` | 半页下 / 半页上 | 可见区域的 1/2 |
| `gg` / `G` | 到顶部 / 到底部 | 向上到边 / 向下到边 |
| `gi` | 聚焦第一个输入框 | `.focusFirstInput`。不另发 `.enterInsert` |
| `Ctrl+]` | 放过下一键 | `.passNextKey`。下一键由解析器给出放过 |
| `H` / `L` | 历史后退 / 前进 | Command+`[` / Command+`]` |
| `J` / `K` | 上一个标签 / 下一个标签 | Command+Shift+`[` / Command+Shift+`]` |
| `x` / `t` / `r` | 关闭 / 新建 / 刷新 | Command+`w` / Command+`t` / Command+`r` |
| `/` | 查找 | Command+`f` |
| `yy` | 复制 URL | 先 Command+`l`，再 Command+`c` |
| `f` / `F` | 提示 | `.beginHint(.plain)` / `.beginHint(.command)` |
| `?` | 帮助 | `.showHelp` |
| `i` | 插入 | `.enterInsert` |
| `Esc` | 离开 | `.escape` |

`F` 是 Command 点击，不是右键菜单，也不是快捷键。帮助表把 `F`、`/`、`?` 标成偏离 Vimium。其余行不标。

`yy` 的承诺应用名只有规格里的两个词：`Safari`、`Chromium`。没有 bundle identifier。本类型不知道前台是谁，所以 `action(for: .copyURL)` 仍然返回那两下快捷键。任务 11 在发出去之前要读 `promisedApplicationNames`。

## 交给所有者看的决定

规格没有写步长，也没有写要合成的快捷键。选择按 Vimium 的默认距离，以及 macOS 上 Safari 和 Chrome 共用的快捷键。没有改规格正文。

1. **`j` / `k` / `h` / `l` 各滚动 60 点。** 这是 Vimium 默认的 `scrollStepSize`。四个方向用同一个数。Vimium 没有单独的横向步长默认值。
2. **`d` / `u` 是可见区域的 1/2。** 规格写的是半页。Vimium 的 `scrollPageDown` / `scrollPageUp` 也是 `viewSize * 1/2`，不是整页。
3. **`gg` 是向上到边，`G` 是向下到边。** 对应 Vimium 的 `scrollTo("y", 0)` 和 `scrollTo("y", "max")`。不是一段像素。
4. **动作里没有平滑滚动。** Vimium 默认开着平滑滚动。那是动画，不是距离。任务 11 可以自己做，也可以一下跳过去。
5. **没有次数。** KeyParser 不产生 `3j` 这种次数。一个记号就是一个动作。
6. **`H` / `L` 合成 Command+`[` / Command+`]`。** 这是 Safari、Chrome、Firefox 在 macOS 上的历史后退和前进。这里没有浏览器自己的 `history.go`。
7. **`J` / `K` 合成 Command+Shift+`[` / Command+Shift+`]`。** 方向沿用任务 3：`J` 是上一个标签，`K` 是下一个。这也是这些浏览器在 macOS 上的标签顺序。
8. **`x` / `t` / `r` / `/` 合成 Command+`w` / Command+`t` / Command+`r` / Command+`f`。** 字符是未按 Shift 的基本键，修饰键只有 Command。刷新不是 Command+Shift+`r`。
9. **`yy` 是先 Command+`l` 再 Command+`c`，中间没有延迟。** 没有 Chrome 的剪贴板接口，所以先聚焦地址栏再复制。这能复制地址栏里的文字，不保证那一定是规范化的 URL。
10. **`yy` 的应用名只写规格里的 Safari 和 Chromium，不写 bundle id。** 规格的歧义说明把具体标识交给任务 6 和任务 11。下面这些标识都没有写进代码，也没有经过所有者确认：Safari `com.apple.Safari`；Chrome `com.google.Chrome`；Chromium `org.chromium.Chromium`；Edge `com.microsoft.edgemac`；Brave `com.brave.Browser`；Arc `company.thebrowser.Browser`；Opera `com.operasoftware.Opera`；Vivaldi `com.vivaldi.Vivaldi`。规格里的「Chromium」是不是包含 Chrome、Edge、Brave 这些，也还没定。Firefox 不在承诺里。
11. **本类型不因为前台应用而丢掉 `yy`。** 它不知道前台是谁。任务 11 读到承诺名单之后再决定发不发。
12. **`F` 是 `.beginHint(.command)`。** 规格规定这是按住 Command 的点击，不是右键菜单，也不是 Vimium 的「在新标签打开」。帮助表标了偏离。
13. **`/` 标成偏离 Vimium。** 规格要求查找走该应用自己的快捷键，所以是 Command+`f`，不是 Vimium 自己的查找模式。
14. **`?` 只给出 `.showHelp`，不在这里开关。** 再按 `?` 或 Esc 关掉帮助是任务 12 的事。这和任务 3 的决定一致，相对 Vimium 的切换是偏离，帮助表标了。
15. **`gi` 不附带 `.enterInsert`。** 规格要求聚焦后进入插入模式。任务 3 已经决定不另发 `manualInsert`，等扫描器报告焦点可编辑后再自动进入。任务 11 负责这件事。
16. **`i` 是 `.enterInsert`，Esc 是 `.escape`。** CommandMap 不调用 ModeMachine。任务 7 把这两个动作接回去。
17. **`.passNextKey` 不自己再吃掉下一键。** 解析器已经把紧接着的那一键收成放过。事件钩子按放过交回系统。
18. **未知键、带 Command 的普通键，以及 Ctrl+Option+V，都是放过。** 暂停仍不在这张表里。前缀等待和前缀取消是吞掉。
19. **快捷键复用 `KeyModifiers`。** 不另做一套修饰键。Command+Shift+`[` 的字符是 `[`，Shift 在修饰键里，不是 `{`。
20. **帮助摘要是英文。** 现有菜单文案是「Quit Supervim」。这一轮没有做本地化。
21. **新建是 Command+`t`，不去打开一个网址。** Vimium 可以打开自己的新标签页。宪法要求运行时不联网，所以用应用自己的新建快捷键。命令名仍然是新建，帮助表没有把这一行标成偏离。
22. **关闭是 Command+`w`，不限于浏览器。** 规格没有像 `yy` 那样把 `x` 限制在 Safari 和 Chromium。浏览器里这通常是关掉标签，和其他应用里关掉窗口不是同一件事。任务 11 如果要区分，需要另做决定。
23. **没有右键菜单这种动作。** `F` 不会变成它。
24. **放过和吞掉不放进 `Action`。** 它们在 `CommandDisposition` 里。`.sequence` 里只放要执行的动作。

## 没有测的东西

- 没有在 macOS 上编译或运行
- 没有 CGEvent、辅助功能树、滚动、点击或真正发出的快捷键
- 没有测量某一页的一半是多少像素
- 没有按 bundle id 过滤 `yy`
- 没有把 `.showHelp` 接到浮层，也没有把 `.enterInsert` 接到 ModeMachine
