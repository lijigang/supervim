# 任务 7 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit，没有 CoreGraphics

因此下面能证明的是事件决策链的先失败、后通过，以及 Linux 上 `EventInterpreter.swift` 和 `EventTap.swift` 的覆盖率。不能证明 `CGEventTap` 真的装上了，也不能证明按键会被系统吞掉或交还。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。写本文时那次 CI 还没有结果。

## 范围

加了 `SupervimCore` 里的 `EventInterpreter`，以及 `SupervimSystem` 里的焦点缓存、扫描协议、按键翻译和 `EventTapWiring`。macOS 上另有 `CGEventTapSession`，用 `CGEvent.tapCreate` 把按键交给同一条决策。菜单栏占位程序没有安装这个钩子。

`KeyParser` 增加了 `suspendParsing()`，用来在离开普通模式时丢掉尚未完成的前缀和「放过下一键」，并且不把前缀补发给应用。没有改 ModeMachine、CommandMap、HintLabeler 或 Settings 的行为。

决策只返回放过、吞掉、动作或浮层更新。不点击、不滚动、不画浮层，也不在按键路径上扫描辅助功能树。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 06:19:16 UTC 到 06:19:21 UTC。命令：`swift test --filter 'EventInterpreterTests|EventTapTests|testSuspendParsing'`。当时还没有 `EventInterpreter.swift`，也没有 `EventTap.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/EventInterpreterTests.swift:564:22: error: cannot find 'CachedFocus' in scope
Tests/SupervimCoreTests/EventInterpreterTests.swift:570:22: error: cannot find type 'EventInterpreter' in scope
Tests/SupervimCoreTests/EventInterpreterTests.swift:588:44: error: cannot find type 'EventDecision' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：解释器忽略焦点和按键，永远返回普通模式放过；`suspendParsing()` 返回 nil，不清除状态；系统翻译永远返回 nil；接线在每次按键和发布缓存时都调用扫描器；时钟永远返回 0。还没有 `CGEventTapSession.swift`。空实现不是最终行为。

## 第二次运行：断言失败（RED）

时间：2026-11-17 06:19:52 UTC 到 06:19:58 UTC。同一条命令。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'EventTapTests' failed at 2026-11-17 06:19:57.859
	 Executed 24 tests, with 48 failures (1 unexpected) in 0.206 (0.206) seconds
Test Suite 'EventInterpreterTests' failed at 2026-11-17 06:19:58.283
	 Executed 39 tests, with 116 failures (0 unexpected) in 0.414 (0.414) seconds
Test Suite 'KeyParserTests' failed at 2026-11-17 06:19:58.284
	 Executed 1 test, with 3 failures (0 unexpected) in 0.001 (0.001) seconds
```

这一轮过滤器一共跑了 64 个测试。失败原因是空实现一律放过、不暂停、不给出滚动或提示，而且按键路径调用了扫描器，不是拼写错误。那 1 个 unexpected 是 `CGEventTapSession.swift` 还不存在，源码测试抛了「文件不存在」。代表输出：

```text
testDefaultPauseShortcutTogglesPauseOutsideTheParser : XCTAssertEqual failed: ("...passThrough...normal...") is not equal to ("...swallow...paused...")
testEveryDefaultBindingReachesTheCommandMapAction : XCTAssertEqual failed: ("passThrough") is not equal to ("swallow") - j
testEveryDefaultBindingReachesTheCommandMapAction : XCTAssertEqual failed: ("[]") is not equal to ("[...scroll(...down...points(60))]") - j
testKeyDecisionUsesTheCacheAndDoesNotScan : XCTAssertEqual failed: ("1") is not equal to ("0")
testSuspendParsingDropsPrefixAndPassNextWithoutReplaying : XCTAssertEqual failed: ("nil") is not equal to ("Optional(...prefixCancelled)")
testMacOSTapSourceInstallsATapAndDoesNotScanOrAct : threw error "The file doesn’t exist."
```

