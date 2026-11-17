# 应用图标测试记录

记录日期：2026-11-17。主机是 Linux，不是 Mac。

- 系统：Ubuntu，x86_64
- Swift：6.4.2（swift-6.4.2-RELEASE），解到 `/tmp/swift-install`
- Python：3.12.3，生成图标时用了本机的 numpy 1.26.4。`--check` 只使用标准库
- 没有 macOS，没有 Xcode，没有 AppKit，没有 `iconutil`，没有 `sips`，没有 `create-dmg`，没有 `hdiutil`

因此下面能证明的是：图标几何、已提交的 PNG / icns 结构、Info.plist 的 `CFBundleIconFile`、组装脚本会把 icns 拷进包、DMG 脚本带 `--volicon`，以及 Linux 上 `swift test` 全绿。不能证明 Finder 里的圆角遮罩，也不能证明 `iconutil` 或 `create-dmg` 在 macOS 上的字节。那些交给 GitHub Actions 的 `macos-latest`。

## 范围

图标是 1024×1024 透明画布，居中一块 824×824 的连续曲率圆角方，圆角半径 185，指数 5。底色由上到下 `#F7F7F8` → `#E9E9EC`，顶部有一层很淡的白高光，方块带轻微下投影。正中是竖向实心矩形，宽 52、高 142，颜色 `#34C759`，周围一圈同色柔光。没有文字。

16、32、64 像素的版本把光标块加粗，分别是 4×9、6×16、8×22，并且 32 及以下不加柔光，避免小图糊成一团。源文件是 `Resources/AppIcon.svg` 和 `scripts/render_icon.py`。`scripts/make-icon.sh` 写出 iconset 和 icns；这台机器没有 `iconutil`，icns 由脚本按 PNG 块打包，类型覆盖 `icp4`、`ic11`、`icp5`、`ic12`、`ic07`、`ic13`、`ic08`、`ic14`、`ic09`、`ic10`。

仓库里的版本号没有改。`CFBundleShortVersionString` 仍是 `0.1.0`，`CFBundleVersion` 仍是 `1`。发布时仍由 `assemble-app.sh release <版本>` 按 tag 或手动输入改写副本。

## 第一次运行：断言失败（RED）

时间：2026-11-17 10:36:24 UTC。命令：`swift test --filter ReleasePackagingTests`。当时还没有图标文件、`scripts/make-icon.sh`，Info.plist 也没有 `CFBundleIconFile`。退出码 1。构建日志里没有编译警告。

```text
Test Suite 'ReleasePackagingTests' failed at 2026-11-17 10:36:24.427
	 Executed 14 tests, with 14 failures (2 unexpected) in 0.104 (0.104) seconds
```

那 2 个 unexpected 是文件还不存在：`Resources/AppIcon.svg`、`scripts/make-icon.sh`。代表断言：

```text
testCheckedInInfoPlistNamesTheAppIcon : XCTAssertEqual failed: ("nil") is not equal to ("Optional("AppIcon")")
testAssembleScriptInstallsTheAppIcon : XCTAssertTrue failed
testPackageScriptSetsTheVolumeIcon : XCTAssertTrue failed
testVerifyScriptChecksTheBundledAppIcon : XCTAssertTrue failed
testPullRequestCIChecksTheAssembledAppIcon : XCTAssertTrue failed
testCommittedIconFilesAreTheStandardSizes : failed - missing Resources/AppIcon-1024.png
```

已有的 6 条打包测试在这次就通过了。它们锁的是原来的版本号、`create-dmg --app-drop-link` 和 ad-hoc 签名，不是新行为。

## 第二次运行：实现之后通过（GREEN）

时间：2026-11-17 10:42:30 UTC 到 10:42:35 UTC。命令：`swift test`。退出码 0。构建日志里没有编译警告。

```text
Test Suite 'All tests' passed at 2026-11-17 10:42:33.125
	 Executed 221 tests, with 0 failures (0 unexpected) in 2.396 (2.396) seconds
Test Suite 'All tests' passed at 2026-11-17 10:42:35.632
	 Executed 384 tests, with 0 failures (0 unexpected) in 2.496 (2.496) seconds
```

系统测试 221 个，核心测试 384 个，合计 605 个 XCTest，0 失败。Swift Testing 仍是 0。核心测试比任务 15 记录的 376 多 8 个，都在 `ReleasePackagingTests`：清单里的 `CFBundleIconFile`、组装脚本、`--volicon`、挂载检查、`make-icon.sh`、CI 步骤、SVG 源图，以及 icns 里 10 个标准尺寸的 PNG 头。`ReleasePackagingTests` 这次是 14 个。

