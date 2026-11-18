# Supervim 实现计划

状态：已批准。技术路线是 Swift 6、AppKit、Swift Package Manager、macOS 13 及以上、XCTest。任务 1 只落地工程骨架，不提前实现下面的功能模块。

## 模块

纯逻辑放在 `SupervimCore`，不导入 AppKit、辅助功能或事件框架：

- **KeyParser**：按键序列、前缀和超时
- **ModeMachine**：Normal、Insert、Hint、Paused
- **HintLabeler**：最短且前缀安全的标签，以及过滤
- **CommandMap**：命令、动作或放过
- **Settings**：UserDefaults 里的排除列表、暂停快捷键、登录启动偏好

系统适配放在 `SupervimSystem`，对核心暴露协议，测试用替身：

- **EventTap**：`CGEventTap` 拦截
- **AXScanner**：辅助功能树和焦点
- **Actuator**：点击、Command 点击、滚动、应用快捷键
- **Overlay**：透明、不激活的标签和帮助
- **MenuBar**：状态和菜单
- **Onboarding**：权限引导

可执行目标 `Supervim` 是菜单栏应用。

## 运行路径

`EventTap` 拿到按键后，只读取当前模式和已经缓存的焦点，交给解析器和命令表，再决定执行动作或更新浮层。

不要在事件钩子里同步扫描辅助功能树。扫描放到钩子之外，结果缓存起来。焦点未知时按宪法放过按键。

v0.1.5 起这条路径分成四条线，原因和测量见 [v0.1.5 证据](v0.1.5-evidence.md)：

- **钩子线程**（`supervim.event-tap`）：钩子有自己的线程和 run loop。回调只读缓存的模式和焦点，决定吞掉还是放过，然后返回。它不调用辅助功能，不发事件，不等主线程。钩子被系统停用时在回调里立刻重新打开，另有一个 500ms 的计时器在别的队列上检查并打开（`TapGuard`）。
- **扫描队列**（`supervim.scan`）：读焦点、走窗口树、`f` 的扫描。每个节点一次批量读取，消息超时 0.75 秒，按层走，一层里最多 4 个线程，节点上限 2000，深度上限 32，`f` 的一遍最长 1 秒。
- **动作队列**（`supervim.actuate`）：滚轮、按键、`AXPress`、`gi` 的聚焦。
- **主线程**：浮层和菜单。浮层面板每块屏幕一个，创建一次后复用。

钩子把工作交出去用的是 `WorkScheduling`。测试里用 `ManualWork` 让交出去的工作停在队列里，由此断言「先返回，后执行」。

## 测试与测量

纯逻辑的覆盖率目标是不低于 90%。这是后续模块的目标。任务 1 只覆盖清单和预检，不把这个百分比写成已经达到。

`f` 的延迟是测量值，不是单元测试里的断言。`LiveBenchmarkTests` 在 macOS CI 上打印以 `BENCH` 开头的行（真实窗口的读取、浮层、文字识别），不对速度做断言。调试日志里的 `timing stage=...` 行是真机上的测量手段。

## CI 与发布

每次 push 和 pull request 都在 `macos-latest` 上执行 `swift build` 和 `swift test`。

`create-dmg` 和按 tag 发布 GitHub Release 属于任务 15。任务 1 的 CI 会组装未签名的 `.app`，用来确认菜单栏包能生成，但不上载 DMG。

## 任务 1 的应用包脚手架

批准计划要求 SPM 和菜单栏应用，没有指定 `.app` 如何生成。任务 1 在三个做法里选了一种，没有改产品要求。

1. **手写 Xcode 工程。** 能直接产出 `.app`，但目标和 `Package.swift` 各写一遍，纯逻辑测试被绑到 `xcodebuild`。
2. **XcodeGen。** 当前环境没有这个工具。按本次约束，不额外安装。
3. **采用的做法：SPM 是唯一的构建描述。** `App/Supervim/Info.plist` 保存 `LSUIElement=true`、最低系统 13.0 和应用包元数据。`scripts/assemble-app.sh` 在 `swift build` 之后把二进制放进 `build/Supervim.app`。`build/` 不进版本库。

这样 `swift test` 仍然是逻辑测试的入口，CI 不需要第二套目标定义。菜单栏占位程序在启动时调用 `setActivationPolicy(.accessory)`，避免 `swift run` 因为没走 Launch Services 而露出 Dock 图标。

占位菜单只有「Quit Supervim」。Normal / Insert / Paused 留给任务 13，避免任务 1 假装已经有模式。

## 平台风险

计划已经指出：Electron 的 `AXManualAccessibility` 也许能帮助提示授权，但不是保证。未签名构建在二进制变化后可能要重新授权。任务 1 不使用 Electron，也不把这些行为写成已经验证。

细节见 [规格中的歧义列表](spec.md#未改要求的技术歧义与不可保证项)。

## 本任务没有改动的计划项

- 不实现 KeyParser、ModeMachine、HintLabeler、CommandMap、Settings 的功能。
- 不实现 EventTap、AXScanner、Actuator、Overlay、权限引导或 DMG。
- 不把覆盖率、内存、CPU、`f` 延迟写成已测量。
- 任务 1 已合并，状态为 `done`。任务 2 在评审前保持 `in-progress`。其余任务保持 `pending`。