有 9 个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testFreshInterpreterPassesKeysUntilFocusAndAppAreKnown`
- `testUnknownEditabilityPassesKeysThatWouldOtherwiseBeCommands`
- `testExcludedAppsPassKeysIncludingThePauseChord`
- `testEscapeInNormalPassesThrough`
- `testPauseRequiresTheExactShortcut`
- `testUnknownNormalKeyPassesThrough`
- `testInterpreterSourceDoesNotTouchTheSystemOrRecordKeys`
- `testKeyUpAndNonKeyDownDoNotBecomeKeyEvents`：空翻译本来就返回 nil
- `testMenuBarPlaceholderDoesNotInstallTheTap`：占位程序本来就没有钩子

真正先失败的是暂停切换、命令动作、提示浮层、排除列表之外的滚动、前缀取消、扫描器不被按键路径调用，以及 macOS 钩子源文件。实现之后这 9 个本来就通过的测试仍然通过，它们单独不能证明接线是对的。

断言红灯之后、实现之前，又加了两条翻译测试：`testModifiedUnmappedKeyKeepsAPlainUnicodeCharacter` 和 `testUnmappedPlainKeyIsUnnamed`。空翻译返回 nil，它们会和上面的翻译测试一样失败。红灯日志里没有这两条，因为它们是后加的。通过的那一轮包含它们。

## 第三次运行：实现之后先有两条测试写错，再通过（GREEN）

时间：2026-11-17 06:22:41 UTC 到 06:22:45 UTC。同一条命令。退出码 1。`EventTapTests` 26 个已经通过。失败的是两条测试期望，不是空实现那种行为错误。

```text
testManualInsertPassesTextAndEscapeAsksToBlur : XCTAssertEqual failed: ("...swallow...scroll(...down...points(60))...") is not equal to ("...passThrough...normal...")
testSuspendParsingDropsPrefixAndPassNextWithoutReplaying : XCTAssertEqual failed: ("[prefixCancelled, command(passNextKey)]") is not equal to ("[command(passNextKey)]")
```

第一处：手动 Insert 下面焦点本来就不可编辑。ModeMachine 在这种 Esc 之后不把焦点改成未知，所以下一键 `j` 应当滚动。测试原先把「可编辑焦点 Esc 之后先放过」写到了这条上。已改成期望滚动，并另加 `testEscapeFromAutomaticInsertPassesKeysWhileTheFieldStillLooksEditable`。

第二处：测试在 Ctrl+] 之前又按了一个 `g`，前缀还在，所以解析器先取消前缀再报放过下一键。测试已先调用 `suspendParsing()` 清掉这个前缀。生产代码没有为了迁就这两条而改口。

时间：2026-11-17 06:23:36 UTC 到 06:23:39 UTC。同一条命令。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'EventTapTests' passed at 2026-11-17 06:23:38.869
	 Executed 26 tests, with 0 failures (0 unexpected) in 0.208 (0.208) seconds
Test Suite 'EventInterpreterTests' passed at 2026-11-17 06:23:39.288
	 Executed 40 tests, with 0 failures (0 unexpected) in 0.411 (0.411) seconds
Test Suite 'KeyParserTests' passed at 2026-11-17 06:23:39.289
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

这一轮还没有把任务 7 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 06:24:36 UTC 到 06:24:43 UTC。命令：`scripts/event-tap-coverage.sh`。退出码 0。构建日志里没有编译警告。

脚本里面会再跑一次 `swift test --enable-code-coverage`。`EventTapTests` 26 个、`MenuBarPreflightTests` 5 个、`UserDefaultsSettingsStoreTests` 10 个，系统测试合计 41 个。`SupervimCoreTests` 266 个（含 `EventInterpreterTests` 40 个、`KeyParserTests` 37 个、`CommandMapTests` 32 个、`HintLabelerTests` 41 个、`ModeMachineTests` 61 个、`SettingsTests` 36 个、`MenuBarManifestTests` 18 个，以及已经改成任务 1–7 都是 `done` 的 `TaskGraphTests` 1 个）全部通过，0 失败。合计 307 个 XCTest。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

同一轮 llvm-cov 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
EventInterpreter.swift line coverage: 98.05% (201/205)
EventInterpreter.swift region coverage: 97.40% (75/77)
EventInterpreter.swift function coverage: 100.00% (23/23)
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
EventTap.swift line coverage: 99.05% (104/105)
EventTap.swift region coverage: 98.08% (51/52)
EventTap.swift function coverage: 100.00% (16/16)
```

