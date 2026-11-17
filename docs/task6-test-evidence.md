# 任务 6 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04.5 LTS，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），本机原先没有 Swift，这次用官方 Ubuntu 24.04 工具链解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`，只为了跑纯逻辑测试
- 没有 macOS，没有 Xcode，没有 AppKit

因此下面能证明的是 Settings 的先失败、后通过，以及 Linux 上 `Settings.swift` 和 `UserDefaultsSettingsStore.swift` 的覆盖率。不能证明登录项真的注册了，也不能证明前台应用会被放过。那是任务 13 和任务 7。macOS 上的同一组测试和覆盖率交给 GitHub Actions。第一次 macOS 运行失败了，原因和改名见文末。改名之后的那次 macOS 运行，以 PR 上的检查状态为准。

## 范围

加了 `SupervimCore` 里的设置模型，以及 `SupervimSystem` 里的 UserDefaults 适配器。没有改 KeyParser、ModeMachine、HintLabeler、CommandMap，也没有改菜单栏占位程序。`Sources/SupervimCore` 仍然不导入 AppKit 或其他系统界面、事件框架；原有的边界测试在通过的那一轮里仍然通过。

模型保存排除列表、暂停状态、暂停快捷键、按键序列超时和登录启动偏好。登录启动只是一个布尔值。真正的登录项注册不在这里。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 05:51:59 UTC 到 05:52:05 UTC。命令：`swift test --filter 'SettingsTests|UserDefaultsSettingsStoreTests'`。当时还没有 `Settings.swift`，也没有 `UserDefaultsSettingsStore.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/SettingsTests.swift:668:44: error: cannot find type 'SettingsStore' in scope
Tests/SupervimCoreTests/SettingsTests.swift:691:43: error: cannot find type 'Settings' in scope
Tests/SupervimCoreTests/SettingsTests.swift:697:17: error: cannot find type 'SettingsError' in scope
Tests/SupervimCoreTests/SettingsTests.swift:720:45: error: cannot find type 'PauseShortcut' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：`load` 不读存储，永远返回一份错误的默认值（暂停、登录启动为真，排除列表为空，超时为 0，暂停键是没有修饰键的 `x`）；`save` 什么都不写；`isExcluded` 永远返回 false；两个 store 的 `read` 永远返回 nil。空实现不是最终行为。

空实现的第一次编译没有跑到断言。系统测试用了 `repoRoot()`，那个函数当时只在核心测试目标里。退出码 1。时间：2026-11-17 05:52:40 UTC 到 05:52:43 UTC。

```text
Tests/SupervimSystemTests/UserDefaultsSettingsStoreTests.swift:133:19: error: cannot find 'repoRoot' in scope
```

同一轮核心测试还有一条警告：`testValueCopiesDoNotShareLaterEdits` 里的 `original` 没有被修改。这是测试代码的问题，不是产品行为失败。随后在系统测试里补了一份同样的 `repoRoot()`，并把 `original` 改成 `let`。断言的期望值没有放宽。

## 第二次运行：断言失败（RED）

时间：2026-11-17 05:52:54 UTC 到 05:52:58 UTC。命令：`swift test --filter 'SettingsTests|UserDefaultsSettingsStoreTests'`。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'UserDefaultsSettingsStoreTests' failed at 2026-11-17 05:52:58.412
	 Executed 10 tests, with 14 failures (0 unexpected) in 0.005 (0.005) seconds
Test Suite 'SettingsTests' failed at 2026-11-17 05:52:58.433
	 Executed 36 tests, with 157 failures (0 unexpected) in 0.01 (0.01) seconds
```

46 个测试里 39 个失败，171 次断言失败。失败原因是空实现不给出默认排除列表、不保存、也不拒绝坏文档，不是拼写错误。代表输出：

