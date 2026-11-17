# 任务 12 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），官方 Ubuntu 24.04 工具链在 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`
- 没有 macOS，没有 Xcode，没有 AppKit

因此下面能证明的是帮助文案、开关，以及接到任务 11 会话之后的先失败、后通过，还有 Linux 上 `HelpSheet.swift` 和 `HelpOverlay.swift` 的覆盖率。不能证明面板真的出现在屏幕上，也不能证明它没有抢走焦点。macOS 上的编译、同一组测试和覆盖率交给 GitHub Actions。

## 范围

加了 `SupervimCore` 里的 `HelpSheet`，以及 `SupervimSystem` 里的 `HelpController`。macOS 上的 `NonActivatingHintPanel` 增加了帮助文字，整段仍在 `#if canImport(AppKit)` 里。Linux 上那个文件没有类型。

任务 11 已经合入 `cdfe799`。`HelpCommandHandling` 留在 `NormalCommandSession.swift`，这里没有再声明一份。`HelpController` 实现 `claimHelp()`、`dismissHelp(for:)` 和 `yieldHelp()`。`MenuHookAssembly` 用同一块面板创建 `HintController` 和 `HelpController`，并把帮助交给会话。

没有改 CommandMap 的行，也没有改任务 11、14 的状态。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 07:39 UTC 前后。命令：`swift test --filter 'HelpSheetTests|HelpOverlayTests'`。当时还没有 `HelpSheet.swift`，也没有 `HelpOverlay.swift`。退出码 1。

构建失败，断言还没执行。代表错误：

```text
Tests/SupervimCoreTests/HelpSheetTests.swift:8:20: error: cannot find 'HelpPage' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：页面没有行；`show`、`hide`、`handle` 永远是 `unchanged`；`claimHelp` 返回 false，也不调用 presenter。空实现不是最终行为。

有一条测试用 `entries[0]` 读空数组，进程收到信号 4，整组停掉。这是测试在空结果上崩了，不是帮助行为。改成 `first?` 之后再跑。期望值没有放宽。

## 第二次运行：断言失败（RED）

时间：2026-11-17 07:40:14 UTC 到 07:40:30 UTC。

`HelpOverlayTests` 先跑。退出码 1。12 个测试，22 次断言失败，0 次 unexpected。

`HelpSheetTests` 随后跑。退出码 1。15 个测试，30 次断言失败，0 次 unexpected。构建日志里没有编译警告。

失败原因是空实现不生成命令行、不打开帮助、不关闭帮助。不是拼写错误。代表输出：

```text
testDefaultActionTextMatchesTheMap : XCTAssertEqual failed: ("[]") is not equal to ("["j", "k", "h", "l", "d", "u", "gg", "G", "gi", "Ctrl+]", "H", "L", "J", "K", "x", "t", "r", "/", "yy", "f", "F", "?", "i", "Esc"]")
testQuestionMarkOpensAndTheNextQuestionMarkCloses : failed - ? should open help
testShowPresentsTheCommandMapWithoutActivating : failed - showHelp should present the page
testClaimHelpTogglesAndConsumesTheQuestionMark : XCTAssertTrue failed
testPanelSourceDrawsHelpWithoutActivatingOrLogging : XCTAssertTrue failed
```

有 4 个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testSheetSourceDoesNotTouchTheSystemOrRecordKeys`：空的 `HelpSheet.swift` 本来就没有系统导入
- `testControllerSourceDoesNotLogOrUseTheNetwork`：空的 `HelpOverlay.swift` 已经写了 `claimHelp()`，也没有日志或网络
- `testMenuProcessDoesNotInstallHelp`：菜单源文件本来就没有帮助类型
- `testPassedThroughQuestionMarkAndHintKeysDoNotOpenHelp`：空实现的 `respond` 本来就返回 `unchanged`

真正先失败的是命令表文案、`/` 的 `Command+F`、偏离标记、`?` 开关、Esc 关闭，以及面板源文件里的 `presentHelp`。实现之后这 4 个本来就通过的测试仍然通过，它们单独不能证明帮助是对的。

控制器实现之后，上面这两组测试通过。时间：2026-11-17 07:41:26 UTC 到 07:41:31 UTC。`HelpSheetTests` 15 个、`HelpOverlayTests` 12 个，0 失败。没有编译警告。这一轮还没有接到会话，也没有把任务 12 改成 `done`。