任务 15 的 Linux 记录是系统 221、核心 376，合计 597。macOS 上还多一个只在 `#if os(macOS)` 里的 `testModifierMasksMatchCoreGraphics`，所以 macOS 上原有 598 个。这次没有改那个测试，也没有改它测的 `CGEvent` 掩码。Linux 上仍然编译不到它。

## 像素检查和组装

时间：2026-11-17 10:43:23 UTC 之前。命令：`scripts/make-icon.sh --check`，然后 `scripts/assemble-app.sh`。两条都是退出码 0。

`--check` 读的是已提交的 1024 PNG 和 icns，不重新绘图。1024 图上量到的值：

| 位置 | 像素 |
| --- | --- |
| 四角 | alpha 0 |
| 光标中心 (512, 512) | 正好 `(52, 199, 89, 255)`，即 `#34C759` |
| 方块上部 (512, 160) | `(249, 249, 250, 255)` |
| 方块下部 (512, 860) | `(234, 234, 237, 255)`，比上部暗 |
| 光标左侧 (478, 512) | 绿色分量高于远处的灰底，柔光还在 |
| 方块下方中线 | 有一段 alpha 在 8 到 49 之间的黑色投影 |

16 / 32 / 64 的实心光标像素数分别是 36、96、176，外接框分别是 4×9、6×16、8×22，高大于宽。小图左上角仍然透明。

接着在 Linux 上组装了 `build/Supervim.app`。`Contents/Resources/AppIcon.icns` 是 65622 字节，和 `Resources/AppIcon.icns` 相同。组装后的清单里 `CFBundleIconFile` 是 `AppIcon`，短版本号仍是 `0.1.0`，构建号仍是 `1`，`LSUIElement` 仍是 true。再跑一次 `scripts/make-icon.sh`，PNG 和 icns 的字节不变。

## 只在 macOS 上编译的代码

这次没有改 Swift 源文件。应用图标不由代码绘制：Launch Services 读 `CFBundleIconFile`，文件在 `Contents/Resources/AppIcon.icns`。

核对过这些只在 macOS 上编译的路径，它们都不引用 `NSImage`、`applicationIcon` 或 `CFBundleIcon`：

- `Sources/Supervim/SupervimApp.swift` 在 macOS 上把激活策略设成 accessory
- `Sources/Supervim/ExclusionSettingsPanel.swift` 的状态栏项用的是文字标题，不是图片
- `PermissionGuidancePanel.swift`、`HintOverlayWindow.swift`、`PermissionAccess.swift`、`AXApplicationReader.swift` 仍包在 `canImport(AppKit)` 里
- `testModifierMasksMatchCoreGraphics` 只比较修饰键掩码，和这次的资源无关

`LSUIElement` 保持 true。菜单栏应用仍然没有 Dock 图标；Finder、DMG 和「应用程序」文件夹会显示这张图。

## 交给所有者看的决定

1. **圆角方用连续曲率，不是圆弧。** 直边接到指数 5 的超椭圆角上，半径 185，边长 824，画布四边各留 100。这样曲率在直边处是 0，和直边连续。
2. **1024 的光标是整数像素的实心矩形。** 左上角 (486, 441)，52×142，中心像素正好是 `#34C759`。柔光画在矩形后面，不盖住实心块。
3. **16 和 32 点的位图把光标加粗，并去掉柔光。** 按比例缩到 16 像素时，52 宽只剩不到 1 像素。16 用 4×9，32 用 6×16，64 用 8×22 并只留很窄的一圈光。
4. **icns 在没有 iconutil 的机器上用 PNG 块写出来，并带 `TOC `。** macOS 13 及以上读这种 icns。`scripts/make-icon.sh` 在找得到 `iconutil` 时会用它覆盖同一路径。CI 不重新生成，只跑 `--check`，避免和 iconutil 的字节差把工作区弄脏。
5. **卷图标用同一张 icns。** `create-dmg --volicon` 会把它拷成映像里的 `.VolumeIcon.icns`。`--app-drop-link` 和 `codesign --force -s -` 都还在。挂载检查同时要求包内 icns、`CFBundleIconFile=AppIcon` 和 `.VolumeIcon.icns`。
6. **版本号仍按原来的机制。** 不在这份改动里把清单改成 0.1.1。合并之后打 `v0.1.1` 才会由 Release 工作流把版本写进副本并上传 DMG。这次不打 tag。

## 没有测的东西

- 没有在 Mac 上跑 `iconutil`、`sips` 或 Finder
- 没有生成 DMG，也没有用 `hdiutil` 挂载
- 没有看过系统是否会在预合成的圆角方外面再套一层遮罩
- 没有把应用拖进「应用程序」，也没有看菜单栏
- macOS 上那一个修饰键测试，以及覆盖率脚本，留给这次 pull request 的 CI
