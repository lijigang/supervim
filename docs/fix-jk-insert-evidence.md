# j/k 被送回 Insert 的根因和修复记录

记录日期：2026-11-17。这台机器是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.2.1（swift-6.2.1-RELEASE），官方 Ubuntu 24.04 工具链，解在 `~/swift`
- `AXApplicationReader.swift` 和 `CGEventTapSession.swift` 整文件包在 `canImport(ApplicationServices)` / `os(macOS)` 里。Linux 上这两个 `.o` 都是空壳（各 3912 字节），里面的 `CFEqual`、`CGEvent` 鼠标掩码没有在这里编译

因此下面能证明的是：用伪造的焦点元素和滚动区域，先看到失败，再看到同一组断言通过。不能证明微信或 Grok 的辅助功能树真的长什么样，也不能证明滚轮在真机上滚的是聊天记录。macOS 编译和测试交给 GitHub Actions。

## 根因

用户的操作是：微信或 Grok（Electron）里，光标一直在底部输入框。按 Esc，状态回到 Normal，再按 `k`，状态又变成 Insert，`k` 被打进输入框。期望是聊天记录向上滚。

这不是 `j` / `k` 被解析成「进入 Insert」，也不是 `AXWebArea` 被判成输入框。

`KeyParser` 里 `j` 是 `scrollDown`，`k` 是 `scrollUp`。`i` 才是 `manualInsert`。失败测试里，`k` 的 `actions` 是空的，投递是 `passThrough`，因为解析器根本没被调用。

`FocusClassification.editability`（`Sources/SupervimSystem/AXScanner.swift`）里，`AXWebArea`、`AXScrollArea`、`AXGroup`、`AXWindow`、`AXApplication` 在 `AXEditable` 缺失或为 false 时已经是 `notEditable`。只读文本角色且 `AXEditable == false` 是 `unknown`，不会进 Insert。微信输入框本身就是可编辑的 `AXTextArea`，分类是对的。

真正的路径是：Esc 只改了模式机，没有改「当前焦点仍可编辑」这个事实。下一次按键，以及下一次 `AXFocusedUIElementChanged`，都会把同一份缓存再送进去。

1. `EventInterpreter.handleKeyDown` 在看键之前先 `apply(cache)`（`Sources/SupervimCore/EventInterpreter.swift`，约第 181 行）。
2. `apply` 调用 `machine.handle(.focus(editability))`（同文件，约第 307 行）。
3. 缓存仍是 `.editable` 时，`ModeMachine.handleFocus` 走 `.editable`，调用 `enterAutomaticInsert()`（`Sources/SupervimCore/ModeMachine.swift` 第 162–163 行和第 270–277 行），模式变回 Insert。
4. 模式已经是 Insert，`k` 走 `decisionWithoutParser`，原样放过。事件钩子不吞这个键，所以字符进了输入框。滚动执行器不会被调用，测试里 `poster.effects` 是空的。
5. 焦点通知走 `AXScanner.noteFocusChanged()` → `publishCachedFocus()` → `updateCache`，同样的 `apply`。Esc 之后通知一到，菜单就先回到 Insert，还没轮到 `k`。

模式机在 Esc 时会把内部焦点改成 `unknown`，并要求 `blurFocus`（`ModeMachine.swift` 第 127–134 行）。但解释器保存的 `CachedFocus` 仍是那个可编辑输入框。下一次 `apply` 用的是缓存，不是模式机内部那份。Electron 聊天框的 Esc 也不会真的把辅助功能焦点移走，所以缓存一直可编辑。

没有单独的焦点轮询定时器。会重新判定的地方是：启动时的第一次读取、`AXFocusedUIElementChanged` / 焦点窗口变化 / 应用激活，以及每一次按键对缓存的套用。

旧测试 `testEscapeFromAutomaticInsertPassesKeysWhileTheFieldStillLooksEditable` 把「缓存仍可编辑就回到 Insert 并放过下一键」锁成了期望。那条路径没有元素身份。没有身份时仍保持旧行为，避免把一个分不清是不是同一个控件的字段当成可以吞键的普通模式。真机读取一旦拿到元素，就会带上身份。

## 先失败的测试

命令：

