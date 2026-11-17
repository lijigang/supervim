# 微信里按 f 没有标签

记录日期：2026-11-17。Linux，Ubuntu 24.04，Swift 6.2.1。`AXApplicationReader.swift` 和 `HintOverlayWindow.swift` 在这里不编译进测试二进制。

## 和 #17 的关系

#17 之后，Esc 记下了输入框身份，同一元素不会马上回到 Insert。这时 `f` 会进入标签流程。

如果还没按 Esc，焦点又在可编辑输入框里，`f` 仍然被放过。这是插入模式，不是扫描失败。Grok 能出标签，说明同一次操作里按键已经进了标签流程。微信没有任何画面，更像是扫描结果为空，标签流程立刻取消。取消后菜单标题仍是 Normal（Hint 不单独显示），所以看起来像没触发。

如果微信每次焦点通知都给出新的元素身份，#17 的保持会失效，`f` 又会在 Insert 里被放过。日志里 Esc 之后马上出现 `insert` 且 `trigger=focus`，就是这种情况。

## 根因

两处都会让微信的扫描变成 0 个标签。

1. `FocusClassification.isClickable`（`Sources/SupervimSystem/AXScanner.swift`）先看角色是不是容器。`AXGroup`、`AXRow` 在容器表里，函数直接返回 false，不再看 `AXPress`。Qt 自绘界面经常把可点的气泡做成带 `AXPress` 的 `AXGroup`。`AXStaticText`、`AXCell`、`AXImage` 不在容器表里，本来就会因 `AXPress` 算作可点。
2. 扫描之前没有对前台 `AXApplication` 设置 `AXManualAccessibility` 或 `AXEnhancedUserInterface`。Chromium、Electron、Qt 在这两个属性打开之前，常常只给出一个空窗口。空结果走 `HintController.stop(.noTargets)`，只把浮层藏起来，状态栏没有字。

深度上限 2000 节点、32 层，这次失败测试里的树远没有到。可见性判断用的是元素框和窗口框的交集，不是这次空结果的原因。

## 先失败

`testGroupWithPressActionIsClickable`：带 `AXPress` 的 `AXGroup` 得到的列表是空的。

`testCollapsedWindowIsRereadAfterAccessibilityIsEnabled`：未开启时窗口没有子节点。期望先请求展开再读第二次。实际 `expansions` 是空的，窗口只读了 1 次，命中是空的。

## 修法

- `AXPress`、`AXConfirm`、`AXPick` 先于容器排除。没有这些动作的 `AXGroup` 仍然不是可点元素。
- 命中数是 0 时，对前台应用调用 `expandAccessibilityTree(allowEnhanced: true)`，然后重读窗口。每个 pid 先试 `AXManualAccessibility=true`。失败才设 `AXEnhancedUserInterface=true`。手动设置成功过的 pid 不再开 enhanced，避免拖慢窗口动画。两个属性每个 pid 只写一次。
- 空结果或窗口读失败时，`HintMissBanner` 把状态栏标题改成「没找到可点击元素」，大约 2 秒后回到 Normal / Insert / Paused。
- 同一把调试开关写下 `hint-scan` 行：bundle id、遍历节点数、命中数、耗时、`expansion=none|manual|enhanced`。

## 通过

`swift test` 退出码 0。Linux 执行 616 个测试，0 失败。`testModifierMasksMatchCoreGraphics` 只在 macOS 上跑。