## 变基到任务 11 之后：接线失败（RED）

`origin/main` 在 `cdfe799` 合入了任务 11。本分支快进到那次提交。任务 11 仍是 `done`。

任务 11 的 `HelpCommandHandling` 只有 `claimHelp()`。没人认领时 `?` 放过。接线测试加在已经通过的控制器测试后面。时间：2026-11-17 07:44:57 UTC 到 07:45:04 UTC。命令仍是 `swift test --filter 'HelpSheetTests|HelpOverlayTests'`。退出码 1。

`HelpOverlayTests` 15 个测试，13 次断言失败，0 次 unexpected。`HelpSheetTests` 15 个仍然通过。失败集中在 3 个新测试。代表输出：

```text
testSessionClaimsQuestionMarkAndEscapeClosesTheSheet : XCTAssertEqual failed: ("passThrough") is not equal to ("swallow")
testStartingAHintHidesHelpOnTheSharedPanel : XCTAssertFalse failed
testAppAssemblyClaimsHelpOnOneNonActivatingPanel : XCTAssertTrue failed
```

第一次 `?` 和第二次 `?` 已经能通过会话吞掉，因为 `claimHelp()` 会切换。失败的是 Esc 仍被放过、开始 Hint 时帮助还开着，以及 `MacHookAssembly` 还没有 `HelpController`。

## 第三次运行：接线之后通过（GREEN）

时间：2026-11-17 07:45:38 UTC。命令：`swift test --filter 'HelpSheetTests|HelpOverlayTests|SupervimRuntimeTests|NormalCommandSessionTests|HintOverlayTests'`。退出码 0。没有编译警告。

```text
HelpOverlayTests: 15 tests, 0 failures
HintOverlayTests: 30 tests, 0 failures
NormalCommandSessionTests: 22 tests, 0 failures
SupervimRuntimeTests: 12 tests, 0 failures
HelpSheetTests: 15 tests, 0 failures
```

## 第四次运行：全量测试和覆盖率

时间：2026-11-17 07:46:23 UTC 到 07:46:36 UTC。命令：`scripts/help-overlay-coverage.sh`。退出码 0。构建日志里没有编译警告。

脚本里面会再跑一次 `swift test --enable-code-coverage`。系统测试 220 个，核心测试 332 个，合计 552 个 XCTest，0 失败。Swift Testing 库对两个测试目标各报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

