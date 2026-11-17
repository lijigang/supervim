# 任务 4 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链装到 `$HOME/swift-6.4.2`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit

因此下面能证明的是 HintLabeler 的先失败、后通过，以及 Linux 上 `HintLabeler.swift` 的覆盖率。不能证明标签会画出来，也不能证明点下去。那是任务 10。macOS 上的同一组测试和覆盖率交给 GitHub Actions。本文写完时，那次 CI 还没有结果；PR 说明里的检查状态才是实际结果。

## 范围

只加了 `SupervimCore` 里的 `HintLabeler`。没有 Overlay，没有 AXScanner，没有 Actuator，也没有改 ModeMachine 或 KeyParser。`Sources/SupervimCore` 仍然不导入 AppKit 或其他系统界面、事件框架；原有的边界测试在通过的那一轮里仍然通过。

`f` 和 `F` 共用这一套标签。点击是普通点击还是 Command 点击，仍由 `HintClick` 记住。Esc 不进这个类型。ModeMachine 已经在 Hint 里用 Esc 结束标签。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 05:20:55 UTC 到 05:20:59 UTC。命令：`swift test --filter HintLabelerTests`。当时还没有 `HintLabeler.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/HintLabelerTests.swift:453:16: error: cannot find type 'HintLabeler' in scope
Tests/SupervimCoreTests/HintLabelerTests.swift:472:16: error: cannot find type 'HintLabeler' in scope
Tests/SupervimCoreTests/HintLabelerTests.swift:519:19: error: cannot find type 'HintLabelResult' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：任何元素个数都得到空标签；`handle` 对字符永远返回 `noMatch`，对退格永远返回空的 `pending`。空实现不是最终行为。

空实现的第一次运行在 05:21:48 UTC 崩溃了，退出码 1。两个测试在标签还是空数组时直接取了下标，进程收到信号 4（`Index out of range`）。这是测试写错，不是实现的断言失败。随即改成先断言标签内容，再使用下标。断言的期望值没有放宽。

## 第二次运行：断言失败（RED）

时间：2026-11-17 05:22:15 UTC 到 05:22:17 UTC。命令：`swift test --filter HintLabelerTests`。退出码 1。

```text
Test Suite 'HintLabelerTests' failed at 2026-11-17 05:22:17.803
	 Executed 41 tests, with 96 failures (0 unexpected) in 0.411 (0.411) seconds
```

41 个测试里 35 个失败，96 次断言失败。失败原因是空实现不分配标签、也不按前缀过滤，不是拼写错误。代表输出：

```text
testOneElementUsesTheSingleLetterA : XCTAssertEqual failed: ("[]") is not equal to ("[SupervimCore.HintLabel(index: 0, text: "a")]")
testTenElementsIntroduceTwoCharacterLabels : XCTAssertEqual failed: ("[]") is not equal to ("["aa", "d", "f", "g", "h", "j", "k", "l", "s", "as"]")
testPartialPrefixListsMatchesWithoutSelecting : XCTAssertEqual failed: ("noMatch") is not equal to ("pending(... typed: "a" ... "aa", "as" ...)")
testTypingASingleLetterSelectsThatElement : XCTUnwrap failed: expected non-nil value of type "HintLabel"
testUniquePartialPrefixDoesNotSelect : XCTAssertEqual failed: ("noMatch") is not equal to ("pending(... typed: "a" ... index: 7, text: "ab" ...)")
testNoMatchLeavesTheTypedPrefixUntouched : XCTAssertEqual failed: ("") is not equal to ("a")
```

有六个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testAlphabetIsTheHomeRowInVimiumOrder`：空实现把字母表常量写成了 `asdfghjkl`
- `testZeroElementsYieldNoLabels` 和 `testNegativeElementCountYieldsNoLabels`：空实现本来就返回空数组
- `testZeroLabelsStartUnselectedAndAnyCharacterIsNoMatch`：没有标签时，任意字符本来就是 `noMatch`
- `testBackspaceOnZeroLabelsStaysPendingAndEmpty`：空实现的退格本来就返回空的 `pending`
- `testPrefixFreeHelperRejectsALabelThatPrefixesAnother`：只检查测试里的前缀判断，不调用标签分配

