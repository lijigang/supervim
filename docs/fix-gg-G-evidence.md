# 浏览器里 `gg` / `G` 不到顶、不到底

记录日期：2026-11-17。这台机器是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.2.1（swift-6.2.1-RELEASE），官方 Ubuntu 24.04 工具链
- 基线：`6652525`（PR #20 合并之后的 `main`）
- 没有改签名、打包脚本或 release workflow

`AXApplicationReader.swift`、`CGEventActuator.swift` 和 `MacHookAssembly.swift` 整段包在 `canImport(ApplicationServices)` 或 `os(macOS)` 里。Linux 上能证明的是：用伪造的滚动区域和滚动条，先看到 `gg` / `G` 只计划一次 `focusScroll`（像素为 0），再看到同一组断言改成滚轮或写上滚动条。不能证明 Safari、Chrome、Arc 或 Electron 的辅助功能树真的长什么样，也不能证明滚轮落在页面中心时页面真的到了顶或底。

## 根因

置信度：高。失败测试直接打出了计划里的效果。真机上的页面有没有滚动，还没看过。

用户的操作是：浏览器里 `j` / `k` 能上下滚，`gg` 不到顶，`G` 不到底。

这不是按键没被解析。

- `KeyParser` 里单独的 `G` 是 `scrollToBottom`。`g` 等第二键，凑成 `gg` 才是 `scrollToTop`。前缀超时仍是 1000 毫秒。Shift 不挡普通绑定，挡的是 Control、Option、Command。
- 事件钩子在只有 Shift 时保留系统给出的 Unicode。键码 `0x05`、Unicode `"G"`、Shift 标志，翻译成 `KeyEvent("G", modifiers: .shift)`，决定是向下到边。两下没有修饰键的 `g` 决定是向上到边。这条测试在修复前就是通过的。
- 空 Unicode 再加 Shift 仍会落到未移位的 `g`，从而开始等第二键。这次没有改这条，因为 `gg` 和 `G` 一起失败，空 Unicode 解释不了 `gg`。

`j` / `k` 和 `gg` / `G` 选的是同一块区域（指针下能移动的区域，否则焦点所在的区域；按住输入框时仍是 `ContentScroll` 选的那块）。差别在数量：

- `j` / `k` 是 60 点滚轮，位置在指针上（按住输入框时在区域中心）。浏览器吃滚轮。
- `d` / `u` 在指针下是可见高度的一半，也是滚轮。可见高度为 0 时半页仍然放过，这是原来的 `testZeroVisibleFractionSkipsTheArea`，不是这次的故障。
- `gg` / `G` 是 `.edge`。修复前 `ScrollHitRule` 把它做成 `focusScroll`，像素 0，`scrollRange` 空。poster 只调用 `scrollBarToEdge`，也就是对竖向 `AXScrollBar` 写 `AXValue`。

失败测试里的效果是：

```text
focusScroll(targetID: "page", direction: .down, amount: .edge, pixels: 0, scrollRange: nil)
```

目标标识是对的（普通页面是 `page`，按住输入框时是 `history`），但是没有滚轮。

写滚动条这一步在真机上还是空操作。`AXElementStore.bind` 以前没有任何调用者。窗口读取把 `AXUIElement` 拷成值之后就丢掉了，store 一直是空的。`scrollBarToEdge` 找不到元素就返回。执行器仍然报告「已执行」，所以键被吞掉，页面不动。

就算 store 里有元素，Safari、Chrome、Arc 和 Electron 的 `AXWebArea` 也经常忽略滚动条上的 `AXValue`。原生 `NSScrollView`（角色通常是 `AXScrollArea`）则可以写。所以不能改成「永远只发滚轮」或「永远只写值」。

## 先失败的测试

命令：

```bash
swift test --filter 'testWebAreaEdgeScrollWheelsTheSameTargetAtItsCenter|testGGOnAWebPageWheelsThePageCenter|testShiftGOnAWebPageWheelsTowardTheBottom|testHeldNormalGGWheelsTheHistoryCenter|testShiftGIsScrollToBottomAndPlainGGIsScrollToTop'
```