同一轮 llvm-cov 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
HelpSheet.swift line coverage: 100.00% (175/175)
HelpSheet.swift region coverage: 100.00% (88/88)
HelpSheet.swift function coverage: 100.00% (20/20)
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
HelpOverlay.swift line coverage: 100.00% (85/85)
HelpOverlay.swift region coverage: 100.00% (33/33)
HelpOverlay.swift function coverage: 100.00% (16/16)
```

这一轮结束时，状态文件里的 `updated` 曾改成 `2026-11-17T07:46:36.000Z`。当时只改了任务 12 的状态和这份元数据。任务 11 保持 `done`。任务 14 当时还在并行，后来合入 main，变基时改成 `done`，`updated` 再改成 `2026-11-17T07:52:36.000Z`。

随后再跑 `scripts/command-session-coverage.sh`，因为会话多了 Esc 和 `yieldHelp`。退出码 0。`NormalCommandSession.swift` 行覆盖率 94.00%（188/200），仍不低于 90%。`CommandFollowThrough.swift` 98.97%（96/97），`ScrollAreaCatalog.swift` 96.10%（197/205），`SupervimRuntime.swift` 100.00%（40/40）。

## 帮助在做什么

| 输入 | 结果 |
| --- | --- |
| 普通模式第一次 `?` | 打开帮助，吞掉这一键。文案按 CommandMap 的顺序 |
| 再按 `?` | 关闭帮助，吞掉这一键 |
| 帮助开着时按 Esc | 只在普通模式关闭并吞掉。Hint、Insert 的 Esc 仍交给原来的路径 |
| 帮助关着时按 Esc | 放过 |
| 帮助开着时按 `f` / `F` | 先收起帮助，再显示标签。`f` 不被帮助吞掉 |
| 插入模式或 Hint 里的 `?` | 不打开帮助 |
| 其他命令 | 帮助保持打开，这一键不由帮助层吞掉 |

`/` 的行是 `Find with the app shortcut`，动作文字是 `Command+F`，并带 `differs from Vimium`。偏离的键只有 `/`、`F`、`?`。`yy` 的行包含 `Command+L, Command+C`，以及 `Safari, Chromium`。

窗口策略沿用标签浮层：透明、不激活、忽略鼠标。面板用原来的 `.nonactivatingPanel` 和 `orderFrontRegardless()`。

## 交给所有者看的决定

规格写了 `?` 打开、再按 `?` 或 Esc 关闭，内容来自命令表，偏离要能读到，并且不记日志、不联网。没有写帮助句子的英文格式、Esc 在 Hint 或 Insert 里归谁，以及帮助和标签是不是同一块面板。选择按已合并的 CommandMap、任务 10 的不激活面板，以及任务 11 的 `HelpCommandHandling`。没有改规格正文。

1. **文案在 `HelpSheet.swift`，显示在 `HelpOverlay.swift`。** 面板绘制仍在 `HintOverlayWindow.swift`，用 `#if canImport(AppKit)` 包住。
2. **不另写一份 `HelpCommandHandling`。** 协议留在任务 11 的会话文件里。`claimHelp()` 切换并返回 true。返回 false 或 handler 为 nil 时，`?` 仍放过。
3. **动作文字用 `Command+F`，不用 `Cmd+F`。** 修饰键顺序是 Command、Shift、Option、Control。字母写成大写。`/` 因此读成 `Command+F`。
4. **偏离标记是字面量 `differs from Vimium`。** 只跟 CommandMap 里 `deviatesFromVimium == true` 的三行：`/`、`F`、`?`。
5. **帮助和标签共用一块 `NonActivatingHintPanel`。** `MenuHookAssembly` 只构造一次面板。开始 Hint 时调用 `yieldHelp()`，避免帮助还占着这块面板。
6. **Esc 只在普通模式关闭帮助。** Hint 的 Esc 仍取消标签，Insert 的 Esc 仍离开插入。帮助关着时，普通模式的 Esc 继续放过。
7. **其他键不关闭帮助，也不由帮助层吞掉。** 滚动和快捷键仍走任务 11。
8. **菜单源文件不直接写 `HelpController`。** 应用入口仍调用 `MenuHookAssembly.make`，帮助在那个组装函数里接上。
9. **运行路径没有 `print`、`Logger`、`NSLog` 或 `URLSession`。** 按键不记日志，也不发到网络。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit
- 没有在屏幕上看到帮助，也没有检查它是否真的不抢焦点
- 没有测量帮助文字在主屏幕上是否居中，也没有把坐标和标签的辅助功能坐标对过
- 没有用真键盘确认 Esc 的虚拟键 `0x35`
- 没有在 Safari、Finder 或系统设置里打开帮助
- 微信、备忘录和 Safari 地址栏的不吞字不属于这次测量

## 变基到任务 14

`origin/main` 在 `4fed5c8` 合入了任务 14。本分支变基到那次提交。任务 14 保持 `done`，只把任务 12 标成 `done`。任务 15 仍是 `pending`。

权限引导没有换掉 `MenuHookAssembly`。两项权限都授予之后，启动仍调用这个组装函数，帮助还在会话的 `help` 上。缺权限时不安装钩子，因此也不会打开帮助。

冲突只在 CI、README、`tasks.json` 和 `docs/tasks.md` 的状态说明。覆盖率脚本同时保留任务 14 的权限引导和任务 12 的帮助，一共十三个。

变基后再跑 `swift test --filter 'HelpSheetTests|HelpOverlayTests|TaskGraphTests|PermissionGuideTests|PermissionAccessTests|SupervimRuntimeTests'`。时间：2026-11-17 07:52:31 UTC 到 07:52:36 UTC。退出码 0。没有编译警告。`HelpSheetTests` 15 个、`HelpOverlayTests` 15 个、`PermissionGuideTests` 24 个、`SupervimRuntimeTests` 12 个、`TaskGraphTests` 1 个，0 失败。帮助源文件没有再改，上面的覆盖率仍然是变基前那一轮的数字。
