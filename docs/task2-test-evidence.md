# 任务 2 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链装到 `$HOME/swift-6.4.2`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit

因此下面能证明的是 ModeMachine 的先失败、后通过，以及 Linux 上 `ModeMachine.swift` 的覆盖率。不能证明事件钩子、辅助功能或浮层。那些不属于任务 2。macOS 上的同一组测试和覆盖率交给 GitHub Actions。本文写完时，那次 CI 还没有结果；PR 说明里的检查状态才是实际结果。

## 范围

只加了 `SupervimCore` 里的 `ModeMachine`。没有 KeyParser，没有 EventTap、AXScanner、Actuator、Overlay，也没有改菜单栏占位程序。`Sources/SupervimCore` 仍然不导入 AppKit 或其他系统界面、事件框架；原有的边界测试在通过的那一轮里仍然通过。

按键进入状态机时已经分成 `escape`、`manualInsert`（`i`）、`hint(.plain)`（`f`）、`hint(.command)`（`F`）和 `other`。字符、组合键和 `gg` 这类序列不在这里解析。菜单暂停和 `Ctrl+Option+V` 都是同一个 `togglePause` 输入，热键本身不在这里识别。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 04:49:53 UTC。命令：`swift test --filter ModeMachineTests`。当时还没有 `ModeMachine.swift`。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。这次命令把输出接进了 `tee`，没有打开 `pipefail`，所以壳的退出码没有留下来；失败依据是编译日志，不是一个保存下来的进程退出码。代表错误：

```text
Tests/SupervimCoreTests/ModeMachineTests.swift:518:22: error: cannot find type 'ModeMachine' in scope
Tests/SupervimCoreTests/ModeMachineTests.swift:519:14: error: cannot find type 'ModeInput' in scope
Tests/SupervimCoreTests/ModeMachineTests.swift:520:11: error: cannot find type 'SupervimMode' in scope
Tests/SupervimCoreTests/ModeMachineTests.swift:521:15: error: cannot find type 'ModeEffect' in scope
Tests/SupervimCoreTests/ModeMachineTests.swift:531:81: error: cannot find type 'ModeMachine' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：`handle` 忽略输入，永远返回 Normal 和空效果。空实现不是最终行为。

空实现编译时有一条测试警告：`testValueCopiesDoNotShareLaterTransitions` 里的 `original` 没有被修改。实现之前把它改成了 `let`。断言没有改。后面的通过轮没有这条警告。

## 第二次运行：断言失败（RED）

时间：2026-11-17 04:50:09 UTC 到 04:50:16 UTC。命令：`swift test --filter ModeMachineTests`。退出码 1。

```text
Test Suite 'ModeMachineTests' failed at 2026-11-17 04:50:16.288
	 Executed 61 tests, with 251 failures (0 unexpected) in 0.513 (0.513) seconds
```

61 个测试里 58 个失败，251 次断言失败。失败原因是空实现不转移模式、也不产生效果，不是拼写错误。代表输出：

```text
testEditableFocusFromNormalEntersInsert : XCTAssertEqual failed: ("normal") is not equal to ("insert")
testEscapeInInsertSwallowsTheKeyAndAsksToBlurFocus : XCTAssertEqual failed: ("[]") is not equal to ("[swallowKey, blurFocus]")
testPlainHintRemembersAPlainClick : XCTAssertEqual failed: ("normal") is not equal to ("hint(plain)")
testUnknownFocusPassesEveryKey : XCTAssertEqual failed: ("[]") is not equal to ("[passKeyThrough]")
testPauseFromHintCancelsHintAndResumesToNormal : XCTAssertEqual failed: ("normal") is not equal to ("paused")
```

有三个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testDefaultModeIsNormal`：空实现的初始模式本来就是 Normal
- `testRepeatedControlledForegroundIsIgnored`：空实现对任何输入都留在 Normal，重复的「受控前台」刚好也是这个结果
- `testRepeatedExcludedForegroundDoesNotEndHintTwice`：这个测试只断言第二次排除的效果为空；空实现任何一次都是空效果

真正先失败的是 Insert、Hint、Esc、暂停、排除应用和未知焦点。实现之后这三个本来就通过的测试仍然通过，它们单独不能证明实现是对的。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 04:51:44 UTC。命令：`swift test`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'MenuBarPreflightTests' passed
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.002 (0.002) seconds
Test Suite 'MenuBarManifestTests' passed
	 Executed 18 tests, with 0 failures (0 unexpected) in 0.115 (0.115) seconds