```bash
swift test --filter 'testEscapedComposerStaysNormalUntilFocusEntersANewInput|testNormalKWheelsTheChatHistoryInsteadOfTheComposer|testNormalKIsNotDeliveredToTheComposer'
```

时间：2026-11-17 11:10:14 UTC。退出码 1。14 个断言失败，0 个意外错误。当时 `acceptPointerClick` 是空实现，元素身份还没有写进缓存，滚动仍走旧的指针/焦点链。

`AXScannerTests.testEscapedComposerStaysNormalUntilFocusEntersANewInput`：

```text
AXScannerTests.swift:57: XCTAssertEqual failed: ("insert") is not equal to ("normal")
AXScannerTests.swift:59: XCTAssertEqual failed: ("insert") is not equal to ("normal")
AXScannerTests.swift:60: XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
AXScannerTests.swift:61: XCTAssertEqual failed: ("[]") is not equal to ("[...scroll(...up, ...points(60))]")
AXScannerTests.swift:73: XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
AXScannerTests.swift:84: XCTAssertEqual failed: ("normal") is not equal to ("insert")
```

第 57 行是 Esc 之后、同一 `identity: "composer"` 的焦点通知。模式从 Normal 被送回 Insert。第 59–61 行是随后的 `k`：模式 Insert，键被放过，没有向上滚动。第 73 行是 `i`：因为已经自动回到 Insert，`i` 被当成文字放过，而不是手动进入 Insert 的吞键。第 84 行是点进输入框：空实现没有切回 Insert。

`NormalCommandSessionTests.testNormalKWheelsTheChatHistoryInsteadOfTheComposer`：

```text
XCTAssertEqual failed: ("insert") is not equal to ("normal")
XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
failed - expected a wheel event, got []
```

指针在输入框上（`(400, 560)`），旁边有更大的 `AXScrollArea`（聊天记录，`(0, 0, 800×500)`）。修复前没有滚轮事件。

`NormalCommandSessionTests.testNormalKIsNotDeliveredToTheComposer`：

```text
XCTAssertEqual failed: ("insert") is not equal to ("normal")
XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
XCTAssertFalse failed
XCTAssertEqual failed: ("insert") is not equal to ("normal")
XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
```

有滚动目标时 `k` 被放过，执行器没有收到滚轮。没有滚动区域时同样被放过。事件钩子看到 `passThrough` 就会把 `k` 交给输入框。

## 修复

Esc 离开 Insert 时，如果缓存里有元素身份，记在 `heldNormalIdentity`（`EventInterpreter.decided`，约第 421 行）。之后：

- 同一身份，或读失败、身份缺失：模式机看到的是 `notEditable`，留在 Normal，`k` 当滚动命令并吞掉。
- 身份换成另一个可编辑元素：清掉这段保持，自动进入 Insert。
- `i`：这段保持还在，所以 `i` 会进到解析器，手动进入 Insert，并吞掉 `i`。
- 点击落在这个元素的框内：清掉保持，再按可编辑焦点进入 Insert。点击框外（聊天记录）不改变模式，点击本身仍然放过。
- `gi` 聚焦成功后调用 `releaseHeldInput()`，随后的焦点读取仍可进入 Insert。

身份由 `AXSystemReader` 用 `CFEqual` 分配（`FocusIdentityVault`）。同一个辅助功能元素再次读到时令牌不变。读不到元素时身份是 nil，可编辑性是 `unknown`。在已经按过 Esc 的保持期间，这种读失败不会被当成「进入了一个新输入框」。没有保持时，未知焦点仍按宪法放过按键。

Normal 下如果焦点缓存仍是那个带身份的可编辑输入框，滚动不再用「指针下最深的区域，否则焦点所在区域」：

- 排除和输入框差不多大、并且压在输入框上的区域，以及标了 `isTextInput` 的区域。
- 优先选指针下面的 `AXScrollArea` 或 `AXWebArea`（更深的优先）。
- 否则选还能朝该方向移动的最大区域。
- 滚轮位置用该区域中心，走现有的 `pointerScroll` → `CGEvent` `scrollWheelEvent2`，`event.location` 设在这个中心。
- 没有可用区域时仍然吞掉滚动键，不把 `k` 交回输入框。普通的不可编辑页面（没有这段保持）仍是旧规则：没有目标就放过。

