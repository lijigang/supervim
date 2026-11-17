<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="Supervim">
</p>

# Supervim

Supervim 是一个原生 macOS 菜单栏应用，目标是提供 Vimium 风格的系统级键盘控制。它使用 Swift 和 AppKit，不用 Electron，运行时不联网，也不记录击键。

Supervim is a native macOS menu-bar app for Vimium-style, system-wide keyboard control. It uses Swift and AppKit, not Electron. The running app does not use the network and does not record keystrokes.

## 安装 / Install

发布物没有公证，也没有付费的 Apple Developer ID。配置好稳定的自签证书之后，每次升级都用同一张证书签名，辅助功能和输入监控可以保留；Gatekeeper 第一次打开时仍会警告。证书还没配进 GitHub 时，打包会退回 ad-hoc 签名（`codesign -s -`），每次安装都要重新授权。说明见 `docs/stable-signing.md`。

1. 从 GitHub Release 下载 `Supervim-<版本>.dmg`。
2. 打开磁盘映像。里面有 `Supervim.app` 和指向「应用程序」的 `Applications` 快捷方式。
3. 把 `Supervim.app` 拖进 Applications。
4. 从「应用程序」文件夹打开它。菜单栏里会出现状态，没有 Dock 图标。

The release is not notarized and does not use a paid Developer ID. Once the stable self-signed certificate is configured, every upgrade is signed with that same certificate, so Accessibility and Input Monitoring can survive. Gatekeeper still warns the first time. If the certificate secret is missing, the build falls back to an ad-hoc signature (`codesign -s -`) and each install needs a new grant. See `docs/stable-signing.md`.

1. Download `Supervim-<version>.dmg` from the GitHub Release.
2. Open the image. It contains `Supervim.app` and an `Applications` shortcut.
3. Drag `Supervim.app` into Applications.
4. Open it from the Applications folder. The status appears in the menu bar, and there is no Dock icon.

## 第一次打开未签名应用 / Opening an unsigned app

第一次打开会被系统拦住。任选一种：

