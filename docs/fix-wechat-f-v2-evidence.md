# 微信里按 f 仍然没有任何画面

记录日期：2026-11-17。Linux，Ubuntu 24.04，Swift 6.2.1。`AXApplicationReader.swift` 和 `CGEventTapSession.swift` 在这里不编译。没有微信，也没有 Mac。

v0.1.2（#18）之后，别的应用里 `f` 能出标签，微信里按 `f` 什么都没有。#18 只处理了两件事：带 `AXPress` 的容器算可点，以及扫描结果是 0 时立刻写 `AXManualAccessibility`（失败才写 `AXEnhancedUserInterface`）并再读一次。这次按代码把 `f` 从事件钩子走到标签的每一步都对过，不把原因收成「树是空的」这一条。

## 代码里能走到「什么都没有」的路径

1. **事件钩子根本没看到这个键。** 钩子是 `cgSessionEventTap`、插在最前、可以吞键。系统在安全输入（`EnableSecureEventInput`）打开时会发 `tapDisabledByUserInput`，然后不再把按键交给钩子。回调里会把钩子重新打开，但安全输入还在的时候，后面的键仍然到不了 Supervim。微信的一些版本在前台时会打开安全输入。别的应用正常、只有微信没反应，和这条相容。安全输入打开时，字符进不进输入框取决于微信自己，不一定能在画面上看到 `f`。
2. **人还在 Insert，`f` 被放过。** 焦点停在可编辑的聊天框上时，`f` 不会进标签流程。#17 用元素身份把 Esc 之后的 Normal 按住。身份来自 `CFEqual`。微信如果每次 `AXFocusedUIElement` 都给出一个 `CFEqual` 对不上的新对象，下一次焦点通知或者下一次按键会清掉这段保持，模式回到 Insert，解析器看不到 `f`。这时 `f` 会被打进输入框。用户如果只盯着有没有标签，也会说成「没有反应」。
3. **窗口没被读到。** 原来只读 `AXFocusedWindow`，没有再读 `AXMainWindow`，再没有就放弃。`AXWindows` 没人读。Qt 经常让 focused 是空的，真正的窗口只在 `AXWindows` 里，或者子节点挂在应用元素上，窗口角色也不是标准的 `AXWindow`。读失败时查询是 `unavailable`，标签流程马上取消。
4. **属性写上了，树还是空的。** 空结果会写 `AXManualAccessibility`。写入返回成功之后，这个进程再也不会写 `AXEnhancedUserInterface`。微信这种 Qt 界面常常要 enhanced，而且树要过一小段时间才长出来。原来的第二次读取是立刻发生的，等不到。另外，扫描只发生在焦点变化时；`f` 用的是那份缓存。焦点变化时树是空的，缓存就一直空，再按 `f` 也不会再扫。
5. **横幅有，但只有状态栏那两个字。** 空结果会把状态栏改成「没找到可点击元素」，大约 2 秒后回到 Normal。Hint 不单独占一个状态。人如果没看菜单栏，就觉得按键没触发。

深度上限和「元素在窗口外面」都不是这次「完全没画面」的原因。那些情况至少会扫到节点；完全没画面是键没进来、被放过，或者扫描被当成 0 个目标立刻取消。

## 先失败

`testEscapedComposerStaysNormalWhenWeChatReissuesTheElement`：Esc 之后同一块 `AXTextArea` 换成新身份 `ax-2`，框还重叠。期望留在 Normal，`f` 进入标签。实际模式是 `insert`，`f` 的投递是 `passThrough`，没有 `beginHint`。

`testHintEntryRescansWhenTheCachedSnapshotIsEmpty`：缓存是空的，扫描器里已经有一个按钮。期望 `f` 再读一次并出标签。实际读数仍是 1，结果是 `cancelled(noTargets)`。