真正先失败的是非空集合的标签、前缀过滤、大小写、退格和选中下标。实现之后这六个本来就通过的测试仍然通过，它们单独不能证明分配是对的。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 05:22:58 UTC 到 05:23:01 UTC。命令：`swift test --filter HintLabelerTests`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'HintLabelerTests' passed at 2026-11-17 05:23:01.912
	 Executed 41 tests, with 0 failures (0 unexpected) in 0.448 (0.448) seconds
```

这一轮还没有把任务 4 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 05:23:51 UTC 到 05:23:56 UTC。命令：`scripts/hint-labeler-coverage.sh`。退出码 0。

脚本里面会再跑一次 `swift test --enable-code-coverage`。`MenuBarPreflightTests` 5 个、`SupervimCoreTests` 157 个（含 `HintLabelerTests` 41 个、`KeyParserTests` 36 个、`ModeMachineTests` 61 个、`MenuBarManifestTests` 18 个，以及已经改成任务 4 `done` 的 `TaskGraphTests`）全部通过，0 失败。合计 162 个 XCTest。Swift Testing 库另外报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。构建日志里没有编译警告。

同一轮 llvm-cov 对 `Sources/SupervimCore/HintLabeler.swift` 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
HintLabeler.swift line coverage: 100.00% (87/87)
HintLabeler.swift region coverage: 100.00% (37/37)
HintLabeler.swift function coverage: 100.00% (16/16)
```

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。写本文时 CI 还没有跑完。

## 给任务 10 用的值

全是值类型。复制一份再输入，不会改到原来那份。

| 入口 | 作用 |
| --- | --- |
| `HintLabeler(elementCount:)` | 按元素顺序分配标签。下标是 `0..<N`。`N <= 0` 得到空数组 |
| `HintLabeler(labels:)` | 沿用调用方的下标和顺序，把文本收成小写 |
| `label.text` / `label.displayText` | 存储用小写，浮层用大写 |
| `HintLabeler.filter(labels:typed:)` | 纯函数。返回仍匹配的标签，以及是不是恰好有一个标签被完整打完 |
| `handle(.character)` | 追加一个字符。匹配则 `pending` 或 `selected`；没有标签以它为前缀则 `noMatch`，已输入的前缀不变 |
| `handle(.backspace)` | 删掉最后一个已输入字符。空前缀上再退格，保持全部标签，不表示取消 |

`selected` 里的 `selectedIndex` 是元素下标，不是排序后的名次。`pending` 的 `matches` 按标签原来的顺序，供浮层隐藏其余标签。`noMatch` 表示规格里的无效输入，调用方取消 Hint。本类型不调用 `hintCancelled`。

## 分配结果

字符表固定为 `asdfghjkl`。算法与 Vimium 的 `AlphabetHints.hintStrings` 相同：从空串做广度扩展，每次把字符加到前面；取到足够的叶子后排序，再把每个字符串倒过来。倒过来是为了把同一个首字符散开。

| N | 标签 |
| --- | --- |
| 0 | 空 |
| 1 | `a` |
| 2 | `a` `s` |
| 9 | `a` `d` `f` `g` `h` `j` `k` `l` `s`，全部一个字符 |
| 10 | `aa` `d` `f` `g` `h` `j` `k` `l` `s` `as` |
| 81 | 81 个两字符标签 |
| 82 | 80 个两字符，2 个三字符 |
| 729 | 729 个三字符标签 |
| 730 | 728 个三字符，2 个四字符 |
| 5000 | 195 个三字符，4805 个四字符 |