- 在 Finder 里对 `Supervim.app` 按住 Control 点按（或右键），选择「打开」，再在对话框里确认打开。
- 若仍然被拒：打开「系统设置」→「隐私与安全性」，在安全性区域选择「仍要打开」。
- 或者在终端去掉隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/Supervim.app
```

然后再次从「应用程序」打开。

The first launch is blocked. Use one of these:

- Control-click (or right-click) `Supervim.app` in Finder, choose Open, and confirm.
- If it is still blocked: System Settings → Privacy & Security → Open Anyway.
- Or clear the quarantine attribute, then open the app from Applications again:

```bash
xattr -dr com.apple.quarantine /Applications/Supervim.app
```

## 权限 / Permissions

Supervim 需要两项权限：辅助功能（Accessibility）和输入监控（Input Monitoring）。缺任何一项时会显示引导，并给出系统设置里对应面板的链接。两项都允许之后，才开始扫描焦点并安装按键钩子。

授权之后，当前进程不保证不用退出再打开就能用上该权限。这一点没有在真机上验证。未签名的 Supervim 重新构建或更换二进制之后，代码目录哈希可能变化，系统可能要求再授权一次。

Supervim needs Accessibility and Input Monitoring. If either is missing, a guide offers a link to that pane in System Settings. The focus scanner and the key hook start only after both are allowed.

Granting a permission does not guarantee this process can use it without quitting and reopening. That has not been verified on a Mac. Rebuilding the unsigned binary can change its code-directory hash, and macOS may ask for permission again.

## 登录时启动 / Launch at login

设置窗口里的 Launch at Login 会保存偏好，并按这个值注册或注销登录项。实现调用的是系统的主应用登录项服务。应用不在「应用程序」文件夹里时，登记常常失败；设置里会提示先把 Supervim 移进去再试，进程不因此崩溃。系统也可能把这一项标成需要在「登录项与扩展」里再允许一次。真机上的登记没有验证。

The Launch at Login checkbox stores the preference and registers or unregisters the login item from that value, through the system main-app service. Registration often fails until Supervim is in the Applications folder. Settings then asks you to move it there. The process does not crash. macOS may also leave the item waiting for approval under Login Items & Extensions. Registration on a real Mac is not verified.

## 键位 / Keys

普通模式下：

| 按键 | 作用 |
| --- | --- |
| `f` | 给当前窗口里可点击的元素标上 `asdfghjkl` 的最短标签。键入完整标签后，在元素中心左键点击并关掉标签 |
| `F` | 同一套标签。点击时按住 Command |
| `Esc` | 取消标签或帮助。插入模式里离开输入焦点，回到普通模式 |
| `i` | 手动进入插入模式，并放过按键 |
| `j` / `k` / `h` / `l` | 向下 / 向上 / 向左 / 向右滚动 60 点。选不到可滚动区域时，原键交还给前台应用 |
| `d` / `u` | 向下 / 向上滚动半页 |
| `gg` / `G` | 滚到顶部 / 底部 |
| `gi` | 聚焦第一个输入框。焦点变成可编辑之后才进入插入模式 |
| `Ctrl+]` | 放过下一个按键 |
| `H` / `L` | 历史后退 / 前进，合成 Command+`[` / Command+`]` |
| `J` / `K` | 上一个 / 下一个标签，合成 Command+Shift+`[` / Command+Shift+`]` |
| `x` / `t` / `r` | 关闭 / 新建 / 刷新，合成 Command+`W` / Command+`T` / Command+`R` |
| `/` | 查找，发给前台应用自己的 Command+`F` |
| `yy` | 复制地址：先 Command+`L`，再 Command+`C`。只对 Safari 和 Chromium 承诺 |
| `?` | 打开快捷键帮助。再按 `?` 或 `Esc` 关闭 |
| `Ctrl+Option+V` | 暂停或恢复。菜单栏显示 Normal、Insert 或 Paused |

焦点在可编辑控件上时自动进入插入模式，并放过全部按键。前台应用如果在排除列表里，Supervim 完全不碰它，包括暂停键。默认排除 Terminal（`com.apple.Terminal`）、iTerm2（`com.googlecode.iterm2`）和 GNU Emacs（`org.gnu.Emacs`）。这三个标识没有经过所有者确认。

无法识别的普通模式按键会放过。没有 omnibar。

In Normal mode, `f` labels clickable elements with the shortest `asdfghjkl` labels and left-clicks the center of a completed label. `F` holds Command for that click. `Esc` cancels labels or help, and leaves an editable field. `i` enters Insert and passes keys through. `j` `k` `h` `l` scroll by 60 points; `d` and `u` scroll half a page; `gg` and `G` go to the top and bottom. A scroll with no target gives the original key back. `gi` focuses the first input and enters Insert only after the focus is editable. `Ctrl+]` passes the next key. `H` `L` are back and forward. `J` `K` are the previous and next tab. `x` `t` `r` close, create, and reload. `/` is the app's own find shortcut, Command+`F`. `yy` is Command+`L` then Command+`C`, promised only for Safari and Chromium. `?` opens the shortcut sheet and `?` or `Esc` closes it. `Ctrl+Option+V` pauses or resumes.

An editable focus enters Insert automatically and every key is passed through. An excluded frontmost app is left completely alone, including the pause chord. The defaults are Terminal (`com.apple.Terminal`), iTerm2 (`com.googlecode.iterm2`), and GNU Emacs (`org.gnu.Emacs`). Those identifiers were not confirmed by the owner.

Unrecognized Normal keys pass through. There is no omnibar.

## 与 Vimium 的偏差 / Differences from Vimium

帮助里标成 `differs from Vimium` 的只有三行：

- `F` 是按住 Command 的点击，不是 Vimium 的「在新标签页打开链接」，也不是右键菜单。
- `/` 发给前台应用的 Command+`F`，不是 Vimium 自己的查找模式。
- `?` 打开的是由这张命令表生成的帮助。命令表本身只发出「显示帮助」；再按 `?` 或 `Esc` 关掉它是帮助层做的。

另外这些也和 Vimium 的默认体验不同，帮助表没有把它们标成偏离：

- 没有 omnibar、标记（marks）、视觉模式、自定义按键，也没有 `3j` 这种次数。
- 滚动一下到位，没有 Vimium 默认的平滑滚动。
- `yy` 先聚焦地址栏再复制，不保证复制出来的是规范化 URL。承诺范围只有 Safari，以及这些未经所有者确认的 Chromium 家族标识：Chrome `com.google.Chrome`、Chromium `org.chromium.Chromium`、Edge `com.microsoft.edgemac`、Brave `com.brave.Browser`、Arc `company.thebrowser.Browser`、Vivaldi `com.vivaldi.Vivaldi`。Firefox 和 Opera 不在里面，`yy` 不会发出快捷键。
- 未完成的按键前缀上按 `Esc`，除了取消前缀，还会把 `Esc` 交给模式机，方便插入模式和标签模式离开。

The help sheet marks only three rows with `differs from Vimium`:

- `F` Command-clicks. It does not open a link in a new tab, and it is not a context menu.
- `/` sends the frontmost app's Command+`F`. It is not Vimium's find mode.
- `?` shows help generated from this command table. The table itself only emits "show help". Pressing `?` again, or `Esc`, closes the sheet in the help layer.

These also differ from Vimium's defaults and are not marked on the sheet: there is no omnibar, marks, visual mode, custom keys, or count prefix such as `3j`; scrolling jumps instead of animating; `yy` focuses the address bar and copies it, only for Safari and the unconfirmed Chromium-family identifiers Chrome `com.google.Chrome`, Chromium `org.chromium.Chromium`, Edge `com.microsoft.edgemac`, Brave `com.brave.Browser`, Arc `company.thebrowser.Browser`, and Vivaldi `com.vivaldi.Vivaldi`. Firefox and Opera are not included. `Esc` during an unfinished prefix also reports escape so Insert and Hint can leave.

**任务 13 把菜单栏换成模式显示。** 状态标题是 Normal、Insert 或 Paused。Hint 也显示成 Normal。菜单可以暂停、恢复、打开设置和退出。暂停会写入设置，下次启动仍然暂停。设置窗口可以加入当前前台应用、移除排除项，以及切换登录启动偏好。偏好会保存；任务 15 再按这个值注册或注销系统登录项。排除列表默认仍是 Terminal、iTerm、Emacs；命中时按键原样放过，包括暂停键。

**Task 13 replaces the menu-bar placeholder with the mode.** The status title is Normal, Insert, or Paused. Hint is shown as Normal. The menu can pause, resume, open settings, and quit. Pause is written to settings and restored on the next launch. The settings window can add the frontmost app, remove an exclusion, and toggle the launch-at-login preference. The preference is stored, and task 15 registers or unregisters the system login item from it. The exclusion list still defaults to Terminal, iTerm, and Emacs, and a match passes every key through, including the pause chord.

**任务 10 为当前窗口里已经扫到的可点击元素显示透明、不抢焦点的标签。** 应用层调用 `HintOverlayControlling`：`refreshClickables()` 在钩子外刷新，`enterHint` 显示标签，`receiveHintKey` 接收后续按键，`cancelHint` 取消。`f` 键入完整标签后，在元素中心左键点击并关掉标签。`F` 用同一套标签，点击时按住 Command，不是右键菜单。Esc、无效输入、没有目标或扫描不可用都会取消，并且不点击。点中或取消后用 `endHint` 回到 Normal。Safari、Finder 和系统设置上的 200ms 与 90% 覆盖率这次没有测量。

**Task 10 shows transparent, non-activating labels on clickable elements already scanned in the current window.** The app calls `HintOverlayControlling`: `refreshClickables()` off the hook, `enterHint` to show labels, `receiveHintKey` for later keys, and `cancelHint` to dismiss. `f` clicks the center of an element with the left button once its full label is typed, then hides the labels. `F` uses the same labels and holds Command for the click. It is not a context menu. Escape, invalid input, no targets, or an unavailable scan all cancel without clicking. A click or a cancel returns to Normal through `endHint`. The 200ms and 90% coverage targets in Safari, Finder, and System Settings were not measured.

**任务 11 把滚动、应用快捷键和 f/F 接到正在运行的钩子。** 有辅助功能和输入监控权限时，先启动 AXScanner，再安装事件钩子。钩子与菜单共用同一个解释器。选不到可滚动区域时，原来的按键交还。进入 Hint 时调用 `HintController` 显示标签，后续按键交给它。`?` 交给 `HelpCommandHandling`，没人认领就放过。`yy` 沿用任务 9 的浏览器名单。权限缺失时不装钩子。微信、备忘录和 Safari 地址栏不吞字仍未测。

**Task 11 connects scrolling, application shortcuts, and f/F to the running hook.** When Accessibility and Input Monitoring are both granted, it starts AXScanner and then installs the event tap. The hook and the menu share one interpreter. A scroll with no target gives the original key back. Entering Hint calls `HintController` to show labels, and later keys go to it. `?` goes to `HelpCommandHandling`, and passes through when nobody claims it. Copy URL keeps task 9's browser list. Missing permissions do not install the hook. Not swallowing characters in WeChat, Notes, and the Safari address bar is still untested.

**任务 12 用 `?` 打开快捷键帮助，再用 `?` 或 Esc 关闭。** 文案从 `CommandMap` 生成。`/`、`F`、`?` 标成与 Vimium 不同，`/` 写成 `Command+F`。帮助和标签共用同一块不激活面板。`MenuHookAssembly` 把 `HelpController` 交给会话的 `help`。普通模式下 Esc 关掉帮助并吞掉这一键；Hint 和 Insert 仍用自己的 Esc。开始 `f` / `F` 时先收起帮助。没有在屏幕上看到这块面板。

**Task 12 opens the shortcut sheet with `?` and closes it with `?` or Esc.** The text comes from `CommandMap`. `/`, `F`, and `?` are marked as different from Vimium, and `/` is written as `Command+F`. Help and hint labels share one non-activating panel. `MenuHookAssembly` passes `HelpController` as the session's `help`. In Normal, Esc closes the sheet and swallows the key. Hint and Insert keep their own Esc. Starting `f` / `F` hides the sheet first. The panel was not seen on a display.

**任务 14 在缺少辅助功能或输入监控时显示引导。** 引导列出仍缺的那一项，并提供打开系统设置里对应面板的链接。重新检测发现两项都已授予后，才走任务 11 的启动：先扫描焦点，再安装事件钩子。授权之后，当前进程不保证不用退出重开就能用上该权限；这一点没有在真机上验证。未签名的 Supervim 重新构建后，可能要再授权一次。权限检测放在可注入的接口后面，测试用替身，不申请真实的辅助功能或输入监控权限。

**Task 14 shows guidance when Accessibility or Input Monitoring is missing.** The guide lists each missing permission and links to that pane in System Settings. A later read that finds both granted is what starts task 11's runtime: the focus scanner, then the event tap. Granting a permission does not guarantee this process can use it without quitting and reopening; that behavior is not verified. An unsigned Supervim may need to be allowed again after it is rebuilt. Permission checks sit behind an injectable interface. Tests use a stand-in and do not request the real permissions.

**任务 15 发布未签名 DMG，并按设置里的登录启动偏好注册登录项。** 推送 `v*` tag，或在 Actions 里手动运行 Release 并输入版本号，都会在 `macos-latest` 上做 release 构建、把版本号写入 `Info.plist`、用 `create-dmg` 生成带 Applications 拖拽快捷方式的 DMG，再用 `GITHUB_TOKEN` 创建 GitHub Release 并上传。登录项的判断放在可注入的 `LoginItemRegistration` 后面；macOS 适配器调用 `SMAppService.mainApp`。pull request 的 CI 会打包同一份 DMG，挂载后检查 `Supervim.app` 和 Applications 链接，并上传 artifact。Safari、Finder、系统设置上的 200ms 和 90% 覆盖率，以及微信、备忘录、Safari 地址栏不吞字，仍写在手工验收清单里，没有改成已经测到。

**Task 15 publishes the unsigned DMG and registers the login item from the saved preference.** Pushing a `v*` tag, or running the Release workflow with a version number, does a release build on `macos-latest`, writes the version into `Info.plist`, builds a DMG with an Applications drop link via `create-dmg`, and uploads it to a GitHub Release with `GITHUB_TOKEN`. The decision lives behind the injectable `LoginItemRegistration`. The macOS adapter calls `SMAppService.mainApp`. Pull-request CI packages the same kind of DMG, mounts it, checks for `Supervim.app` and the Applications link, and uploads the image as an artifact. The 200ms and 90% targets, and not swallowing characters in WeChat, Notes, and the Safari address bar, stay on the manual checklist. They are not marked as measured.

## 文档 / Docs

- [宪法 / Constitution](docs/constitution.md)
- [规格 v0.1 / Spec](docs/spec.md)
- [计划 / Plan](docs/plan.md)
- [任务与依赖 / Tasks](docs/tasks.md)
- [任务 1 测试记录 / Task 1 test evidence](docs/task1-test-evidence.md)
- [任务 2 测试记录 / Task 2 test evidence](docs/task2-test-evidence.md)
- [任务 3 测试记录 / Task 3 test evidence](docs/task3-test-evidence.md)
- [任务 4 测试记录 / Task 4 test evidence](docs/task4-test-evidence.md)
- [任务 5 测试记录 / Task 5 test evidence](docs/task5-test-evidence.md)
- [任务 6 测试记录 / Task 6 test evidence](docs/task6-test-evidence.md)
- [任务 7 测试记录 / Task 7 test evidence](docs/task7-test-evidence.md)
- [任务 8 测试记录 / Task 8 test evidence](docs/task8-test-evidence.md)
- [任务 9 测试记录 / Task 9 test evidence](docs/task9-test-evidence.md)
- [任务 10 测试记录 / Task 10 test evidence](docs/task10-test-evidence.md)
- [任务 11 测试记录 / Task 11 test evidence](docs/task11-test-evidence.md)
- [任务 12 测试记录 / Task 12 test evidence](docs/task12-test-evidence.md)
- [任务 13 测试记录 / Task 13 test evidence](docs/task13-test-evidence.md)
- [任务 14 测试记录 / Task 14 test evidence](docs/task14-test-evidence.md)
- [任务 15 测试记录 / Task 15 test evidence](docs/task15-test-evidence.md)
- [应用图标测试记录 / App icon test evidence](docs/app-icon-test-evidence.md)
- [手工验收清单 / Manual acceptance](docs/manual-acceptance.md)

规格文末单独列出了尚未能保证的平台行为。那些条目没有改写已批准的要求。手工验收清单把还没在真机上做过的项目收在一处。

## 环境 / Requirements

- macOS 13 or later
- Swift 6
- Xcode, which provides the Swift toolchain and AppKit

Linux 可以编译并运行纯逻辑测试。菜单栏进程不能在 Linux 上运行。

## 构建与测试 / Build and test

在 macOS 上：

```bash
swift test
scripts/assemble-app.sh
open build/Supervim.app
```

`swift test` 会编译三个 SwiftPM 目标并运行 XCTest。`scripts/assemble-app.sh` 把调试版二进制装进 `build/Supervim.app`。这个包的 `Info.plist` 设置了 `LSUIElement=true`，bundle id 是 `com.lijigang.supervim`，所以通过 Finder 或 `open` 启动时没有 Dock 图标。包没有开发者签名。

直接 `swift run` 时，系统不会把裸二进制当成带 `LSUIElement` 的应用包。程序会改用 accessory 激活策略，避免开发时出现 Dock 图标。状态栏显示 Normal、Insert 或 Paused，菜单里有暂停、恢复、设置和退出。缺少辅助功能或输入监控时，启动会打开权限引导，菜单里多一项 Permissions，并且不安装事件钩子。两项都授予之后，再重新检测，然后先跑焦点扫描，再安装事件钩子；`f` / `F` 交给标签浮层，`?` 打开帮助。授权不保证不用退出再打开就能生效。

发布构建和磁盘映像。第二个参数会写进 `CFBundleShortVersionString` 和 `CFBundleVersion`。不写的话，沿用仓库里的 `0.1.0` 和 `1`。

```bash
scripts/assemble-app.sh release 0.1.0
brew install create-dmg
scripts/package-dmg.sh build/Supervim.app build/Supervim-0.1.0.dmg
scripts/verify-dmg.sh build/Supervim-0.1.0.dmg
```

应用图标是一张 1024 画布上的浅灰圆角方，正中一块绿色的普通模式光标。`scripts/make-icon.sh` 从同一套几何写出 `Resources/AppIcon.svg`、各尺寸 PNG 和 `Resources/AppIcon.icns`。macOS 上如果有 `iconutil`，脚本会用它重新打包 icns。组装时 icns 放进 `Contents/Resources`，`CFBundleIconFile` 是 `AppIcon`。菜单栏状态仍然是文字，`LSUIElement` 仍是 true，所以没有 Dock 图标。DMG 用同一张 icns 做卷图标。

The app icon is a light rounded square on a 1024 canvas, with a green Normal-mode cursor in the center. `scripts/make-icon.sh` writes `Resources/AppIcon.svg`, the PNG sizes, and `Resources/AppIcon.icns` from that geometry. On macOS it repacks the icns with `iconutil` when that tool exists. Assembly copies the icns into `Contents/Resources` and `CFBundleIconFile` is `AppIcon`. The menu bar stays text, and `LSUIElement` stays true, so there is still no Dock icon. The DMG uses the same icns as its volume icon.

合并之后，在仓库上推送 tag `v0.1.0` 会触发 Release 工作流，生成 DMG 并创建 GitHub Release。也可以在 Actions 里手动运行 Release，版本号填 `0.1.0`。不要为了同一次发布既推 tag 又手动跑：手动运行会创建 tag，随后的 tag 工作流如果发现 Release 里已经有同名 DMG，就跳过重建。

## 工程结构 / Layout

```text
Package.swift                 SwiftPM 描述，macOS 13+，Swift 6
Sources/SupervimCore          纯逻辑，不导入 AppKit 或事件框架。含 ModeMachine、KeyParser、HintLabeler、CommandMap、Settings、EventInterpreter、CommandFollowThrough、MenuBarController、HintSession、HelpSheet、PermissionGuide、LoginItemRegistration
Sources/SupervimSystem        系统适配。含菜单栏预检、UserDefaults、EventTap、AXScanner、Actuator、标签浮层、帮助浮层、滚动目录、命令会话、权限探测，以及 macOS 上的主应用登录项。另有 CGEvent 合成、不激活面板和输入框聚焦
Sources/Supervim              菜单栏应用。启动时按偏好登记登录项；缺权限时显示引导；两项都授予后启动 AXScanner 并安装事件钩子
App/Supervim/Info.plist       应用包清单，含 LSUIElement、CFBundleIconFile、com.lijigang.supervim 和版本号
Resources/AppIcon.svg         图标源图。1024 透明画布、824 连续曲率圆角方、绿色光标块
Resources/AppIcon-1024.png    提交的 1024 图标
Resources/AppIcon.icns        提交的应用图标，含 16–1024 与 @2x
scripts/make-icon.sh          生成 iconset 和 icns；macOS 上优先用 iconutil
scripts/assemble-app.sh       组装未签名 .app，放入 AppIcon.icns，release 时可写入版本号
scripts/package-dmg.sh        用 create-dmg 打包。scripts/sign-app.sh 用稳定证书签名，没有证书时才 ad-hoc
scripts/verify-dmg.sh         hdiutil 挂载并检查应用、Applications 链接、图标和卷图标
Tests                         XCTest
.github/workflows/ci.yml      macos-latest 上构建、测试、组装、DMG 冒烟
.github/workflows/release.yml 推送 v* tag 或手动输入版本号后发布 DMG
docs                          已批准的中文宪法、规格、计划和任务
.taskmaster/tasks/tasks.json  任务 1–15，供 task-master 读取
```

应用包不把手写 Xcode 工程或 XcodeGen 当作第二份目标定义。原因写在 [计划](docs/plan.md#任务-1-的应用包脚手架)。

## CI

推送和 pull request 都会在 `macos-latest` 上执行 `swift build`、`swift test`、十四个覆盖率脚本和 `scripts/make-icon.sh --check`，再跑 `scripts/assemble-app.sh`，检查组装结果里的 `LSUIElement`、bundle id、版本号、`CFBundleIconFile=AppIcon` 和 `Contents/Resources/AppIcon.icns`，然后用 `create-dmg` 打包、`hdiutil` 挂载校验，并把 DMG 作为 artifact 上传。覆盖率脚本分别要求 `ModeMachine.swift`、`KeyParser.swift`、`HintLabeler.swift`、`CommandMap.swift`、`Settings.swift`、`UserDefaultsSettingsStore.swift`、`EventInterpreter.swift`、`EventTap.swift`、`Actuator.swift`、`AXScanner.swift`、`MenuBarController.swift`、`HintSession.swift`、`HintOverlay.swift`、`CommandFollowThrough.swift`、`NormalCommandSession.swift`、`ScrollAreaCatalog.swift`、`SupervimRuntime.swift`、`PermissionGuide.swift`、`HelpSheet.swift`、`HelpOverlay.swift` 和 `LoginItemRegistration.swift` 的行覆盖率不低于 90%。`AXApplicationReader.swift`、`CGEventActuator.swift`、`HintOverlayWindow.swift`、`AXInputFocuser.swift`、`PermissionAccess.swift`、`MacHookAssembly.swift`、`MainAppLoginItemController.swift` 和菜单与引导的 AppKit 胶水只在 macOS 上编译，不计入这个门槛。

## 工作流工具 / Workflow tools

本仓库没有 spec-kit，也没有 task-master CLI。任务文件是按上游 schema 手写的，说明见 [任务文档](docs/tasks.md#task-master-格式)。测试记录写在 `docs/task1-test-evidence.md` 到 `docs/task15-test-evidence.md`。真机还没做的项目见 [手工验收清单](docs/manual-acceptance.md)。