时间：2026-11-17 14:03:32 UTC。退出码 1。4 个断言失败，0 个意外错误。解析那一条通过。

`EventTapTests.testShiftGIsScrollToBottomAndPlainGGIsScrollToTop`：通过。Shift+`G` 是 `scrollToBottom`，`gg` 是 `scrollToTop`，扫描次数是 0。

`ActuatorTests.testWebAreaEdgeScrollWheelsTheSameTargetAtItsCenter`：

```text
ActuatorTests.swift:320: failed - gg/G must wheel the j/k target at its center, got [focusScroll(targetID: "page", direction: .down, amount: .edge, pixels: 0, scrollRange: nil)]
```

同一条测试里，`j` 的 60 点滚轮和 `d` 的半页滚轮在断言失败之前已经对上了，位置仍是指针 `(20, 30)`，不是中心。

`NormalCommandSessionTests`：

```text
testGGOnAWebPageWheelsThePageCenter: got [focusScroll(... direction: .up, amount: .edge, pixels: 0, scrollRange: nil)]
testShiftGOnAWebPageWheelsTowardTheBottom: got [focusScroll(... direction: .down, amount: .edge, pixels: 0, scrollRange: nil)]
testHeldNormalGGWheelsTheHistoryCenter: got [focusScroll(targetID: "history", direction: .up, amount: .edge, pixels: 0, scrollRange: nil)]
```

`gg` 的目标已经是 `history`，不是输入框。缺的是到边的做法，不是选区。

## 修复

到边仍用 `j` / `k` 的那块区域。滚轮改打在这块区域的中心，不打在指针上。`j` / `k` / `d` / `u` 的像素路径没有改。

`EdgeScroll` 的顺序：

1. 读该方向的滚动条。已经在那一端：不写、不滚，结果 `alreadyAtEdge`。
2. `AXValue` 可写（`AXUIElementIsAttributeSettable`）时，向上或向左写成最小值，向下或向右写成最大值。读回来的值停在那一端，才算 `scrollBarValue` / `atEdge`。写被拒绝，或读回来没到边，就改走滚轮。
3. 没有条、条不可用，或条不可写：在区域中心发滚轮。每下 `50_000` 像素，最多 `8` 下（`EdgeScroll.wheelPixels`、`unobservedBursts`）。不可写的条即使数值不动也打满，因为网页经常不更新这个值。数值读到了那一端就提前停。
4. 可写但没写住：继续滚，直到数值不再变、到了边，或满 `30` 下（`maxBursts`）。
5. 不发 Home、End、Command+方向键。效果里只有 `pointerScroll` 或一次 `scrollBarEdge`。

窗口刷新时，被选中的那棵树按 `ScrollTargetIdentity` 绑进同一个 `AXElementStore`。路径和目录一致：根是 `root`，子节点是 `0/2` 这种。`MenuHookAssembly` 把这份 store 同时交给读取器、poster 和 `ActionActuator.edgeBars`。`j` / `k` 不读它。

## 修复之后

`swift test` 退出码 0。

```text
Test Suite 'debug.xctest' passed
Executed 651 tests, with 0 failures (0 unexpected) in 6.28 seconds
```

651 是 Linux 上实际执行的数量。`EventTapTests.testModifierMasksMatchCoreGraphics` 包在 `#if os(macOS)` 里，这里不会跑。macOS 上会多这 1 个，一共 652。本次新增 10 个测试：