```text
testDefaultsMatchTheApprovedInitialState : XCTAssertEqual failed: ("[]") is not equal to ("["com.apple.Terminal", "com.googlecode.iterm2", "org.gnu.Emacs"]")
testDefaultTimeoutMatchesTheKeyParser : XCTAssertEqual failed: ("0") is not equal to ("1000")
testDefaultsExcludeTheThreeNamedAppsByBundleIdentifier : XCTAssertTrue failed
testPauseShortcutDefaultIsControlOptionVAndMatchesExactly : XCTAssertEqual failed: ("x") is not equal to ("v")
testLegacyApplicationNamesMigrateToBundleIdentifiersAndArePersisted : XCTAssertEqual failed: ("[]") is not equal to ("["com.apple.Terminal", "com.googlecode.iterm2", "org.gnu.Emacs"]")
testFutureSchemaIsLeftUntouched : XCTAssertThrowsError failed: did not throw error
testWriteThenReadRoundTripsBytes : XCTAssertEqual failed: ("nil") is not equal to ("Optional(14 bytes)")
testApplicationIdentifiersStayOffTheStandardDomain : XCTAssertEqual failed: ("") is not equal to ("com.lijigang.supervim")
```

有七个测试在空实现上直接通过，不能当作「测试先抓住了错误」的证据：

- `testFreshStoreLoadsDefaultsWithoutWriting`：空实现的 `load` 本来就返回它自己的 `Settings.defaults`，`read` 本来就返回 nil。这个测试不检查默认值的内容
- `testLegacyEmptyExclusionListDoesNotGrowTheDefaults`：空实现忽略文档，而它的默认排除列表本来就是空的
- `testValueCopiesDoNotShareLaterEdits`：结构体的副本本来就不会写回原来那份
- `testSettingsSourcesDoNotTouchTheNetworkLoginItemsOrUserDefaults`：空文件里没有这些调用
- `testMissingKeyReadsNil`：空实现的 `read` 本来就返回 nil
- `testSeparateSuitesAreIsolated`：空实现的 `load` 总是返回同一份默认值，第二个 store 的 `read` 也是 nil。它没有证明写进一个套件不会出现在另一个套件
- `testAdapterSourceDoesNotRegisterLoginItemsOrImportAppKit`：空文件里没有这些调用

真正先失败的是三份默认 bundle id、暂停快捷键、超时、迁移、校验、写回，以及适配器的字节往返。实现之后这七个本来就通过的测试仍然通过，它们单独不能证明设置是对的。

这一轮的 `testLegacyRejectsABlankNameAndAReversedHotkeyWithoutWriting` 还没有检查「暂停热键写成整数」。那个断言是在这次失败之后、实现通过之前加到同一个测试里的。空实现的 `load` 不会抛错，所以这一下也会失败；红灯日志里没有这一行。

## 第三次运行：实现之后先有两条源码扫描失败，再通过（GREEN）

时间：2026-11-17 05:56:09 UTC 到 05:56:14 UTC。命令：`swift test --filter 'SettingsTests|UserDefaultsSettingsStoreTests'`。退出码 1。

行为测试已经通过。失败的是两条源码扫描，因为注释里写了它们要禁止的词：

```text
Test Suite 'UserDefaultsSettingsStoreTests' failed
	 Executed 10 tests, with 1 failure (0 unexpected) in 0.006 (0.006) seconds
Test Suite 'SettingsTests' failed
	 Executed 36 tests, with 1 failure (0 unexpected) in 0.526 (0.526) seconds
testAdapterSourceDoesNotRegisterLoginItemsOrImportAppKit : XCTAssertFalse failed - UserDefaults.standard
testSettingsSourcesDoNotTouchTheNetworkLoginItemsOrUserDefaults : XCTAssertFalse failed - UserDefaults
```

随后只改了这两处注释的用词，没有改校验和存储行为。

时间：2026-11-17 05:56:25 UTC 到 05:56:28 UTC。同一条命令。退出码 0。构建日志里没有编译警告。`Build complete!` 在 05:56:28 UTC 之前，测试从 05:56:28.638 开始。

```text
Test Suite 'UserDefaultsSettingsStoreTests' passed at 2026-11-17 05:56:28.646
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.006 (0.006) seconds
Test Suite 'SettingsTests' passed at 2026-11-17 05:56:28.787
	 Executed 36 tests, with 0 failures (0 unexpected) in 0.126 (0.126) seconds
```

这一轮还没有把任务 6 改成 `done`。状态文件和 `TaskGraphTests` 是之后一起改的。

## 第四次运行：状态更新之后再测，并量覆盖率

时间：2026-11-17 05:57:14 UTC 到 05:57:20 UTC。命令：`scripts/settings-coverage.sh`。退出码 0。构建日志里没有编译警告。