`testOneTargetUsesTheEasiestLetter`、`testAlphabetPlusOneKeepsSingleLettersAndTwoDoubles`：期望 1 个目标是 `f`，字母表用完再加 1 个时单字母排在前面。实际 1 个目标是 `a`，10 个目标的开头是 `aa`。

## 修法

- Esc 按住的不再只是那一枚 `CFEqual` 令牌。同一个 bundle、同一个 role 和 subrole，框重叠（较小的那块至少盖住一半）或者其中一次没有框，都还算同一个输入框。换了 role，或者框对不上，才回到 Insert。点进当前焦点的框里仍然回到 Insert。
- `f` 发现缓存里没有可用目标时再扫一次。有目标的缓存不动，避免每次 `f` 都走树。
- 扫描按 focused、main、`AXWindows`（最多 8 个）的顺序，用第一棵有命中的树。这些都空，再读应用元素自己。窗口角色不限。
- 命中是 0 时先写 `AXManualAccessibility`。写成功就等 120ms 再读。还是 0 才写 `AXEnhancedUserInterface`，再等 120ms。手动写入成功不再阻止 enhanced。两个属性每个进程各写一次。测试里的等待是记录下来的，不真睡；菜单栏进程装的是 `AccessibilityTreeSleeper`。
- 标签改成单字母优先、前缀自由。默认字母表是 `fjdkslaghrueiwotypqvbncmxz`：先主行 `fjdkslagh`，再上行 `rueiwotypq`，再下行 `vbncmxz`。规格第 1 条写的是 `asdfghjkl`。这里加长，是为了目标一多还有单字母可用。`HintLabeler.init(elementCount:alphabet:)` 和 `HintSession` 的 `alphabet` 可以换一套。设置文档里没有这项，没有新增要存盘的字段。
- 字母表有 N 个字、目标不超过 N 时，全是单字母，按好按的顺序。目标是 N+1 时，留下 N−1 个单字母，只再做 2 个双字母，前缀是最难的那个字。再多也先把最长长度压到够用，再在这个长度里尽量多留单字母。没有任何一条标签是另一条的前缀。
- 最好按的标签分给最可能被点的目标。角色从高到低：按钮一类、链接、标签页、菜单项、文本框、其余（组、静态文本、图像）。短边小于 8 的排在所有正常大小的后面。给了窗口框时，完全落在窗口外的丢掉；全都在外面就都留下。同一档里，离窗口中心（没有窗口框就用这些框的并集中心）更近的优先，再比离指针的距离、面积，最后用原来的序号。顺序是确定的。

## 调试日志

开关和 #17 相同：`SUPERVIM_LOG=1`，或 `defaults write com.lijigang.supervim SupervimDebugLog -bool true`。文件是 `~/Library/Logs/Supervim.log`。

按一次 `f` 或 `F`，至少有一行 `hint-key`。钩子没看到这个键时，没有这一行。

```text
hint-key key=f mode=hint why=held-normal delivery=swallow bundle=com.tencent.xinWeChat role=AXTextArea subrole=- identity=ax-2 held=kept
hint-key key=f mode=insert why=editable-focus delivery=passThrough bundle=com.tencent.xinWeChat role=AXTextArea subrole=- identity=ax-9 held=cleared
hint-window source=focused found=0 children=0
hint-window source=main found=1 children=0
hint-window source=windows found=1 children=40
hint-window source=application found=1 children=12
hint-scan bundle=com.tencent.xinWeChat window=windows found=1 visited=800 hits=15 ms=140 expansion=manual+enhanced retry=hits
hint-banner reason=noTargets
tap-disabled reason=userInput reenabled=1
```

