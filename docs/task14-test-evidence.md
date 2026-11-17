# 任务 14 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit，没有 ApplicationServices，没有 IOKit

因此下面能证明的是权限引导的出现、消失和设置链接的先失败、后通过，以及 Linux 上 `PermissionGuide.swift` 的覆盖率。不能证明 `AXIsProcessTrusted` 或输入监控探测在真机上的返回值，也不能证明系统设置面板真的被打开。授权之后当前进程能否不用退出重开就生效，保持未验证。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。写本文时那次 CI 还没有结果。

## 范围

加了 `SupervimCore` 里的 `PermissionGuide`。它根据注入的辅助功能和输入监控状态决定引导是否可见、文案，以及要打开的系统设置链接。`PermissionStatusProviding` 和 `PrivacyPaneOpening` 是可替换的接口。macOS 上的探测和 `NSWorkspace` 打开放在 `SupervimSystem/PermissionAccess.swift`，整段包在 `canImport` 里。引导窗口在 `Sources/Supervim/PermissionGuidancePanel.swift`，包在 `canImport(AppKit)` 里。菜单进程在缺少权限时显示这个窗口，并在菜单分隔线前加上 Permissions。仍然不安装事件钩子，也不启动 AXScanner。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 07:29:34 UTC 到 07:29:39 UTC。命令：`swift test --filter 'PermissionGuideTests|PermissionAccessTests'`。当时还没有 `PermissionGuide.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/PermissionGuideTests.swift:236:33: error: cannot find 'PrivacyPaneLink' in scope
Tests/SupervimCoreTests/PermissionGuideTests.swift:251:6: error: cannot find type 'PermissionGuide' in scope
Tests/SupervimCoreTests/PermissionGuideTests.swift:306:47: error: cannot find type 'PermissionStatusProviding' in scope
Tests/SupervimCoreTests/PermissionGuideTests.swift:320:41: error: cannot find type 'PrivacyPaneOpening' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：刷新和打开链接都返回不可见的空引导，辅助功能和输入监控的探测结果一律当成缺失。空实现不是最终行为。

## 第二次运行：断言失败（RED）

时间：2026-11-17 07:30:03 UTC 到 07:30:08 UTC。同一条命令。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'PermissionAccessTests' failed at 2026-11-17 07:30:07.993
	 Executed 1 test, with 1 failure (1 unexpected) in 0.001 (0.001) seconds
Test Suite 'PermissionGuideTests' failed at 2026-11-17 07:30:08.108
	 Executed 18 tests, with 66 failures (0 unexpected) in 0.108 (0.108) seconds
```

那 1 个 unexpected 是 `PermissionAccess.swift` 还不存在，源码测试抛了「文件不存在」。18 个引导测试里，17 个失败。代表输出：

```text
testBothMissingShowsGuidanceAndBothSettingsLinks : XCTAssertTrue failed
testBothMissingShowsGuidanceAndBothSettingsLinks : XCTAssertEqual failed: ("") is not equal to ("Supervim Needs Permissions")
testOpeningAMissingPaneUsesThatSettingsLink : XCTAssertEqual failed: ("[]") is not equal to ("["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"]")
testFailedOpenKeepsGuidanceAndDoesNotPretendItWasGranted : XCTAssertEqual failed: ("") is not equal to ("Could not open System Settings.")
testUnknownOrDeniedListenEventIsNotAGrant : XCTAssertEqual failed: ("missing") is not equal to ("granted")
testVisibleCopyDoesNotPromiseARestartFreeGrant : XCTAssertTrue failed
testAppPresentsGuidanceWithoutPromptingOrInstallingATap : XCTAssertTrue failed
```