同一份 profdata 上，`KeyParser.swift` 仍然是 100%（171/171 行）。`suspendParsing()` 被这条新测试和解释器的离开普通模式路径盖住。

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。`CGEventTapSession.swift` 整文件包在 `#if os(macOS)` 里，Linux 上不计入覆盖率，脚本也不把它放进 90% 门槛。

## 接线在做什么

`EventInterpreter` 拿一份已经缓存的焦点：可编辑性加上 bundle id。按键路径不扫描。

| 情况 | 结果 |
| --- | --- |
| 焦点未知 | 放过，包括 `f`、Esc 和暂停键。不 blur |
| bundle id 为空、只有空白，或在排除列表里 | 完全放过，包括暂停键。比较走 `Settings.isExcluded` |
| 已知焦点、应用不受排除，暂停键与设置完全一致 | 吞掉，并调用 `ModeMachine.togglePause`。不进入解析器 |
| 普通模式、焦点不可编辑、键在命令表里 | 吞掉，返回 CommandMap 的动作。不执行 |
| 普通模式、不认识的键 | 放过 |
| 普通模式的 Esc | 放过。命令表里的 `perform(escape)` 不采用 |
| `f` / `F` | 进入 Hint，浮层更新是开始提示。不点击 |
| Hint 里的非 Esc | 吞掉，浮层更新带着这一键。命令不再解释 |
| Hint 里的 Esc | 吞掉，结束提示 |
| Insert | 放过文字。Esc 吞掉并带 `blurFocus` |
| 可编辑焦点上的 Esc 之后，缓存仍是可编辑 | 重新进入自动 Insert，这一键放过 |
| 手动 Insert 且焦点不可编辑时 Esc | blur，下一键可以立刻当命令 |
| `?` | 每次都是 `showHelp`。第二次不在这里关闭 |
| `gi` | 只有 `focusFirstInput`，不进入 Insert |
| `g` / `y` 前缀 | 第一键吞掉。凑不齐时第二键重解析。离开普通模式、暂停或超时设置改变时，前缀丢掉且不补发 |
| Ctrl+] | 吞掉。下一键放过，再下一键恢复 |
| 键抬起、修饰键变化、其它事件 | 不进入解析器，交给系统 |

`EventTapWiring.refreshFocus()` 才会调用扫描器。`handleKeyDown`、`handleSystemRecord` 和 `publishCachedFocus` 只读缓存。测试用一份会返回「可编辑」的假扫描器，断言按键路径的调用次数是 0，并且 `j` 仍然是向下滚动而不是插入。

## 交给所有者看的决定

规格和计划写了钩子只读模式和缓存、未知焦点放过、排除应用不拦截、普通模式未知键放过。没有写暂停键在钩子里的精确位置、浮层状态机，以及 CGEvent 怎么翻译成字符。选择按 Vimium、已合并的 ModeMachine / KeyParser / CommandMap / Settings，以及宪法第 2 条（不确定就放过）。没有改规格正文。

