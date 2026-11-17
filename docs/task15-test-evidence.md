# 任务 15 测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu 24.04，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），解到 `/tmp/swift-install/swift-6.4.2-RELEASE-ubuntu24.04`
- 没有 macOS，没有 Xcode，没有 AppKit，没有 ServiceManagement，没有 `create-dmg`，没有 `hdiutil`

因此下面能证明的是登录项偏好如何变成注册或注销、失败时不假装已经改过，以及 Info.plist、打包脚本和两个工作流的文本契约。不能证明 `SMAppService.mainApp` 在真机上的返回值，也不能证明 DMG 真的能挂载。macOS 上的编译、同一组测试、覆盖率，以及 CI 里的 `create-dmg` 和 `hdiutil` 冒烟，交给 GitHub Actions。写本文时那次 CI 还没有结果。

## 范围

加了 `SupervimCore` 里的 `LoginItemRegistration`。它根据注入的登录项状态，按 `Settings.launchAtLogin` 决定注册、注销，还是什么都不做。`LoginItemControlling` 可替换。macOS 上的 `SMAppService.mainApp` 放在 `SupervimSystem/MainAppLoginItemController.swift`，整段包在 `canImport(ServiceManagement)` 里。菜单进程在启动时，以及设置里切换登录启动时，用已经保存的偏好调用它。失败时把固定英文提示写进设置窗口，进程不崩溃。

另外加了 `scripts/package-dmg.sh`、`scripts/verify-dmg.sh` 和 `.github/workflows/release.yml`。pull request 的 CI 在组装 `.app` 之后安装 `create-dmg`、打包、用 `hdiutil` 挂载检查，并把 DMG 上传为 artifact。签名只做 `codesign -s -`，没有开发者证书，也没有公证。

## 第一次运行：测试没编译过（RED）

时间：2026-11-17 08:08:36 UTC 到 08:08:42 UTC。命令：`swift test --filter 'LoginItemRegistrationTests|ReleasePackagingTests'`。当时还没有 `LoginItemRegistration.swift`。退出码 1。

构建失败，断言还没执行。日志里的结果是 `error: Build failed`。代表错误：

```text
Tests/SupervimCoreTests/LoginItemRegistrationTests.swift:139:41: error: cannot find type 'LoginItemControlling' in scope
Tests/SupervimCoreTests/LoginItemRegistrationTests.swift:140:16: error: cannot find type 'LoginItemState' in scope
```

这是缺类型，不是断言失败。随后加了一个能编译的空实现：`apply` 一律返回 `.unchanged`，`reportNotice` 忽略传入的文字。空实现不是最终行为。

## 第二次运行：断言失败（RED）

时间：2026-11-17 08:08:57 UTC 到 08:09:03 UTC。同一条命令。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'LoginItemRegistrationTests' failed at 2026-11-17 08:09:03.837
	 Executed 14 tests, with 23 failures (1 unexpected) in 0.006 (0.006) seconds
Test Suite 'ReleasePackagingTests' failed at 2026-11-17 08:09:03.838
	 Executed 6 tests, with 10 failures (3 unexpected) in 0.001 (0.001) seconds