没有滚动条的 `AXWebArea` / `AXScrollArea` 记在目录的 `structural` 里，不进原来的 `areas`，所以「没有滚动条就不算目标」的旧测试不变。只有按住这段 Normal 时才会用它们发滚轮。Electron 的聊天列表经常没有 `AXScrollBar`。

## 修复之后

同一条过滤命令，退出码 0。随后 `swift test` 退出码 0。

```text
Test Suite 'debug.xctest' passed
Executed 605 tests, with 0 failures (0 unexpected) in 4.466 seconds
```

605 是 Linux 上实际执行的数量。`EventTapTests.testModifierMasksMatchCoreGraphics` 包在 `#if os(macOS)` 里，这里不会跑。macOS 上会多这 1 个。本次新增 8 个测试，都在这 605 里面：

| 测试 | 证明的事 |
| --- | --- |
| `testEscapedComposerStaysNormalUntilFocusEntersANewInput` | Esc 后同一身份的焦点通知和 `k` 留在 Normal；`k` 是向上滚动并吞键。换到 `AXWebArea` 仍是 Normal。换到另一个可编辑身份进入 Insert。`i` 吞键进入 Insert。点在框外留在 Normal，点进输入框进入 Insert |
| `testNormalKWheelsTheChatHistoryInsteadOfTheComposer` | 指针在输入框上时，滚轮目标是 `history`，位置是该区域中心 `(400, 250)`，垂直增量为正 |
| `testNormalKIsNotDeliveredToTheComposer` | 有目标时 `k` 被吞且有滚轮；没有目标时 `k` 仍被吞，执行器不发事件 |
| `testHeldNormalKWheelsABarlessWebAreaFromTheStructuralList` | 没有滚动条的 `AXWebArea` 也能成为滚轮目标 |
| `testContentScrollSkipsTheInputAndAimsTheWheelAtTheChosenCenter` | 指针下更深的 `AXWebArea` 优先；输入框被排除后用最大区域；大的父区域不因为包住光标就被排除；四个方向的行程；面积相同时标识更小的优先 |
| `testWebAreaWithoutAScrollBarIsAStructuralWheelTarget` | 结构目标不混进原来的 `areas` |
| `testPointerPressIsPassedThroughAndCanReenterInsert` | 鼠标按下不扫树、不吞点击；框内点击把模式改回 Insert |
| `testModeTraceLineNamesTheFocusAndTheTrigger` | 日志行含触发键、role、subrole、身份 |

`testEscapeFromAutomaticInsertPassesKeysWhileTheFieldStillLooksEditable` 仍然通过：那份缓存没有 `elementIdentity`，Esc 之后下一键仍会回到 Insert。生产路径的焦点读取会填身份。

## 调试日志

默认关闭。打开任一处即可：

```bash
SUPERVIM_LOG=1
```

或：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool true
```

模式真正发生变化时，往 `~/Library/Logs/Supervim.log` 追加一行，例如：

```text
2026-11-17T11:00:00Z insert -> normal trigger=escape role=AXTextArea subrole=- identity=composer
```

`trigger` 是按键字符、`escape`、`focus`（焦点通知）、`click`、`pause`、`resume` 或 `hint-end`。同一元素被按住不切模式时不写行。如果真机上 Esc 之后立刻又出现 `trigger=focus` 或 `trigger=k` 且右边是 `insert`，把这行发回来：身份如果每次通知都变（`ax-1`、`ax-2`），说明 `CFEqual` 没有把 Electron 的两次读取认成同一个元素。

关掉：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool false
```

环境变量不设 `SUPERVIM_LOG` 即可。标准域和套件 `com.lijigang.supervim` 都会读这个布尔值。

## 这里没有验证的事

- 没有在微信或 Grok 里按 `k`
- 没有看到菜单栏文字从 Insert 变成 Normal
- 没有确认 Electron 的 `CFEqual` 对两次 `AXUIElementCopyAttributeValue` 返回真
- 没有确认聊天记录在辅助功能树里是 `AXScrollArea` 还是没有滚动条的 `AXWebArea`，也没有确认它的框比输入框大
- macOS 上 `CGEventTap` 是否收到 `leftMouseDown`，以及滚轮 `location` 是否和辅助功能框同一套坐标，都还没在真机上看过。现有代码本来就不翻转坐标
