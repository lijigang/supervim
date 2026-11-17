# 任务 3 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链装到 `$HOME/swift-6.4.2`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit

因此下面能证明的是 KeyParser 的先失败、后通过，以及 Linux 上 `KeyParser.swift` 的覆盖率。不能证明事件钩子会把这些结果交给前台应用。那是任务 7。macOS 上的同一组测试和覆盖率交给 GitHub Actions。本文写完时，那次 CI 还没有结果；PR 说明里的检查状态才是实际结果。

## 范围

只加了 `SupervimCore` 里的 `KeyParser`。没有 CommandMap，没有 EventTap、滚动、点击或菜单热键。`Sources/SupervimCore` 仍然不导入 AppKit 或其他系统界面、事件框架；原有的边界测试在通过的那一轮里仍然通过。

解析器不知道 Normal、Insert、Hint、Paused。它只把按键收成命令记号。ModeMachine 仍只认识 `escape`、`manualInsert`、`hint` 和 `other`。滚动、导航这些新记号以后由 CommandMap 和 EventTap 接线，本任务不改 ModeMachine。

时间从外面注入。解析器不调用 `Date`。测试用 `ManualKeyClock.advance(by:)` 把时间往前拨。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 05:06:02 UTC 之前。命令：`swift test --filter KeyParserTests`。当时还没有 `KeyParser.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/KeyParserTests.swift:373:16: error: cannot find type 'ManualKeyClock' in scope
Tests/SupervimCoreTests/KeyParserTests.swift:374:17: error: cannot find type 'KeyParser' in scope
Tests/SupervimCoreTests/KeyParserTests.swift:384:14: error: cannot find type 'KeyEvent' in scope
Tests/SupervimCoreTests/KeyParserTests.swift:385:17: error: cannot find type 'KeyParseResult' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：`handle` 忽略按键，永远返回空结果；`expirePendingPrefix` 永远返回 nil。超时数值会记下来。空实现不是最终行为。

## 第二次运行：断言失败（RED）

时间：2026-11-17 05:06:13 UTC 到 05:06:19 UTC。命令：`swift test --filter KeyParserTests`。退出码 1。

```text
Test Suite 'KeyParserTests' failed at 2026-11-17 05:06:19.622
	 Executed 36 tests, with 175 failures (0 unexpected) in 0.107 (0.107) seconds
```

36 个测试里 35 个失败，175 次断言失败。失败原因是空实现不产生命令、前缀或放过，不是拼写错误。代表输出：

```text
testEveryApprovedSingleKeyBinding : XCTAssertEqual failed: ("[]") is not equal to ("[SupervimCore.KeyParseResult.command(SupervimCore.KeyCommand.hint(SupervimCore.HintClick.plain))]") - f
testLowercaseGThenGScrollsToTop : XCTAssertEqual failed: ("[]") is not equal to ("[SupervimCore.KeyParseResult.waitingForPrefix]")
testUnknownKeysPassThrough : XCTAssertEqual failed: ("[]") is not equal to ("[SupervimCore.KeyParseResult.passThrough]") - q
testControlBracketArmsPassNextKey : XCTAssertEqual failed: ("[]") is not equal to ("[SupervimCore.KeyParseResult.command(SupervimCore.KeyCommand.passNextKey)]")
testLonelyPrefixIsNotACommandAfterTimeout : XCTAssertEqual failed: ("[]") is not equal to ("[SupervimCore.KeyParseResult.waitingForPrefix]")
```

有一个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testDefaultPrefixTimeoutIsOneSecond`：空实现的初始化本来就会把默认超时存成 1000 毫秒

真正先失败的是单键命令、前缀、超时、Esc、修饰键、大小写、未知键和 Ctrl+]。实现之后这个本来就通过的测试仍然通过，它单独不能证明解析是对的。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 05:07:32 UTC 到 05:07:35 UTC。命令：`swift test --filter KeyParserTests`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'KeyParserTests' passed at 2026-11-17 05:07:35.099
	 Executed 36 tests, with 0 failures (0 unexpected) in 0.005 (0.005) seconds
```

这一轮还没有把任务 2 改成 `done`、任务 3 改成 `in-progress`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 05:08:40 UTC 到 05:08:44 UTC。命令：`scripts/key-parser-coverage.sh`。退出码 0。

脚本里面会再跑一次 `swift test --enable-code-coverage`。`MenuBarPreflightTests` 5 个、`SupervimCoreTests` 116 个（含 `KeyParserTests` 36 个、`ModeMachineTests` 61 个、`MenuBarManifestTests` 18 个，以及已经改成任务 2 `done`、任务 3 `in-progress` 的 `TaskGraphTests`）全部通过，0 失败。合计 121 个 XCTest。Swift Testing 库另外报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。构建日志里没有编译警告。

同一轮 llvm-cov 对 `Sources/SupervimCore/KeyParser.swift` 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
KeyParser.swift line coverage: 100.00% (165/165)
KeyParser.swift region coverage: 100.00% (92/92)
KeyParser.swift function coverage: 100.00% (19/19)
```

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。写本文时 CI 还没有跑完。

## 命令表

字符区分大小写。Shift 只表示「这个字符是怎么打出来的」，不单独挡住命令。Control、Option、Command 会挡住单键命令，唯一的例外是 Ctrl+]。