```

那 4 个 unexpected 是文件还不存在：`MainAppLoginItemController.swift`、`scripts/package-dmg.sh`、`.github/workflows/release.yml`、`scripts/verify-dmg.sh`。代表输出：

```text
testTurningThePreferenceOnRegistersTheMainApp : XCTAssertEqual failed: ("unchanged") is not equal to ("registered")
testAFailedRegistrationDoesNotPretendTheItemChanged : XCTAssertEqual failed: ("unchanged") is not equal to ("failed("Could not update the login item. Move Supervim into Applications and open it from there.")")
testFailureNoticeCanBeShownInTheSettingsEditor : XCTAssertEqual failed: ("") is not equal to ("Could not update the login item. Move Supervim into Applications and open it from there.")
testAppAppliesTheSavedPreferenceWithoutNamingTheSystemService : XCTAssertGreaterThanOrEqual failed: ("0") is less than ("2")
testAssembleScriptStampsTheReleaseVersion : XCTAssertTrue failed
testPullRequestCIPackagesMountsAndUploadsTheDMG : XCTAssertTrue failed
```

空实现一律不注册、不注销。因此「已经启用时不再注册」「等待系统批准时不再注册」「偏好关闭且本来就没有登录项时不调用注销」这三条在空实现上也会过。它们单独不能证明「该注册的会去注册」。真正先失败的是：偏好打开且尚未登记时调用注册，偏好关闭且已经登记时调用注销，登记失败时返回 Applications 提示并不把状态改成已启用，设置窗口能显示这句提示，应用在启动和切换时各调用一次，以及打包脚本和发布工作流还不存在。

`testCheckedInInfoPlistCarriesTheReleaseIdentity` 在这次就通过了。仓库里的 `Info.plist` 本来就有 `LSUIElement`、`com.lijigang.supervim`、`CFBundleShortVersionString` `0.1.0` 和 `CFBundleVersion` `1`。这条锁的是已有清单，不是新写出来的行为。

## 第三次运行：实现之后通过（GREEN）

时间：2026-11-17 08:10:27 UTC 到 08:10:32 UTC。命令：`swift test --filter 'LoginItemRegistrationTests|ReleasePackagingTests|MenuBarControllerTests|TaskGraphTests'`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'LoginItemRegistrationTests' passed at 2026-11-17 08:10:32.241
	 Executed 14 tests, with 0 failures (0 unexpected) in 0.006 (0.006) seconds
Test Suite 'ReleasePackagingTests' passed at 2026-11-17 08:10:32.357
	 Executed 6 tests, with 0 failures (0 unexpected) in 0.102 (0.102) seconds
Test Suite 'MenuBarControllerTests' passed at 2026-11-17 08:10:32.254
	 Executed 15 tests, with 0 failures (0 unexpected) in 0.013 (0.013) seconds
```

这一轮还没有把任务 15 改成 `done`。状态文件和 `TaskGraphTests` 是在这次通过之后一起改的。任务 1 到 14 保持 `done`。

## 第四次运行：状态改成 done 之后再测，并量覆盖率

时间：2026-11-17 08:11:05 UTC 到 08:11:17 UTC。命令：`scripts/login-item-coverage.sh`。退出码 0。构建日志里没有编译警告。脚本里面会再跑一次 `swift test --enable-code-coverage`。

系统测试 221 个，核心测试 376 个，合计 597 个 XCTest，0 失败。其中 `LoginItemRegistrationTests` 14 个，`ReleasePackagingTests` 6 个。Swift Testing 仍是 0。

```text
binary: .build/out/Products/Debug-linux-x86_64/SupervimCoreTests.so
LoginItemRegistration.swift line coverage: 100.00% (30/30)
LoginItemRegistration.swift region coverage: 100.00% (17/17)
LoginItemRegistration.swift function coverage: 100.00% (2/2)
```

同一份改动上再跑 `scripts/menu-bar-coverage.sh`。时间：2026-11-17 08:12:08 UTC 到 08:12:14 UTC。退出码 0。没有编译警告。系统测试仍是 221 个，核心测试仍是 376 个，0 失败。`TaskGraphTests` 在任务 15 已是 `done` 的状态下通过。

```text
MenuBarController.swift line coverage: 99.44% (179/180)
MenuBarController.swift region coverage: 98.39% (61/62)
MenuBarController.swift function coverage: 100.00% (23/23)
```

这仍是 Linux 数字。macOS 上 `MainAppLoginItemController.swift` 能编过，以及 CI 里的 DMG 冒烟，看这次 pull request 的 `macos-latest` 运行。

## 登录项在做什么