脚本里面会再跑一次 `swift test --enable-code-coverage`。`MenuBarPreflightTests` 5 个、`UserDefaultsSettingsStoreTests` 10 个、`SupervimCoreTests` 225 个（含 `SettingsTests` 36 个、`CommandMapTests` 32 个、`HintLabelerTests` 41 个、`KeyParserTests` 36 个、`ModeMachineTests` 61 个、`MenuBarManifestTests` 18 个，以及已经改成任务 6 `done` 的 `TaskGraphTests`）全部通过，0 失败。合计 240 个 XCTest。Swift Testing 库另外报告了 0 个测试。本包只用 XCTest，这个 0 不是失败。

同一轮 llvm-cov 的结果：

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
Settings.swift line coverage: 100.00% (391/391)
Settings.swift region coverage: 100.00% (216/216)
Settings.swift function coverage: 100.00% (53/53)
binary: .build/out/Products/Debug-linux-x86_64/SupervimSystemTests.so
UserDefaultsSettingsStore.swift line coverage: 100.00% (16/16)
UserDefaultsSettingsStore.swift region coverage: 100.00% (7/7)
UserDefaultsSettingsStore.swift function coverage: 100.00% (3/3)
```

这是 Linux 上的数字。macOS CI 会再跑同一个脚本。两边的区域计数可能不同；以 CI 日志里的那一行为 macOS 结果。写本文时 CI 还没有跑完。

状态文件里的 `updated` 时间在这一轮之后改成 `2026-11-17T05:57:20.000Z`。只改了这一处元数据。随后单独再跑 `swift test --filter TaskGraphTests`（2026-11-17 05:58:00 UTC 到 05:58:04 UTC），1 个测试通过。`Settings.swift` 没有再改，所以上面的覆盖率仍然是这一轮的数字。

## 给任务 7 和任务 13 用的值

`Settings` 是值类型。改一份副本不会改到原来那份，也不会自动写盘。`SettingsRepository` 通过 `SettingsStore` 读写一份属性列表。测试用 `InMemorySettingsStore`。菜单以后应使用 `UserDefaultsSettingsStore`，并且传入名为 `com.lijigang.supervim` 的套件，键名是 `com.lijigang.supervim.settings`。适配器不会自己去打开标准偏好域。

| 入口 | 作用 |
| --- | --- |
| `Settings.defaults` | 未暂停，不登录启动，超时 1000 毫秒，暂停键是 Ctrl+Option+V，排除下面三个 bundle id |
| `settings.isExcluded(bundleIdentifier:)` | 这个前台应用要不要完全放过 |
| `settings.isPaused` | 保存的暂停状态。任务 13 再交给 ModeMachine |
| `settings.pauseShortcut.matches(_:)` | 这一键是不是保存的暂停快捷键。默认只匹配 `v` 加上 Control 和 Option |
| `settings.keySequenceTimeoutMilliseconds` | 任务 7 传给 `KeyParser` 的前缀超时。本任务不改 KeyParser |
| `settings.launchAtLogin` | 只是偏好。本任务不注册登录项 |
| `SettingsRepository.load()` / `save(_:)` | 读出或写回。缺文档时用默认值，并且不创建文档 |

默认排除，顺序固定：

| 规格里的名字 | 采用的 bundle id | 是否经过所有者确认 |
| --- | --- | --- |
| Terminal | `com.apple.Terminal` | 否 |
| iTerm | `com.googlecode.iterm2` | 否。现成的应用是 iTerm2 |
| Emacs | `org.gnu.Emacs` | 否。不是 Aquamacs 的 `org.gnu.Aquamacs` |

比较时先去掉两端空白，再按大小写精确匹配。`com.apple.terminal` 不算 Terminal。

空白的 bundle id 算作排除。读不到前台应用时，调用方应传入空字符串。这样不会因为不知道是谁就吞键。

文档是版本 1 的属性列表，字段只有：`schemaVersion`、`paused`、`excludedBundleIdentifiers`、`launchAtLogin`、`keySequenceTimeoutMilliseconds`、`pauseShortcut`。`pauseShortcut` 里是 `key` 和 `modifiers`。修饰键按 control、option、command、shift 这个顺序写。布尔值必须是布尔，整数必须是整数；`<integer>1</integer>` 不是真。

没有保存过时，`load` 返回默认值，存储保持为空。版本 1 少了某个键时，内存里用默认值，不把文件改写。排除列表这个键如果存在而且是空数组，就保持为空，不会补回 Terminal、iTerm、Emacs。超时必须在 1 到 60000 毫秒之间，含两端。暂停键必须是一个非空白、非控制字符，并且带有 Control、Option 或 Command 里的至少一个。只有 Shift 不算。

没有 `schemaVersion` 的旧文档，以及 `schemaVersion` 为 0 的文档，会迁到版本 1 并写回去。旧的 `excludedApplications` 接受应用名或 bundle id。`Terminal`、`iTerm`、`iTerm2`、`Emacs` 不区分大小写，映射到上表。带点的字符串当作 bundle id，不改大小写，所以 `COM.APPLE.TERMINAL` 会原样留下。同一个 id 在旧文档里出现多次时只留第一次。旧的 `pauseHotkey` 只接受 `ctrl+option+v` 和 `control+option+v`。版本大于 1 的文档直接拒绝，原字节不动。版本 1 里不认识的字段也拒绝，不会悄悄丢掉。

## 交给所有者看的决定

规格没有写 bundle id，也没有写设置文档的形状。选择按 Vimium 的排除思路（对上了就不处理按键）和宪法第 2 条（不确定就放过）。没有改规格正文。

1. **三个 bundle id 是未确认的选择。** 见上表。规格只给了应用名。iTerm 对到 iTerm2 的 `com.googlecode.iterm2`。Emacs 对到 `org.gnu.Emacs`，不包含 Aquamacs。
2. **暂停状态要保存，默认不暂停。** 计划里的设置条目写了排除列表、暂停快捷键和登录启动，没有写这个布尔值。菜单栏要显示 Paused。如果用户已经暂停，下次启动又开始拦截，比漏掉快捷键更打扰。任务 13 才把这个值交给 ModeMachine。
3. **按键序列超时要保存，默认 1000 毫秒。** 这和 KeyParser 现有的默认值相同。计划没有把它列进设置。本任务不改 KeyParser；任务 7 把 `keySequenceTimeoutMilliseconds` 传进去。允许的范围是 1 到 60000 毫秒。0 和负数会立刻或异常地取消前缀，超过一分钟的损坏值会把快捷键卡住。这个上限规格没写。
4. **空白 bundle id 视为排除。** `isExcluded` 回答的是「要不要完全不碰这个前台应用」。名字都读不到时，把它当成排除，避免吞掉未知应用的键。大小写敏感。两端空白会去掉。
5. **空的排除列表是用户的选择。** 键不存在才用三份默认值。键存在而且是 `[]` 就谁也不排除，空白 id 仍然排除。
6. **旧文档用应用名，版本 1 只用 bundle id。** 没有版本号或版本为 0 时，`Terminal` / `iTerm` / `iTerm2` / `Emacs` 映射成上表。带点的字符串必须是合法 bundle id，并且保留原来的大小写。旧文档里的重复 id 合并。版本 1 里的重复 id 拒绝，避免用户以为两行都保存了。迁移成功才写回版本 1。写回失败时旧字节保持不动。版本 1 缺键不写回，这样以后如果默认列表变了，还没改过这一项的人会看到新默认值。
7. **暂停快捷键存成「基本键 + 修饰键」，不是一串显示文字。** 默认是 `v` 加上 Control 和 Option，没有 Shift。不把 `V` 折成 `v`。匹配必须修饰键完全一致，多一个 Shift 或少一个 Option 都不算。只有 Shift、或者没有任何 Control / Option / Command 的组合会拒绝，避免把普通打字键当成全局暂停。存储用的修饰键名字是 `control`、`option`、`command`、`shift`。`alt` 和 `ctrl` 不接受。旧文档里的热键字符串只接受 `ctrl+option+v` 和 `control+option+v`。自定义全部按键仍然不在初始范围内；这里只保存这一个快捷键，因为任务要求把它写回。
8. **登录启动默认关闭，而且只保存偏好。** 规格说这是可选项。这里没有 `SMAppService`，测试也不碰本机登录项。任务 13 和任务 15 再按这个布尔值注册。
9. **一份属性列表，而不是每个字段一个偏好键。** 这样版本和迁移有一个边界。坏掉的未来版本不会被当成空设置盖掉。
10. **适配器必须由调用方传入 UserDefaults。** 它不打开标准域。应用套件名是 `com.lijigang.supervim`，文档键是 `com.lijigang.supervim.settings`。测试只用带随机后缀的临时套件，并在结束时删掉该域。套件里如果这个键不是 `Data`，就当作读失败，不把它看成「还没保存过」。
11. **内存 store 放在 SupervimCore。** 它不碰系统框架，核心测试和系统测试都能用。这和 `ManualKeyClock` 放在核心里一样。UserDefaults 适配器只放在 SupervimSystem。
12. **`yy` 的 bundle id 仍然不写进代码。** 规格的歧义说明把排除列表和 `yy` 的标识都交给任务 6 和任务 11。本任务只把排除列表的三个标识写进设置。`yy` 仍沿用任务 5：承诺的应用名是 Safari 和 Chromium，下面这些标识都没有写进代码，也没有经过所有者确认：Safari `com.apple.Safari`；Chrome `com.google.Chrome`；Chromium `org.chromium.Chromium`；Edge `com.microsoft.edgemac`；Brave `com.brave.Browser`；Arc `company.thebrowser.Browser`；Opera `com.operasoftware.Opera`；Vivaldi `com.vivaldi.Vivaldi`。「Chromium」是否包含 Chrome、Edge、Brave，留给任务 11。
13. **设置不联网，也不记录击键。** 暂停快捷键是一条配置，不是按键历史。源码扫描拒绝网络、日志和登录项注册这些调用。

## macOS CI：测试辅助函数和 XCTest 重名

第一次 macOS 运行：<https://github.com/lijigang/supervim/actions/runs/44027898745>，作业 <https://github.com/lijigang/supervim/actions/runs/44027898745/job/133852566056>。提交 `742e745`。`swift build` 之后的 Test 步骤失败，退出码 1。Linux 上同一份测试能编译，因为这台机器的 XCTest 没有把无参的 `load()` 加到测试实例上。

Apple 的 XCTest 给 `SettingsTests` 一个不带参数的实例方法 `load()`。测试文件里的自由函数 `load(_:)` 因此对不上。代表错误：

```text
Tests/SupervimCoreTests/SettingsTests.swift:266:26: error: static member 'load' cannot be used on instance of type 'SettingsTests'
Tests/SupervimCoreTests/SettingsTests.swift:266:31: error: argument passed to call that takes no arguments
Tests/SupervimCoreTests/SettingsTests.swift:271:26: error: static member 'load' cannot be used on instance of type 'SettingsTests'
Tests/SupervimCoreTests/SettingsTests.swift:376:25: error: static member 'load' cannot be used on instance of type 'SettingsTests'
Tests/SupervimCoreTests/SettingsTests.swift:408:30: error: static member 'load' cannot be used on instance of type 'SettingsTests'
Tests/SupervimCoreTests/SettingsTests.swift:482:26: error: static member 'load' cannot be used on instance of type 'SettingsTests'
Tests/SupervimCoreTests/SettingsTests.swift:487:28: error: static member 'load' cannot be used on instance of type 'SettingsTests'
```

后面的 `Any` 不能比较、`.default` 找不到、`control` 缺少类型，都是这一处解析失败带出来的，不是设置模型的行为错误。

改法只在测试里：那个辅助函数改名为 `loadSettings`。`SettingsRepository.load()` 和生产 API 没有改。调用点是 266、271、376、377、408、482、487 行。

改名之后在 Linux 上再跑 `swift test --filter SettingsTests`。时间：2026-11-17 06:01:41 UTC 到 06:01:44 UTC。退出码 0。没有编译警告。

```text
Test Suite 'SettingsTests' passed at 2026-11-17 06:01:44.210
	 Executed 36 tests, with 0 failures (0 unexpected) in 0.018 (0.018) seconds
```

这只证明 Linux 仍能编译并跑过这些断言。macOS 是否不再撞上 `load()`，看改名之后的 `macos-latest` 运行。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit
- 没有把设置接到菜单、事件钩子或 KeyParser
- 没有注册登录项，也没有读本机真实的偏好域
- 没有测量 CPU、内存或 `f` 的延迟
- 没有按 bundle id 过滤 `yy`
- 第一次 macOS CI 在测试编译阶段失败，没有跑到设置断言
