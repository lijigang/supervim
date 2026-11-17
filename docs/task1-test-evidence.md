# 任务 1 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），用 Swiftly 安装，只为了在这台机器上跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有启动 AppKit

因此下面能证明的是纯逻辑测试的先失败、后通过，以及 Linux 上能组装出带 `Info.plist` 的目录。不能证明 Dock 图标真的隐藏，也不能证明菜单栏占位进程能在 macOS 上跑起来。那一部分交给 GitHub Actions 的 `macos-latest`。本文写完时，那次 CI 还没有结果；PR 说明里的检查状态才是实际结果。

## 用过和没用过的工具

- 环境里有 Superpowers 技能。任务 1 读过并按测试先行来做：先写测试，看到失败，再写实现。完成前又按验证要求重新跑了 `swift test`。
- 宪法、规格和计划在这次任务开始前已经由所有者批准。没有用 brainstorming 流程重写它们，也没有安装或运行 spec-kit（环境里没有 `specify`）。
- 环境里没有 `task-master` CLI。没有运行它。`.taskmaster/tasks/tasks.json` 是对照上游 `src/schemas/base-schemas.js` 和 `docs/task-structure.md` 手写的。格式说明见 [任务文档](tasks.md#task-master-格式)。

## 第一次运行：测试没编译过

`TaskGraphTests` 里用了 `CFGetTypeID` / `CFBooleanGetTypeID`。这台 Linux 上的 Swift 6.4 SDK 没有这两个符号，测试目标编译失败，断言还没执行：

```text
Tests/SupervimCoreTests/TaskGraphTests.swift:152:12: error: cannot find 'CFGetTypeID' in scope
Tests/SupervimCoreTests/TaskGraphTests.swift:152:35: error: cannot find 'CFBooleanGetTypeID' in scope
error: Build failed
```

这是测试代码的编译错误，不是产品行为失败。随后把任务文件解析改成 `JSONDecoder`，没有改产品实现。这次编译日志后来被下一次 `tee` 覆盖，上面两行来自当时的命令输出。

## 第二次运行：断言失败（RED）

时间：2026-11-17 04:29:22 UTC。命令：`swift test`。构建成功，然后测试失败，退出码 1。

当时的产品代码是故意放空的：

- 版本解析一律返回 `0.0.0`
- 清单校验一律通过
- 属性列表解码忽略输入，并假装 Dock 已隐藏
- 预检一律返回可以在 Mac 上启动
- `currentHost()` 一律返回 macOS
- 核心源文件里有一行被 `#if false` 包住的 `import AppKit`，用来确认边界测试能看见它
- 还没有 `App/Supervim/Info.plist`，也没有 `tasks.json`

结果：24 个 XCTest 里 22 个失败。`SupervimSystemTests` 5 个里 4 个失败；`SupervimCoreTests` 19 个里，断言失败 31 次。失败原因是功能还没写，不是拼写错误。代表输出：

```text
MenuBarPreflightTests.testCurrentHostMatchesCompiledPlatform : XCTAssertEqual failed: ("macOS") is not equal to ("other")
MenuBarPreflightTests.testInvalidManifestIsNotReadyOnMacOS : XCTAssertThrowsError failed: did not throw error
MenuBarPreflightTests.testValidManifestOnNonMacHostIsUnsupported : XCTAssertEqual failed: ("readyForMenuBarLaunch") is not equal to ("unsupportedPlatform")
MenuBarManifestTests.testCheckedInInfoPlistPassesMenuBarContract : failed - missing App/Supervim/Info.plist
MenuBarManifestTests.testDecoderReadsAMenuBarPropertyList : XCTAssertEqual failed: ("") is not equal to ("com.lijigang.supervim")
MenuBarManifestTests.testParsesDottedSystemVersions : XCTAssertEqual failed: ("SystemVersion(major: 0, minor: 0, patch: 0)") is not equal to ("SystemVersion(major: 13, minor: 0, patch: 0)")
MenuBarManifestTests.testRejectsManifestThatWouldShowTheDockIcon : XCTAssertThrowsError failed: did not throw error
MenuBarManifestTests.testSupervimCoreSourcesDoNotImportSystemUIOrEventFrameworks : XCTAssertEqual failed: ("["MenuBarManifest.swift:3 imports AppKit"]") is not equal to ("[]")
TaskGraphTests.testTaskMasterFileMatchesApprovedSchedule : failed - missing .taskmaster/tasks/tasks.json
```

有两个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testAcceptsMacOS13AndNewer`：空校验会接受任何清单，所以合法清单当然通过
- `testValidManifestOnMacHostIsReady`：空预检一律返回可以启动

真正先失败的是拒绝路径、解码结果、非 Mac 主机、核心库边界、缺失的 plist 和缺失的任务文件。实现之后，那两个本来就通过的测试仍然通过，它们单独不能证明实现是对的。

Swift Testing 库另外报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 04:32:26 UTC。命令：`swift test`。退出码 0。

```text
Test Suite 'MenuBarPreflightTests' passed
	 Executed 5 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
Test Suite 'MenuBarManifestTests' passed
	 Executed 18 tests, with 0 failures (0 unexpected) in 0.111 (0.111) seconds
Test Suite 'TaskGraphTests' passed
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds
```

合计 24 个 XCTest，0 失败。同一轮 `swift build` 退出码也是 0，输出是 `Build complete!`，没有编译警告。

提交前又跑了一次 `swift test`（2026-11-17 04:33:52 UTC），仍是 24 个测试、0 失败，退出码 0。源码没有再改。

这些测试检查的是行为，不是某个常量等于自己：

- 会露出 Dock 图标的清单被拒绝，macOS 13 以下被拒绝，空的标识、名字、可执行文件名被拒绝，不是 `APPL` 的包被拒绝
- `13`、`13.0`、`14.2.1` 能解析；空串、`13.`、`13.0b`、`13.00`、`v13.0` 被拒绝
- 属性列表里 `LSUIElement` 为真、为假、缺失、写成整数，结果不同；坏掉的 plist 和数组 plist 被拒绝
- 仓库里的 `App/Supervim/Info.plist` 要能通过上面的校验
- 合法清单在 Mac 上预检通过，在其他主机上得到 `unsupportedPlatform`；不合法清单在两种主机上都先报清单错误，不会被说成「平台不支持」
- `Sources/SupervimCore` 不能导入 AppKit 等系统界面或事件框架
- 任务文件的 15 个编号和批准依赖必须一致，并且无环

`#if false` 里的 `import AppKit` 已从最终源码删除。删除之后边界测试通过。

## Linux 上额外跑过的命令

`scripts/assemble-app.sh` 退出码 0，生成了 `build/Supervim.app`，并把同一份 Info.plist 复制进去。`LSUIElement` 这一行在文件里是 `<true/>`。脚本里的 `PlistBuddy` 检查只在 Darwin 上运行，这里没有跑到。

直接执行包内二进制，退出码 1，标准错误是：

```text
Supervim is a macOS 13+ menu-bar app and cannot run on this platform.
```

这只说明 Linux 分支会拒绝运行。它不是菜单栏，也没有隐藏 Dock。

## 没有测的东西

- 没有在 macOS 上编译或运行 AppKit 菜单栏占位程序
- 没有看到 Dock 图标是否出现
- 没有 `open build/Supervim.app`
- 没有辅助功能、输入监控、事件钩子
- 没有测量 CPU、内存、`f` 的延迟或控件覆盖率
- 没有 DMG，没有签名
- `unsupportedPlatform` 这条分支在 Linux 的单元测试里跑过；`currentHost() == .macOS` 要等 macOS CI 才会执行到编译期的 Mac 分支
- 属性列表布尔值和整数的区分，只在 Linux 的 Foundation 上通过了测试。Apple 的 Foundation 如果用了不同的 `objCType`，要看 macOS CI 的同一组测试

## 和批准计划的差别

没有改行为要求。工程上多出来的、规格没写死的选择：

- Bundle identifier 暂用 `com.lijigang.supervim`
- 应用包用 SPM 加组装脚本，而不是 Xcode 工程
- 占位菜单不显示模式名
- 任务状态被测试锁住，下一步改状态时要一起改测试