| 已保存的偏好 | 当前状态 | 结果 |
| --- | --- | --- |
| 打开 | 未登记，或系统找不到这个包 | 调用注册。成功是 `.registered` |
| 打开 | 已经启用，或正在等用户批准 | 不再调用注册 |
| 关闭 | 已启用，或正在等批准 | 调用注销 |
| 关闭 | 未登记，或找不到包 | 不再调用注销 |
| 打开或关闭 | 对应的调用抛错 | `.failed`，提示把应用放进 Applications。状态不被改成已经成功 |

菜单进程在 `applicationDidFinishLaunching` 和设置开关里各读一次已经保存的偏好。保存失败时，解释器里的旧值还在，登记按旧值来。应用目标的源码里没有 `SMAppService` 这几个字；现有测试禁止菜单目标直接写这个符号。

## 交给所有者看的决定

规格第 11 条要求用 DMG 拖进「应用程序」，登录启动是可选项。任务说明要求按 tag 和手动输入的版本号发布未签名 DMG，并用 `SMAppService.mainApp` 按设置里的布尔值注册或注销。没有写窗口坐标、失败文案，也没有保证未签名的包一定能登记成功。没有改规格正文。

1. **判断放在 `LoginItemRegistration`，真实调用放在 `MainAppLoginItemController`。** 核心不导入 ServiceManagement。测试注入 `LoginItemControlling`。适配器整段在 `canImport(ServiceManagement)` 里，Linux 编译不到。
2. **已经匹配的状态不再调用。** `requiresApproval` 算已经提交，偏好仍为打开时不再 `register()`。偏好关掉时，启用和等待批准都会 `unregister()`。未登记时不调用 `unregister()`，避免系统对「本来就没有」抛错。
3. **找不到包时仍然尝试注册。** `notFound` 常见于应用还不在「应用程序」文件夹。失败变成固定英文提示，和现有设置窗口的语言一致。进程不崩溃，也不把偏好改回关闭。
4. **启动时和切换开关时都按已保存的值登记。** 菜单控制器仍然只负责保存布尔值。`reportNotice` 只在登记失败时写入提示。
5. **DMG 用 `create-dmg --app-drop-link`。** 这会在映像里放一个指向 `/Applications` 的符号链接。窗口 640×400、图标放在 160 和 480，是没有经过所有者确认的布局。
6. **ad-hoc 签名写在打包脚本里：`codesign --force -s -`。** 签的是放进映像之前的那一份副本。没有开发者证书，也没有公证。README 仍把它称为未签名发布物。
7. **版本号只在传入 `assemble-app.sh release <版本>` 时改写副本。** 仓库里的清单保持 `0.1.0` 和构建号 `1`。发布工作流把 tag `v0.1.0` 或手动输入的 `0.1.0` 写成短版本号和构建版本号。
8. **Release 工作流用 `GITHUB_TOKEN`，`permissions: contents: write`。** 触发是推送 `v*` tag，以及 `workflow_dispatch` 的 `version` 输入。手动运行如果创建了还不存在的 tag，随后的 tag 工作流看到 Release 里已经有同名 DMG 就跳过，避免再构建一次，也不会循环。pull request 的 CI 仍然是 `contents: read`，只上传 artifact，不创建 Release。
9. **200ms、90% 界面覆盖率、不吞字、真机热键、免重启和登录项登记保持未测。** 步骤和期望写在 `docs/manual-acceptance.md`。没有改规格。

## 没有测的东西

- 没有在这台 Linux 机器上编译或运行 AppKit 或 ServiceManagement
- 没有调用真实的 `SMAppService.mainApp.register()` 或 `unregister()`
- 没有生成 DMG，也没有用 `hdiutil` 挂载
- 没有把应用拖进「应用程序」，也没有看过登录项面板
- 没有验证授权之后不退出重开就能生效。这一点保持未验证
- 没有测量 Safari、Finder、系统设置里 `f` 的 200ms，也没有测量按钮和链接的 90% 覆盖率
- 微信、备忘录、Safari 地址栏里输入时字符不被吞掉：未测
- 没有在真机上按过 `Ctrl+Option+V`。这一项仍然不能标成通过
- 没有测量空闲 CPU 或内存