| 行 | 含义 |
| --- | --- |
| `hint-key` | 钩子看到了 `f` 或 `F`。`mode` 是处理之后的模式。`why=held-normal` 是 Esc 按住的输入框上进入了标签。`why=normal` 是本来就不可编辑。`why=editable-focus` 是被当成新的输入框，键被放过。`why=unknown-focus` 是焦点不明，按宪法放过。`why=excluded` 是排除列表。`why=paused` 是暂停。`why=hint` 是已经在标签里。`held=kept` 是新令牌仍算同一个框。`held=cleared` 是保持被清掉。`held=unnamed` 是这次没读到身份。`held=none` 是没有保持 |
| `hint-window` | 这一次尝试的窗口。`found=0` 是这个属性没有。`children` 是直接子节点数，不是命中数。`source` 是 `focused`、`main`、`windows`、`application` 或 `none` |
| `hint-scan` | 最终采用的那棵树。`window` 是上面的 source。`visited` 是走过的节点。`hits` 是可点的个数。`expansion` 是 `none`、`manual`、`enhanced` 或 `manual+enhanced`。`retry=none` 是没有等。`retry=empty` 是等了还是 0。`retry=hits` 是等完有了目标 |
| `hint-banner` | 扫描结束仍然没有目标。`reason=noTargets` 是窗口在但没有可点元素。`reason=unavailable` 是窗口没读到 |
| `tap-disabled` | 系统关掉了事件钩子。`reason=userInput` 是安全输入。`reason=timeout` 是钩子超时。`reenabled=1` 是回调里又打开了。这条如果紧挨着一次 `f`，而没有对应的 `hint-key`，就是钩子没看见那个键 |

还在的旧行：`hint-screen`、`hint-label`、`hint-click`，以及模式变化的 `insert -> normal`。

如果这版在微信里还是没有标签，把按 `f` 前后这几行原样发回来：所有 `hint-key`、`hint-window`、`hint-scan`、`hint-banner`、`tap-disabled`，以及 Esc 附近带 `trigger=` 的模式行。

## 通过

`swift test` 退出码 0。Linux 执行 638 个测试，0 失败。`testModifierMasksMatchCoreGraphics` 只在 macOS 上跑，所以 macOS 会多 1 个。

这次新增或改写后用来卡住行为的测试：

| 测试 | 证明的事 |
| --- | --- |
| `testEscapedComposerStaysNormalWhenWeChatReissuesTheElement` | 新身份但同一 role、框重叠时，`f` 进入标签。没有框的再读也按住。点进框里回到 Insert。搜索框那种不同 role 回到 Insert |
| `testHintEntryRescansWhenTheCachedSnapshotIsEmpty` | 缓存为空时 `f` 再扫一次 |
| `testEmptyFocusedWindowUsesAnotherWindowWithoutWaiting` | focused 是空的，命中来自 `windows`，不写属性 |
| `testPopulationDelayRereadsAfterManualAccessibility` | 写了 manual 之后等 120ms，第二次读到按钮，不再写 enhanced |
| `testEnhancedIsTriedWhenTheTreeIsStillEmptyAfterManual` | manual 之后仍为空，再写 enhanced，再等一次 |
| `testApplicationTreeIsUsedWhenEveryWindowAttributeIsMissing` | 三个窗口属性都没有时用应用元素 |
| `testOneTargetUsesTheEasiestLetter` 到 `testCustomAlphabetMaximizesSinglesForOneSizeAndSizePlusOne` | 1 个、整表、整表加 1、100、700；前缀自由；单字母尽量多 |
| `HintRankingTests` | 角色顺序、中心和面积、指针、过小靠后、屏幕外丢掉、序号打破平局 |

## 这里没有验证的事

- 没有在真机的微信里按 `f`
- 没有看到菜单栏或标签层
- 没有确认微信是否打开了安全输入，也没有确认它的 `AXFocusedUIElement` 是否每次都 `CFEqual` 失败
- 没有确认微信的窗口在 `AXFocusedWindow`、`AXMainWindow`、`AXWindows` 还是应用元素上，也没有确认写完属性要多久树才出现
- 120ms 是固定等待，不是等到树出现为止。真机若更慢，日志里会是 `retry=empty`，需要再加长
- 缓存里已经有别的应用的目标时，`f` 不会重扫。切到微信却没有焦点通知时，标签可能还是上一份