空实现一律不显示引导，也不打开链接。`testCoreDoesNotImportSystemFrameworks` 在空实现上通过，因为占位文件已经声明了两个协议，而且没有导入系统框架。`testBothGrantedHidesGuidance` 里「不可见、标题和正文为空、没有链接」这几条在空实现上也会过，失败的只是 Check Again 和 Permissions 这两个固定标题。这两处不能单独当作「测试先抓住了错误」的证据。真正先失败的是缺权限时引导出现、只列出仍缺的那一项、打开对应链接、授权后引导消失，以及正文写明不保证免重启。

## 第三次运行：两条探测必须同时同意（RED）

时间：2026-11-17 07:31:38 UTC 到 07:31:39 UTC。命令：`swift test --filter testListenEventGrantRequiresTheHidGrantAndThePreflight`。退出码 1。构建失败，断言还没执行。

```text
Tests/SupervimCoreTests/PermissionGuideTests.swift:152:31: error: type 'ListenEventAccess' has no member 'resolve'
```

这是缺合并两条探测的函数，不是拼写错误。后面的 `.granted` 找不到是这一处带出来的。

## 第四次运行：实现之后通过（GREEN）

时间：2026-11-17 07:32:36 UTC 到 07:32:39 UTC。命令：`swift test --filter 'PermissionGuideTests|PermissionAccessTests'`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'PermissionAccessTests' passed at 2026-11-17 07:32:39.075
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'PermissionGuideTests' passed at 2026-11-17 07:32:39.392
	 Executed 19 tests, with 0 failures (0 unexpected) in 0.31 (0.31) seconds
```

这一轮还没有把任务 14 改成 `done`。状态文件和 `TaskGraphTests` 是在这次通过之后一起改的。改的时候主干已经合并了任务 10，变基保留了任务 10 的 `done`，任务 11 和 12 仍是 `pending`。

## 第五次运行：变基到任务 10 之后再测，并量覆盖率

时间：2026-11-17 07:35:28 UTC 到 07:35:37 UTC。命令：`scripts/permission-guide-coverage.sh`。退出码 0。构建日志里没有编译警告。脚本里面会再跑一次 `swift test --enable-code-coverage`。

系统测试 159 个：`AXScannerTests` 44、`ActuatorTests` 40、`EventTapTests` 29、`HintOverlayTests` 30、`MenuBarPreflightTests` 5、`PermissionAccessTests` 1、`UserDefaultsSettingsStoreTests` 10。核心测试 322 个：`CommandMapTests` 32、`EventInterpreterTests` 45、`HintLabelerTests` 41、`HintSessionTests` 17、`KeyParserTests` 37、`MenuBarControllerTests` 15、`MenuBarManifestTests` 18、`ModeMachineTests` 61、`PermissionGuideTests` 19、`SettingsTests` 36、`TaskGraphTests` 1。合计 481 个 XCTest，0 失败。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
PermissionGuide.swift line coverage: 100.00% (95/95)
PermissionGuide.swift region coverage: 100.00% (38/38)
PermissionGuide.swift function coverage: 100.00% (12/12)
```

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。`PermissionAccess.swift` 和引导窗口整段包在平台条件里，Linux 上不计入覆盖率，脚本也不把它们放进 90% 门槛。

## 引导在做什么

| 情况 | 结果 |
| --- | --- |
| 辅助功能和输入监控都缺 | 引导可见。两个链接，辅助功能在前 |
| 只缺辅助功能 | 只有辅助功能链接 |
| 只缺输入监控 | 只有输入监控链接 |
| 两项都已授权 | 引导不可见，链接为空 |
| 之后重新读取变成已授权 | 引导消失 |
| 已授权又变成缺失 | 引导再次出现 |
| 打开仍缺的那一项 | 调用打开接口，参数是该项的系统设置 URL。不把权限标成已授予 |
| 打开时下一次读取已经两项都有 | 引导消失，提示仍是空的 |
| 打开一项之后另一项仍缺 | 引导留下剩下的那一个链接 |
| 对已经授予的项调用打开 | 不调用打开接口 |
| 打开失败 | 引导还在，提示是 Could not open System Settings. |
| 失败之后再刷新 | 清掉这条提示。权限状态不变 |