| 输入 | 结果 |
| --- | --- |
| `f` / `F` | `hint(.plain)` / `hint(.command)` |
| `i` | `manualInsert` |
| `h` / `j` / `k` / `l` | 左 / 下 / 上 / 右 |
| `d` / `u` | 半页下 / 半页上 |
| `gg` | 到顶部 |
| `G` | 到底部。单独的 `G` 不等待第二键 |
| `H` / `L` | 历史后退 / 前进 |
| `J` / `K` | 上一个标签 / 下一个标签 |
| `x` / `t` / `r` | 关闭 / 新建 / 刷新 |
| `/` / `?` | 查找 / 帮助 |
| `yy` | 复制 URL |
| `gi` | 聚焦第一个输入框。不另外发出 `manualInsert` |
| Esc | `escape` |
| Ctrl+] | `passNextKey`。紧接着的下一键不解析，结果是放过 |
| `q`、`z`、数字、空格，以及没有列入上表的键 | 放过 |
| Ctrl+Option+V | 放过。这里不识别暂停 |

`J` 是上一个标签、`K` 是下一个标签，按 Vimium 的默认方向（左 / 右）。规格只写了「切换标签页」，没有写方向。见下面的决定。

## 前缀和超时

默认超时 1000 毫秒，构造时可以改。边界是「已经过去的时间大于等于超时」才算过期：999 毫秒内第二键仍然有效，满 1000 毫秒就取消。

- 按下 `g` 或 `y` 之后进入等待。这一下先不交给应用，也不是一条命令。
- 第二键凑成 `gg`、`gi` 或 `yy` 时，发出对应命令。
- 第二键凑不齐时，前缀取消。取消的那一下被吞掉：不发明 `g` 或 `y` 命令，也不补发给应用。第二键再按没有前缀的情况重解析。所以 `gz` 放过 `z`，`gx` 变成关闭，`gu` 变成半页向上，`gy` 改等 `y` 的第二键。
- 超时且没有第二键时，`expirePendingPrefix()` 返回前缀已取消。迟到的键不能把刚才那下补成命令。`g` 然后超时然后 `g`，得到的是一次新的等待，不是到顶部。
- 下一键到来时如果已经超时，结果里会先写前缀已取消，再解析这个新键。
- Esc 会取消尚未完成的前缀，并且仍然报 `escape`。ModeMachine 在 Insert 和 Hint 里已经处理 Esc。
- Ctrl+] 之后的那一键，哪怕是 `j`、`f`、Esc 或另一下 Ctrl+]，都只放过，不解析。再下一键恢复正常。

## 交给所有者看的决定

规格没有把这些岔路写死。选择按 Vimium 的按键状态机，并且不发明规格里没有的命令。没有改规格正文。

1. **凑不齐的前缀：吞掉第一键，重解析第二键。** Vimium 的 `keyState` 在当前前缀对不上时，会退回整张键表。未知的第二键放过（宪法第 2 条，规格第 12 条）。第二键本身是命令时就执行它，不把这一下也丢掉。因此在本子集里，`gu` 不是「向上走网址」（那条不在规格里），而是半页向上。如果所有者希望失败的两键序列整段放过、第二键也不当命令，需要改这个决定。
2. **超时的前缀吞掉，不补发。** `g` 单独不是命令。已经按住的前缀再补发给前台，会变成迟到的一次按键，比漏掉这个快捷键更打扰。Vimium 同样不会把已经吞下的 `g` 重放出来。
3. **Esc 在前缀未完成时既取消，又报 `escape`。** Vimium 是第一下 Esc 只清空按键队列并吞掉。这里同时报 `escape`，是为了让 ModeMachine 在 Insert / Hint 里还能离开。这是相对 Vimium 的偏离，按本任务的要求做。
4. **Ctrl+] 的下一键一律不解析。** 包括 Esc 和本可成命令的键。事件钩子以后负责真的放过那一键。本任务不写 EventTap。
5. **不解析 Ctrl+Option+V。** 暂停仍由菜单或热键在解析器外面发 `togglePause`。带 Control、Option 或 Command 的其它键也放过，避免抢走应用自己的快捷键。
6. **`gi` 只发 `focusFirstInput`，不发 `manualInsert`。** 任务 2 已经记下：`gi` 以后可以由扫描器报告焦点可编辑，从而自动进入 Insert。手动 Insert 在焦点变回不可编辑时不会退出，和这个动作不是一回事。
7. **`J` / `K` 的方向按 Vimium。** `J` 是上一个标签（向左），`K` 是下一个标签（向右）。规格只写了切换，没有写左右。
8. **没有次数前缀。** `3j` 这类重复不在批准的绑定里。数字放过，不发明计数。
9. **大小写以字符为准。** `f` 和 `F`、`g` 和 `G`、`h` 和 `H`、`j` 和 `J`、`k` 和 `K`、`y` 和 `Y` 都不同。`Y`、`I`、`D`、`U` 等没有单独的命令。
10. **Ctrl+] 接受两种写法。** `]` 加上 Control，或字符 U+001D（有没有单独的 Control 修饰都可以，但不能再带 Option、Command 或 Shift）。Ctrl+Shift+] 不是放过下一键。
11. **帮助键只发 `help`。** `?` 再按一次不会在解析器里切换开和关。开关是任务 12 的事。

## 没有测的东西

- 没有在 macOS 上编译或运行
- 没有 CGEvent、辅助功能树、点击、滚动或浮层
- 没有把命令真正执行出去，也没有把 Ctrl+] 的下一键交还给前台应用
- 没有测量 CPU、内存或 `f` 的延迟
