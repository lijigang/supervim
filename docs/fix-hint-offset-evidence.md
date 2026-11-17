# Grok 里 f 的标签和点击错位

记录日期：2026-11-17。Linux，Ubuntu 24.04，Swift 6.2.1。画标签的 `HintOverlayWindow.swift` 在这里不编译。坐标换算是纯函数，测试覆盖了它。

## 根因

辅助功能的 `AXPosition` / `AXSize` 是全局坐标：原点在主屏左上角，y 向下。`NSWindow` 的原点在主屏左下角，y 向上。主屏是 `NSScreen.screens[0]`，不是 `NSScreen.main`，也不是窗口所在的那块屏。

修复前 `PanelHolder.show`（`Sources/SupervimSystem/HintOverlayWindow.swift` 大约第 102 行和第 117 行）把 `marker.anchor` 直接写成 `NSTextField.frame`，再把这些框的并集交给 `panel.setFrame`。没有做 `nsY = 主屏高度 - axY - h`。标签在竖直方向是翻的。左屏的负 x 还能留在左边，但 y 会把上方的按钮画到下方。用户按那个字母时，点的是标签所绑定的元素，不是眼睛看到的那个按钮。

点击坐标本身用的是元素框中心，和 `CGEvent` 一样是左上角原点，不应该再翻成 NS 坐标。错的是标签画在哪，以及以前明文写死 `canAccessibilityPress: false`（`HintOverlay.swift` 的 `request`），所以从不发 `AXPress`。

`copyFrame` 读的是 `kAXPositionAttribute` 和 `kAXSizeAttribute`，不是网页内的相对坐标。

标签编号和元素的映射本来就是对齐的。`HintSession` 用 `label.index` 取过滤之后的同一个 `targets` 数组。第 n 个标签的 `activation.index` 和 `activation.point` 就是第 n 个元素的中心。失败测试里，索引和标识断言没有先失败；失败的是把该中心拿去和还没换算的点击函数比较。

面板以前用标签框的并集当窗口 frame，子视图会减去这个原点。并集可以跨屏，但因为 y 没换算，窗口落在错误的 NS 位置。换算之后仍然用并集，不裁到 `NSScreen.main`。`backingScaleFactor` 只写进日志，不乘到坐标上。点和像素没有混用。

## 先失败

`HintGeometry.labelRect` 当时原样返回辅助功能原点。

- 主屏在右、副屏在左：期望标签 y 是 964，实际是 100。点击点是 `(0, 0)`，不是 `(-300, 120)`。
- 两块屏高度不同：期望 y 1070，实际 360。
- 副屏在主屏上方：期望 y 1970，实际 -900。
- 缩放系数为 2 时，点击点仍然被写成 `(0, 0)`，而不是和 1 倍缩放相同的 `(-300, 120)`。

## 修法

`HintGeometry.labelRect`：`nsY = screens[0].height - axY - elementHeight`，标签贴在元素可视区域的上沿，中心落在元素框内。x 不改。`backingScale` 不参与计算。

`HintGeometry.clickPoint` 返回辅助功能框的中心。`CGEvent` 继续用这个点。

元素的 `AXActionNames` 含 `AXPress` 时，普通点击先发 `AXPress`。失败或找不到元素时，`CGEventActuatorPoster` 再用这个中心做左键点击。`F` 仍是按住 Command 的鼠标点击，因为 `AXPress` 不能带 Command。

`HintGeometry.arrange` 把各屏上的标签并成一个面板，子视图坐标减去面板原点，加回去等于全局 NS 坐标。

调试日志（和 #17 同一开关）多了这些行：

```text
hint-screen index=0 x=0.0 y=0.0 w=1920.0 h=1080.0 scale=2.0
hint-label index=0 ax=-400.0,100.0,200.0,40.0 ns=-400.0,964.0,18.0,16.0
hint-click index=0 method=AXPress ax=-300.0,120.0
hint-click index=1 method=coordinate ax=80.0,215.0
```

`hint-screen` 每个屏一行，index 0 是主屏。`ax` 是辅助功能框，`ns` 是画上去的 AppKit 框。`method` 是 `AXPress` 或 `coordinate`。

## 通过

`swift test` 退出码 0。Linux 执行 616 个测试，0 失败。