Test Suite 'ModeMachineTests' passed
	 Executed 61 tests, with 0 failures (0 unexpected) in 0.511 (0.511) seconds
Test Suite 'TaskGraphTests' passed
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

合计 85 个 XCTest，0 失败。Swift Testing 库另外报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

这一轮还没有把任务 1 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 04:53:23 UTC。命令：`scripts/mode-machine-coverage.sh`。退出码 0。

脚本里面会再跑一次 `swift test --enable-code-coverage`。`MenuBarPreflightTests` 5 个、`SupervimCoreTests` 80 个（含 `ModeMachineTests` 61 个和已经改成任务 1 `done`、任务 2 `in-progress` 的 `TaskGraphTests`）全部通过，0 失败。

同一轮 llvm-cov 对 `Sources/SupervimCore/ModeMachine.swift` 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
ModeMachine.swift line coverage: 100.00% (201/201)
ModeMachine.swift region coverage: 100.00% (114/114)
ModeMachine.swift function coverage: 100.00% (16/16)
```

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。写本文时 CI 还没有跑完。

## 实现的转移

默认：模式 Normal，焦点未知，前台应用受控。焦点未知时按键全部放过，所以启动后不会吞键。

下面「效果」为空表示只改模式或什么都不做。`pass` 是放过按键，`swallow` 是吞掉，`blur` 是要求离开输入焦点，`begin(plain|command)` 是打开对应点击方式的 Hint，`end` 是关掉 Hint。

先过这三道门，命中就不再按模式处理按键：

| 条件 | 按键结果 |
| --- | --- |
| 当前是 Paused | 留在 Paused，`pass` |
| 前台在排除列表 | 模式不变，`pass`，不 blur |
| 焦点未知 | 模式不变，`pass`，不 blur |

门没挡住时：

| 当前 | 输入 | 结果 | 效果 |
| --- | --- | --- | --- |
| Normal，焦点明确不可编辑 | `i` | Insert（手动） | `swallow` |
| Normal，焦点明确不可编辑 | `f` | Hint(plain) | `swallow`，`begin(plain)` |
| Normal，焦点明确不可编辑 | `F` | Hint(command) | `swallow`，`begin(command)` |
| Normal，焦点明确不可编辑 | Esc 或其他键 | Normal | `pass` |
| Insert | Esc | Normal | `swallow`，`blur` |
| Insert | `i`、`f`、`F` 或其他键 | Insert | `pass` |
| Hint(plain 或 command) | Esc | Normal | `swallow`，`end`，不 blur |
| Hint | 其他任何已分类按键 | 原来的 Hint，不改点击方式 | `swallow` |
| Hint | `hintCompleted` 或 `hintCancelled` | Normal | `end` |
| 非 Hint | `hintCompleted` 或 `hintCancelled` | 不变 | 无 |

焦点和前台：

| 当前 | 输入 | 结果 | 效果 |
| --- | --- | --- | --- |
| Normal 或 Insert | 焦点变为可编辑 | Insert（自动） | 无 |
| Hint | 焦点变为可编辑 | Insert（自动） | `end` |
| 自动 Insert | 焦点变为不可编辑 | Normal | 无 |
| 手动 Insert | 焦点变为不可编辑 | Insert | 无 |
| Hint | 焦点仍不可编辑 | Hint | 无 |
| Hint | 焦点变为未知 | Normal | `end` |
| Insert | 焦点变为未知 | 仍叫 Insert，但按键改走上面的未知门 | 无 |
| 排除中的应用 | 焦点变化 | 模式不变，只记住焦点 | 无 |
| Hint | 前台变为排除应用 | Normal | `end` |
| 其他模式 | 前台变为排除应用 | 模式不变 | 无 |
| 非暂停，前台从排除变回受控 | 焦点可编辑 | Insert（自动） | 无 |
| 非暂停，前台从排除变回受控 | 焦点不可编辑，且是手动 Insert | Insert | 无 |
| 非暂停，前台从排除变回受控 | 焦点不可编辑，且不是手动 Insert | Normal | 无 |
| 非暂停，前台从排除变回受控 | 焦点未知 | 模式不变，按键继续放过 | 无 |

暂停和恢复。`togglePause` 在未暂停时等于 `pause`，已暂停时等于 `resume`。菜单和 `Ctrl+Option+V` 都发 `togglePause`。

| 当前 | 输入 | 结果 | 效果 |
| --- | --- | --- | --- |
| Normal | pause | Paused，恢复目标 Normal | 无 |
| Insert | pause | Paused，恢复目标同一种 Insert | 无 |
| Hint | pause | Paused，恢复目标 Normal | `end` |
| 已经 Paused | 再 pause | 仍是 Paused，不覆盖恢复目标 | 无 |
| 未暂停 | resume | 不变 | 无 |
| Paused，其间焦点变成可编辑 | resume | Insert（自动） | 无 |
| Paused，自动 Insert 的焦点变成不可编辑 | resume | Normal | 无 |
| Paused，手动 Insert 的焦点仍不可编辑 | resume | 手动 Insert | 无 |
| Paused，焦点变成未知 | resume | 保留原来的恢复目标；未知门继续放过按键 | 无 |
| Paused，前台仍被排除 | resume | 恢复暂停前的模式，但不因为可编辑焦点把 Normal 升级成 Insert | 无 |

Esc 离开「当时焦点确实可编辑」的 Insert 之后，焦点改记为未知，后续按键先放过，直到新的焦点报告到来。手动 Insert 下面焦点本来就不可编辑时，Esc 仍然发出 `blur`，但马上可以再进 Hint。

## 交给所有者看的决定

规格没有把这些岔路写死。选择按 Vimium 的默认手感，并且在不确定时放过按键（宪法第 2 条）。没有改规格正文。

1. **Normal 下的 Esc 放过，不 blur。** 规格只规定 Insert 的 Esc，以及 Hint 里 Esc 取消。Normal 里没有定义的键必须交给前台应用。
2. **机器不解析字符。** `f`、`F`、`i`、Esc 由以后的 EventTap 或 KeyParser 分类后再送进来。`Ctrl+Option+V` 不在这里匹配，菜单和热键都发送 `togglePause`。另外有单独的 `pause` 和 `resume`：连续 pause 不覆盖恢复目标，没暂停时 resume 无操作。
3. **未知焦点一律放过。** 不自动进入 Insert，也不把 `f` / `F` / `i` / Esc 当成命令。已经在 Hint 里则结束 Hint 回到 Normal。已经在 Insert 里时模式名字可以还叫 Insert，但 Esc 不吞、不 blur，直到焦点再次明确。启动时焦点就是未知。
4. **排除应用时完全不碰它的按键。** 不进入 Hint，不 blur。进入排除名单时如果正在 Hint，就结束 Hint。暂停和恢复仍然有效，因为排除的是这个应用的按键，不是菜单。排除期间即使焦点可编辑也不进入 Insert；离开排除并且没有暂停时，才按记住的焦点进入 Insert。排除还没结束就 resume 的话，不因为可编辑焦点把 Normal 升级成 Insert。
5. **Hint 期间不重新解释 `f` / `F` / `i`。** 非 Esc 键都吞掉，点击方式保持进入时的 plain 或 command。标签是否有效由以后的 HintLabeler 和 Overlay 决定，它们再发 `hintCompleted` 或 `hintCancelled`。这两个事件如果不是在 Hint 里发来，就忽略。
6. **暂停会取消 Hint，恢复时不把标签复活。** 恢复目标是 Normal；暂停期间如果焦点变成可编辑，恢复到 Insert。
7. **手动 Insert 和自动 Insert 不一样。** `i` 是手动的，焦点报告「不可编辑」不会把它打回 Normal。焦点落到可编辑控件上是自动的，离开控件就回 Normal。手动 Insert 之后如果焦点变成可编辑，就改记成自动，再离开控件时回 Normal。
8. **Insert 里真正处理 Esc 时总是带 `blur`。** 这是规格第 3 条的字面要求，手动 Insert 也一样。前台如果没有可编辑焦点，以后的执行器可以把 blur 当成空操作。焦点未知、应用被排除或正处于暂停时，Esc 走放过，不发 blur。
9. **`gi`、帮助、滚动和放过下一键都不是本任务的输入。** `gi` 以后可以让扫描器报告焦点可编辑，从而自动进入 Insert。
10. **菜单栏仍不显示模式。** Hint 只存在于状态机内部。任务 13 才把 Normal、Insert、Paused 画出来。

## 没有测的东西

- 没有在 macOS 上编译或运行
- 没有 CGEvent、辅助功能树、点击、滚动或浮层
- 没有解析 `gg`、`gi`、`Ctrl+]` 或 `Ctrl+Option+V` 这几个具体按键
- 没有把模式名画到菜单栏上
- 没有测量 CPU、内存或 `f` 的延迟