同一 N 两次调用的结果相同。任意一个标签都不是另一个的前缀，字符都来自 `asdfghjkl`，并且互不相同。

`N <= 9` 时全是单字符，但不是按 `asdfghjkl` 的书写顺序原样截取。先按生成顺序取前 N 个（`a s d f g h j k l`），再排序。所以 3 个元素是 `a d s`，9 个元素是上面那一行。

## 过滤

比较不区分大小写，记下来的前缀是小写。

- 还没输入时，全部标签都匹配，不选中。
- 打完一个标签，并且没有任何别的标签仍以这段文字为前缀时，`selected` 带上那个元素下标。
- 只打到某个更长标签的真前缀时，即使目前只剩下一个标签，也不选中。要等标签打完。
- 字符对不上任何剩余标签时返回 `noMatch`，已输入的前缀保持原样。
- 退格回到上一个前缀。从 `as` 退回 `a` 时，`aa` 和 `as` 重新一起出现。
- 在空前缀上退格不改变状态，也不返回 `noMatch`。

## 交给所有者看的决定

规格没有把这些岔路写死。分配算法按 Vimium 的字母标签。过滤按规格第 1 条：打完标签就选中，无效输入交给调用方取消。没有改规格正文。

1. **标签顺序用 Vimium 的「扩展、排序、再倒转每个字符串」。** 单字符不是 `asdfghjkl` 从左到右的前 N 个。`N = 9` 的顺序是 `a d f g h j k l s`。这是 Vimium 为了把相同首字符散开，不是另写的一套。
2. **只有完整且不再有歧义的标签才选中。** 规格写的是键入标签后点击。某个更长标签的唯一真前缀先不选。Vimium 的字母模式会在「只剩一个标签」时立刻激活；用本算法生成的标签里，这种情况和「标签已经打完」是同一时刻，因为每个被展开的节点至少贡献两个子标签。调用方如果塞进一组不是前缀安全的自定义标签，唯一真前缀会继续等。
3. **一个标签如果还是另一个标签的前缀，打完它也不选中。** 生成结果不会这样。自定义标签若破坏前缀安全，就保持 `pending`，直到只剩一个完全相等的标签。
4. **对不上的字符是 `noMatch`，不改已输入的前缀。** 规格第 1 条把无效输入当作取消，不是忽略。取消本身留给后面的模式机，和任务说明一致。本类型不吞掉这个字符，也不把它记进前缀。
5. **空前缀上的退格不取消。** Vimium 会在退格队列为空时退出标签模式。规格的取消条件只有 Esc 和无效输入，没有退格。空退格返回原来的 `pending`。任务 10 如果要跟 Vimium 一样，可以在 `typed` 已经为空时自己取消。这是相对 Vimium 的偏离。
6. **Esc 不是这里的输入。** ModeMachine 已经处理 Hint 里的 Esc。
7. **`f` 和 `F` 共用标签。** Command 点击仍是 `HintClick.command`，不在标签器里分支。
8. **字母表不可配置。** 规格写死 `asdfghjkl`。初始范围没有自定义按键。
9. **不做 Vimium 的文字过滤模式。** 只按标签前缀收窄，不按链接文字收窄。
10. **`N <= 0` 得到空标签，不触发陷阱。** 文档没有写负数。0 是规格里的空集合。
11. **生成标签的下标就是元素顺序 `0..<N`。** `init(labels:)` 保留调用方的下标，过滤也不按下标重排。
12. **静态 `filter` 不改写调用方的标签文本。** 只有会话初始化会把文本收成小写。大小写不敏感的比较在过滤时做。

## 没有测的东西

- 没有在 macOS 上编译或运行
- 没有辅助功能树、点击、Command 点击或浮层
- 没有测量 `f` 的 200ms，也没有测量按钮和链接覆盖率
- 没有把 `noMatch` 接到 `hintCancelled`，也没有把 `selected` 接到真正的点击