1. **决策放在 `EventInterpreter`，系统钩子放在 `SupervimSystem`。** 解释器不导入辅助功能或事件框架。扫描、缓存和安装都是协议，测试注入替身。`CGEventTapSession` 只在 macOS 上编译。
2. **占位程序不安装钩子。** 动作还不会执行。现在就吞掉 `j` 或 `f`，等于丢掉按键。任务 11 和任务 13 再安装。
3. **暂停键在解析器外面。** 默认 Ctrl+Option+V，也可以是设置里的另一组，必须修饰键和字符都完全一致。命中就 `togglePause`，并吞掉这一键。焦点未知或应用被排除时不拦截，连暂停键也放过。Insert、Hint、普通模式和已经暂停时，只要焦点已知且应用不受排除，暂停键都有效。
4. **不读取 `Settings.isPaused`。** 任务 6 把这个布尔值留给任务 13。保存成暂停的用户，在任务 13 接上之前，钩子不会一启动就暂停。本任务也不把暂停写回设置。
5. **解析器只在普通模式、焦点不可编辑、应用不受排除时收到按键。** 其它情况调用 `suspendParsing()`，丢掉前缀和「放过下一键」，不补发。暂停同样会清掉这两样，避免恢复之后补成 `gg`。
6. **超时用设置里的毫秒数。** 默认 1000，和 KeyParser 原来的默认值相同。超时变了就换一个解析器，未完成的前缀丢掉。超时没变就不换，免得把「放过下一键」清掉。没有单独的计时器；下一次被解析的键会按 KeyParser 的规则处理超时。
7. **普通模式的 Esc 放过。** 这是任务 2 的决定，也是规格第 12 条。命令表把 Esc 映射成动作，接线不执行那个动作。
8. **Hint 期间不重新解释命令。** 非 Esc 都吞掉，并作为浮层输入交出去，包括带 Command 的键。标签对不对是任务 10 的事。Esc 结束提示。
9. **`?` 每次都发出显示帮助，不在这里切换关闭。** 任务 3 已经把开关留给任务 12。
10. **`gi` 不直接进入 Insert。** 只返回聚焦动作。以后的扫描器如果报告焦点可编辑，模式机再进入 Insert。
11. **动作和浮层更新只是返回值。** 接线没有执行器，也没有画浮层。`F` 是开始 Command 提示，不是右键菜单，也不是现在就点击。
12. **每键都重新套用缓存。** 可编辑字段上按了 Esc 之后，如果缓存仍说可编辑，就回到自动 Insert，这一键放过。这样在模糊焦点还没被下一轮扫描确认之前，不会把字当成命令吃掉。手动 Insert 且缓存本来就不可编辑时，Esc 之后可以立刻滚动。
13. **修饰键下的字符用美式虚拟键，不用 Option 产生的符号。** 这样 Ctrl+Option+V 仍是 `v` 加上 Control 和 Option，而不是 `√`。没按 Control / Option / Command 时用 unicode，所以当前键盘布局的 `j` 仍然是 `j`。这张虚拟键表没有经过所有者确认。Shift 在这种组合里只做修饰键，不把 `v` 变成 `V`，和 `PauseShortcut` 的「基本键加修饰键」一致。
14. **键抬起不解析。** 重复的键按下会再走一次决策，所以按住 `j` 会多次得到滚动动作。本任务不记录按键。
15. **`yy` 的 bundle id 仍然不写进代码。** 仍沿用任务 5 和任务 6 的未确认列表。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit / CoreGraphics
- 没有安装真正的 `CGEventTap`，也没有在辅助功能权限下看回调
- 没有点击、滚动、模糊焦点或绘制浮层
- 没有走真实的辅助功能树
- 没有把暂停状态写回设置，也没有在菜单栏显示模式
- 没有测量 CPU、内存或 `f` 的延迟
- 没有按 bundle id 过滤 `yy`

## macOS CI：测试辅助函数和 XCTest 重名

第一次 macOS 运行：<https://github.com/lijigang/supervim/actions/runs/44031277566>，作业 <https://github.com/lijigang/supervim/actions/runs/44031277566/job/133863552170>。提交 `7297aed`。`swift build` 通过。Test 步骤失败，退出码 1。Linux 上同一份测试能编译，因为这台机器的 XCTest 没有把 `record` 加到测试实例上。

Apple 的 XCTest 给 `EventTapTests` 一个实例方法 `record`。测试文件里的自由函数 `record(kind:keyCode:flags:unicode:)` 因此对不上。代表错误：

```text
Tests/SupervimSystemTests/EventTapTests.swift:59:55: error: use of 'record' refers to instance method rather than global function 'record(kind:keyCode:flags:unicode:)' in module 'SupervimSystemTests'
Tests/SupervimSystemTests/EventTapTests.swift:60:41: error: type 'Equatable' has no member 'swallow'
```

后面的 `.swallow` 找不到、`[Any]` 不能比较，都是这一处解析失败带出来的，不是决策行为错误。

改法只在测试里：那个辅助函数改名为 `keyRecord`。生产 API 没有改。

改名之后在 Linux 上再跑 `swift test --filter EventTapTests`。时间：2026-11-17 06:29:39 UTC 到 06:29:43 UTC。退出码 0。没有编译警告。

```text
Test Suite 'EventTapTests' passed at 2026-11-17 06:29:43.375
	 Executed 26 tests, with 0 failures (0 unexpected) in 0.107 (0.107) seconds
```

这只证明 Linux 仍能编译并跑过这些断言。macOS 是否不再撞上 `record`，看改名之后的 `macos-latest` 运行。
