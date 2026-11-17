# 微信滚动、视觉标签、gi 和标签位置

记录日期：2026-11-17。Linux，Ubuntu 24.04，Swift 6.2.1。基线是 `65d868f`（v0.1.3）。没有微信，也没有 Mac。`AXApplicationReader.swift`、`VisionHintCapture.swift`、`FrontWindowFrame.swift`、`HintOverlayWindow.swift` 整段包在 macOS 条件里，这里不编译。

## 根因

1. **`f` 能出横幅、但没有标签。** 置信度：高（代码路径），中（微信的树确实为空，用户是这样描述的，这里没有 dump）。`f` 已经进了标签流程，扫描结果是 0，所以状态栏写成「没找到可点击元素」。v0.1.3 在空结果之后没有第二套目标。微信 4.1.15 是自绘界面，辅助功能树可以是空的。

2. **`j` / `k` / `d` / `u` / `gg` / `G` 在没有滚动区域时没有滚轮。** 置信度：高。`ScrollHitRule` 找不到区域就 `passedThrough`。按住输入框时，会话还会把这个放过改成吞掉，执行器的效果是空的。微信没有 `AXScrollArea` / `AXWebArea` 时，键被吃掉或者交给微信，画面不动。失败测试是空区域加窗口框时期望有滚轮，修复前效果列表是空的。

3. **`gi` 什么都不做。** 置信度：高。两条叠在一起。
   - `AXInputFocuser.bind` 没有任何调用者。`focusInput` 查的是空表，永远返回 false。
   - 就算返回 false，`NormalCommandSession` 也不点击、也不改模式。它只在 `focusInput` 为 true 之后再读一次焦点，读到可编辑才进 Insert。写的属性还是系统级的 `AXFocusedUIElement`，不是元素上的 `AXFocused`。
   - 选框用的是树序的第一个可编辑节点，不是靠下的输入区。

   先失败的测试 `testGIClicksTheFieldAndEntersInsertWhenAccessibilityFocusIsRejected`（2026-11-17，退出码 1）：模式是 `normal` 而不是 `insert`，`focusedPath` 是 nil，点击效果是 `[]`。

4. **标签和点击不在同一块可见区域上。** 置信度：中。Y 翻转在 #18 里已经用主屏高度算过。还没做的是：一块面板跨两块缩放不同的屏、元素框超出窗口或网页视口时标签仍钉在原始框的上沿、重叠标签叠在一起。点击用的是未裁切框的中心，眼睛看到的是另一处。

## 修法

- 没有滚动区域时，指针在前台窗口内就在指针上发滚轮，否则在窗口中心。窗口框先用辅助功能，没有再用 `CGWindowList` 里该进程最大的一层窗口。`j` / `k` 是 60 点，`d` / `u` 是窗口在该方向上的一半，`gg` / `G` 是原来的 8 下大滚轮。没有窗口时写 `scroll-fallback direction=… reason=no-window`。有区域时仍走原来的命中，不改。
- 辅助功能命中是 0，或者前台应用在 `visionBundleIdentifiers` 里（默认 `com.tencent.xinWeChat`）时，另起队列截前台窗口。macOS 14 及以上先用 `SCScreenshotManager`，失败或更老的系统用 `CGWindowListCreateImage`。Vision 用 `zh-Hans` 和 `en-US`、`accurate`，并可识别矩形。文字行合成列表行，重叠框丢掉，再按原来的排序和单字母优先标。坐标：Vision 归一化、原点在图的左下 → 像素、y 向下 → 除以该窗口所在屏的缩放 → 加上窗口的辅助功能原点。图片不写盘、不上传。事件钩子不等待。屏幕录制用 `CGPreflightScreenCaptureAccess`，只在第一次需要时调用 `CGRequestScreenCaptureAccess`。没允许时状态栏是「需要“屏幕录制”权限才能在此应用显示标签」。只缺这项不挡住启动。
- `gi` 在文本框上写 `AXFocused`。失败则点击可见框中心。然后 `holdManualInsert`，清掉 Esc 按住的普通模式。没有文本框时，名单里的应用点击窗口底部偏上 48 点（或高度的 12%，取较小者）并写 `gi decision=bottom-center`。窗口太小或不是这类应用时，状态栏是「没找到可输入的文本框」，不点击。
- 标签先裁到窗口和包住它的滚动/网页视口。完全在外面、零尺寸、或只有一条缝伸进视口的巨大框丢掉。裁切后的中心就是点击点，标签贴在这块可见区域的上沿。每块屏幕一块面板，不把不同 `backingScaleFactor` 的屏并进同一个窗口。重叠的标签向右挪开。
- 调试日志仍是 `SUPERVIM_LOG=1` 或 `defaults write com.lijigang.supervim SupervimDebugLog -bool true`，文件 `~/Library/Logs/Supervim.log`，默认关。