| 测试 | 证明的事 |
| --- | --- |
| `testShiftGIsScrollToBottomAndPlainGGIsScrollToTop` | Shift+`G` 和 `gg` 被解析并路由，不扫树 |
| `testWebAreaEdgeScrollWheelsTheSameTargetAtItsCenter` | `j` 仍是指针上的 60 点，`d` 仍是指针上的半页；`G` 对 `AXWebArea` 在区域中心发大滚轮，不是 `focusScroll`，也不是按键 |
| `testGGOnAWebPageWheelsThePageCenter` | 会话里 `gg` 吞键，滚轮在页面中心，方向向上 |
| `testShiftGOnAWebPageWheelsTowardTheBottom` | 系统记录的 Shift+`G` 在页面中心向下滚 |
| `testHeldNormalGGWheelsTheHistoryCenter` | 焦点还在输入框时，`gg` 滚的是 `history` 的中心 |
| `testEdgeScrollNamesAndLogLine` | 日志行含序列、命令、角色、目标和策略 |
| `testUnsettableWebBarWheelsUntilTheEdgeOrTheBurstEnds` | 不可写的条：读到边缘就停；数值不更新就打满 8 下 |
| `testSettableBarThatDoesNotStickWheelsUntilTheValueStops` | 可写但读不回来：改滚，数值停了或条消失了就停 |
| `testMissingOrUselessBarPostsABoundedCenterWheelAndNoKeys` | 没有条、NaN、已经在边缘。横向滚轮符号对。不写条 |
| `testSettableBarThatKeepsMovingStopsAtTheBurstCap` | 数值一直变但到不了边时停在 30 下 |

`testEdgeScrollSetsTheBarEvenWhenThePointerIsOverTheArea` 改成：指针在区域上时，可写并且读得回来的条仍写成 0 或 1，不发滚轮。

`Actuator.swift` 行覆盖率 98.09%（666/679）。`ScrollAreaCatalog.swift` 96.40%（250 行里 9 行没走到）。都高于 90% 的门。Linux 上的覆盖率脚本认不出 `SupervimPackageTests.xctest` 这个文件名，数字是用 `llvm-cov` 对同一份 profdata 算的。macOS CI 仍走仓库里的脚本。

## 调试日志

默认关闭。打开任一处即可：

```bash
SUPERVIM_LOG=1
```

或：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool true
```

`gg` 或 `G` 真正执行时，往 `~/Library/Logs/Supervim.log` 追加一行，例如：

```text
scroll-edge sequence=gg command=scrollToTop role=AXWebArea target=0/2 strategy=wheel result=unobserved
scroll-edge sequence=G command=scrollToBottom role=AXScrollArea target=root strategy=scrollBarValue result=atEdge
```

| 字段 | 含义 |
| --- | --- |
| `sequence` | `gg` 或 `G` |
| `command` | `scrollToTop` 或 `scrollToBottom` |
| `role` | 滚动目标的辅助功能角色，没有则是 `-` |
| `target` | 和 `j` / `k` 相同的区域标识 |
| `strategy` | `scrollBarValue` 表示写成了滚动条；`wheel` 表示发了滚轮 |
| `result` | `atEdge` 读到了那一端；`alreadyAtEdge` 本来就在；`moved` 可写的条动了但没到边；`unchanged` 可写的条滚了一下没动；`unobserved` 没有可用的条，或不可写的条一直没报边缘，此时发了 8 下各 50_000 像素 |

`j` / `k` / `d` / `u` 不写这行。

如果真机上还是不到顶或不到底，把按 `gg` 和 `G` 时新出现的 `scroll-edge` 行发回来。`strategy=scrollBarValue` 且 `result=atEdge` 但页面没动，说明网页把 `AXValue` 读成了已经到边，滚轮没有发出去。`result=unobserved` 而页面只移动了一截，说明 8 下不够长。`result=unchanged` 说明条可写、写不进去，滚轮也没让数值变化。

关掉：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool false
```

环境变量不设 `SUPERVIM_LOG` 即可。

## 这里没有验证的事

- 没有在 Safari、Chrome、Arc 或 Electron 里按 `gg` / `G`
- 没有看滚轮的 `location` 是否和辅助功能框同一套坐标。现有代码本来就不翻转坐标
- 没有确认这些应用的竖向滚动条 `AXValue` 是否可写，以及写完再读是否会撒谎
- 没有确认 8 下 50_000 像素能盖住一条很长的网页。更长的页面日志里会是 `result=unobserved`
- 没有确认 `CFEqual` 或这次按路径绑定的元素，在页面刷新之后还指着同一块滚动区域
- `d` / `u` 在指针下本来就是有限像素的滚轮，没有走这次的空 store。焦点不在指针下、又不知道内容长度时，半页仍会放过。可见高度为 0 的半页仍放过。这两条没有改