可见时的正文写明：授权不保证当前进程不用退出再打开就能用上；这取决于系统版本和权限数据库是否刷新；这一点未验证。未签名的 Supervim 重新构建后，代码目录哈希可能变化，可能要再授权一次。正文不写「免重启已经成立」，也不提 Electron 的 `AXManualAccessibility`。

输入监控只有在 HID 监听探测是 granted、并且预检也是 granted、而且没有同时报 denied 或 unknown 时，才算授予。unknown、denied，以及两条探测不一致，都当成缺失。

## 交给所有者看的决定

规格第 10 条要求缺权限时显示引导并提供系统设置链接，同时希望授权后不用重启。文末写明这不是平台保证，测不到就保持未验证。没有改规格正文。

1. **判断放在 `PermissionGuide`，真实探测放在 `PermissionAccess.swift`。** 核心不导入 AppKit、ApplicationServices、IOKit 或 CoreGraphics。测试注入 `PermissionStatusProviding` 和 `PrivacyPaneOpening`。
2. **辅助功能用 `AXIsProcessTrusted()`。** 不调用 `AXIsProcessTrustedWithOptions`，不弹出授权框，也不使用 `AXManualAccessibility`。那不是辅助功能常量，是 Electron 的接口。这里没有做 CF 字典的向下转换。
3. **输入监控要两条探测同时同意。** `IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)` 给出 granted、denied 或 unknown。`CGPreflightListenEventAccess()` 只给是或否。只在 HID 为 granted 且预检为真时当作已授予。单独一条可能在「还没问过用户」或「只有辅助功能、没有输入监控」时给出过宽的结果，所以不一致就当成未知，也就是缺失。这个组合没有在 Mac 上核对过。
4. **不调用会弹出系统对话框的请求函数。** 没有 `CGRequestListenEventAccess`，也没有 `IOHIDRequestAccess`。用户从引导里的链接自己打开系统设置。
5. **链接是 macOS 13 系统设置的 URL，没有经过所有者确认，也没有在 Mac 上点过。** 辅助功能是 `x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility`。输入监控是同一扩展上的 `Privacy_ListenEvent`。打开动作是 `NSWorkspace.shared.open`。
6. **文案明确不保证免重启。** 授权后当前进程能否立刻看到权限，保持未验证。未签名二进制重新构建后可能要重新授权，写在引导正文和 README 里。
7. **菜单栏快照不增加命令。** 任务 13 把菜单锁成 Pause、Resume、Settings、分隔线、Quit。Permissions 由应用外壳在分隔线前插入，而且只在引导可见时出现。关掉窗口不会把权限标成已授予。下次启动如果仍缺权限，窗口会再出现。应用变为活动状态时，如果窗口还开着，会再读一次，两项都有了就关掉。
8. **仍然不安装事件钩子，也不启动扫描器。** 和任务 13 的理由相同：钩子一旦装上，已知且不可编辑的焦点会吞掉还没执行的命令。权限引导不改变这一点。
9. **入口仍是 `SupervimApp.swift`。** `@main` 留在 `#if os(macOS)` 里。没有 `main.swift`。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit、ApplicationServices 或 IOKit
- 没有调用真实的 `AXIsProcessTrusted`、`IOHIDCheckAccess` 或 `CGPreflightListenEventAccess`
- 没有打开系统设置里的辅助功能或输入监控面板
- 没有验证授权之后不退出重开就能生效。这一点保持未验证
- 没有验证未签名二进制重新构建后是否真的要重新授权
- 没有看过引导窗口
- `PermissionAccess.swift` 里把 C 枚举翻译成 Bool 的那几行没有执行。Swift 侧 `ListenEventAccess.resolve` 的合并规则有测试
- `NSWorkspace` 打开失败，以及空 URL 被拒绝，没有在 macOS 上跑过
- 没有安装事件钩子，也没有测量 CPU、内存或 `f` 的延迟