## 先失败

```text
swift test --filter testGIClicksTheFieldAndEntersInsertWhenAccessibilityFocusIsRejected
```

2026-11-17 16:37:53 UTC。退出码 1。3 个断言失败：模式是 `normal`，`focusedPath` 是 nil，点击是 `[]`。

同一时刻，空滚动区域不会发滚轮。加上窗口框之后，测试期望指针处或窗口中心有滚轮。

## 通过

`swift test` 退出码 0。Linux 执行 674 个测试，0 失败。`testModifierMasksMatchCoreGraphics` 只在 macOS 上跑，所以 macOS 会多 1 个，一共 675。

覆盖率（Linux，`llvm-cov`，门是 90%）：`Actuator.swift` 98.13%，`AXScanner.swift` 93.41%，`NormalCommandSession.swift` 96.18%，`HintOverlay.swift` 96.07%，`ModeMachine.swift` 100%，`PermissionGuide.swift` 100%，`Settings.swift` 99.75%，`EventInterpreter.swift` 96.33%。

## 调试日志

打开：

```bash
SUPERVIM_LOG=1
```

或：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool true
```

关掉：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool false
```

不设 `SUPERVIM_LOG` 即可去掉环境变量。

如果这版在微信里还是不行，把按键前后这些行原样发回来：

```text
ax-summary bundle=com.tencent.xinWeChat nodes=0 roles=
hint-scan bundle=com.tencent.xinWeChat window=focused found=1 visited=1 hits=0 ms=40 expansion=manual+enhanced retry=empty
hint-banner reason=noTargets
hint-banner reason=screenRecording
vision permission=denied image=0x0 boxes=0 hits=0
vision permission=granted image=1600x1200 boxes=40 hits=12
scroll-fallback direction=down reason=no-scroll-area source=pointer x=420.0 y=300.0
scroll-fallback direction=up reason=no-window
scroll-target id=history direction=up x=400.0 y=250.0
gi decision=none reason=no-input bundle=com.tencent.xinWeChat
gi decision=bottom-center bundle=com.tencent.xinWeChat x=400.0 y=552.0
gi decision=ax-focused path=0/2 role=AXTextArea x=200.0 y=540.0
gi decision=click reason=ax-focus-failed path=0/2 x=200.0 y=540.0
hint-screen index=0 x=0.0 y=0.0 w=1920.0 h=1080.0 scale=2.0
hint-panel screen=1 scale=1.0 x=-400.0 y=964.0 w=18.0 h=16.0
hint-label index=0 ax=-400.0,100.0,80.0,30.0 ns=-400.0,964.0,18.0,16.0
hint-click index=0 method=coordinate ax=-360.0,115.0
```

| 行 | 含义 |
| --- | --- |
| `ax-summary` | 这次采用的树有多少节点，以及每种 role 的个数。`nodes=0` 或只有窗口、没有按钮，就是视觉回退的理由 |
| `hint-scan` | 和以前一样。`hits=0` 才会去截图 |
| `hint-banner reason=screenRecording` | 没给屏幕录制权限 |
| `vision` | `permission` 是 `granted`、`denied`、`no-window`。`image` 是像素。`boxes` 是识别框。`hits` 是合成后的标签数 |
| `scroll-fallback` | 没有滚动区域。`source=pointer` 是指针在窗口里。`source=window-center` 是窗口中心。`reason=no-window` 是辅助功能和窗口列表都没有框 |
| `scroll-target` | 找到了滚动区域，滚轮或到边打在这个点 |
| `gi decision` | `ax-focused` 写上了 `AXFocused`。`click` 是写失败后的点击。`bottom-center` 是微信这类没有文本框时的估计。`none` 是没点 |
| `hint-screen` / `hint-panel` / `hint-label` / `hint-click` | `hint-screen` 的 index 0 是主屏。`hint-panel` 是该屏自己的面板和缩放。`ax` 是裁切后的元素框。`hint-click` 的点必须落在这个框的中心 |

## 这里没有验证的事

- 没有在微信 4.1.15 里按 `f`、`j`、`k`、`gi`
- 没有看到屏幕录制的系统对话框，也没有确认 `SCScreenshotManager` 对微信的 GPU 窗口能截到会话列表
- 没有确认 OCR 能把中文会话行合成可点的一行，也没有确认 120ms 之外的树会不会忽然长出来
- 没有在主屏在右、副屏在左、两块屏缩放不同的机器上看标签
- 没有确认 `AXFocused = true` 在备忘录或 Safari 里真的把插入点放进该框
- 没有确认窗口列表的框和辅助功能框是同一套坐标。现有滚轮和点击都按辅助功能的左上角原点，不翻转
- 底部中心是估计。微信输入框若不在那一块，日志里会是 `gi decision=bottom-center`，点的位置就是行里的 `x`、`y`
