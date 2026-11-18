# 实现过程记录

这些段落原来写在 README 里，按任务和版本记录当时做了什么、哪些没有在真机上验证。为了让 README 只讲怎么用，原文搬到这里，内容没有改写，只把顺序排成了时间顺序。每一段说的是那个任务合并时的状态，后来的变化以 [规格](spec.md)、各任务的测试记录和 [v0.1.5 证据](v0.1.5-evidence.md) 为准。例如任务 15 的 DMG 当时未签名，现在的发布物用固定的自签名证书签名，见 [稳定签名](stable-signing.md)。

These paragraphs used to live in the README. They are moved here unchanged, in chronological order. Each one describes the state when that task was merged; later changes are in the [spec](spec.md), the per-task test evidence, and the [v0.1.5 evidence](v0.1.5-evidence.md).

## 任务 10：标签浮层与 f / F

**任务 10 为当前窗口里已经扫到的可点击元素显示透明、不抢焦点的标签。** 应用层调用 `HintOverlayControlling`：`refreshClickables()` 在钩子外刷新，`enterHint` 显示标签，`receiveHintKey` 接收后续按键，`cancelHint` 取消。`f` 键入完整标签后，在元素中心左键点击并关掉标签。`F` 用同一套标签，点击时按住 Command，不是右键菜单。Esc、无效输入、没有目标或扫描不可用都会取消，并且不点击。点中或取消后用 `endHint` 回到 Normal。Safari、Finder 和系统设置上的 200ms 与 90% 覆盖率这次没有测量。

**Task 10 shows transparent, non-activating labels on clickable elements already scanned in the current window.** The app calls `HintOverlayControlling`: `refreshClickables()` off the hook, `enterHint` to show labels, `receiveHintKey` for later keys, and `cancelHint` to dismiss. `f` clicks the center of an element with the left button once its full label is typed, then hides the labels. `F` uses the same labels and holds Command for the click. It is not a context menu. Escape, invalid input, no targets, or an unavailable scan all cancel without clicking. A click or a cancel returns to Normal through `endHint`. The 200ms and 90% coverage targets in Safari, Finder, and System Settings were not measured.

## 任务 11：滚动、应用快捷键接到钩子

**任务 11 把滚动、应用快捷键和 f/F 接到正在运行的钩子。** 有辅助功能和输入监控权限时，先启动 AXScanner，再安装事件钩子。钩子与菜单共用同一个解释器。选不到可滚动区域时，原来的按键交还。进入 Hint 时调用 `HintController` 显示标签，后续按键交给它。`?` 交给 `HelpCommandHandling`，没人认领就放过。`yy` 沿用任务 9 的浏览器名单。权限缺失时不装钩子。微信、备忘录和 Safari 地址栏不吞字仍未测。

**Task 11 connects scrolling, application shortcuts, and f/F to the running hook.** When Accessibility and Input Monitoring are both granted, it starts AXScanner and then installs the event tap. The hook and the menu share one interpreter. The wheel goes to the scrollable area under the pointer; with the pointer outside the front window, the pointer is first moved to the best area in that window. Entering Hint calls `HintController` to show labels, and later keys go to it. `?` goes to `HelpCommandHandling`, and passes through when nobody claims it. Copy URL keeps task 9's browser list. Missing permissions do not install the hook. Not swallowing characters in WeChat, Notes, and the Safari address bar is still untested.

## 任务 12：快捷键帮助

**任务 12 用 `?` 打开快捷键帮助，再用 `?` 或 Esc 关闭。** 文案从 `CommandMap` 生成。`/`、`F`、`?` 标成与 Vimium 不同，`/` 写成 `Command+F`。帮助和标签共用同一块不激活面板。`MenuHookAssembly` 把 `HelpController` 交给会话的 `help`。普通模式下 Esc 关掉帮助并吞掉这一键；Hint 和 Insert 仍用自己的 Esc。开始 `f` / `F` 时先收起帮助。没有在屏幕上看到这块面板。

**Task 12 opens the shortcut sheet with `?` and closes it with `?` or Esc.** The text comes from `CommandMap`. `/`, `F`, and `?` are marked as different from Vimium, and `/` is written as `Command+F`. Help and hint labels share one non-activating panel. `MenuHookAssembly` passes `HelpController` as the session's `help`. In Normal, Esc closes the sheet and swallows the key. Hint and Insert keep their own Esc. Starting `f` / `F` hides the sheet first. The panel was not seen on a display.

## 任务 13：菜单栏模式、暂停与设置

**任务 13 把菜单栏换成模式显示。** 状态标题是 Normal、Insert 或 Paused。Hint 也显示成 Normal。菜单可以暂停、恢复、打开设置和退出。暂停会写入设置，下次启动仍然暂停。设置窗口可以加入当前前台应用、移除排除项，以及切换登录启动偏好。偏好会保存；任务 15 再按这个值注册或注销系统登录项。排除列表默认仍是 Terminal、iTerm、Emacs；命中时按键原样放过，包括暂停键。

**Task 13 replaces the menu-bar placeholder with the mode.** The status title is Normal, Insert, or Paused. Hint is shown as Normal. The menu can pause, resume, open settings, and quit. Pause is written to settings and restored on the next launch. The settings window can add the frontmost app, remove an exclusion, and toggle the launch-at-login preference. The preference is stored, and task 15 registers or unregisters the system login item from it. The exclusion list still defaults to Terminal, iTerm, and Emacs, and a match passes every key through, including the pause chord.

## 任务 14：权限引导

**任务 14 在缺少辅助功能或输入监控时显示引导。** 引导列出仍缺的那一项，并提供打开系统设置里对应面板的链接。重新检测发现两项都已授予后，才走任务 11 的启动：先扫描焦点，再安装事件钩子。授权之后，当前进程不保证不用退出重开就能用上该权限；这一点没有在真机上验证。未签名的 Supervim 重新构建后，可能要再授权一次。权限检测放在可注入的接口后面，测试用替身，不申请真实的辅助功能或输入监控权限。

**Task 14 shows guidance when Accessibility or Input Monitoring is missing.** The guide lists each missing permission and links to that pane in System Settings. A later read that finds both granted is what starts task 11's runtime: the focus scanner, then the event tap. Granting a permission does not guarantee this process can use it without quitting and reopening; that behavior is not verified. An unsigned Supervim may need to be allowed again after it is rebuilt. Permission checks sit behind an injectable interface. Tests use a stand-in and do not request the real permissions.

## 任务 15：DMG、Release 与登录项

**任务 15 发布未签名 DMG，并按设置里的登录启动偏好注册登录项。** 推送 `v*` tag，或在 Actions 里手动运行 Release 并输入版本号，都会在 `macos-latest` 上做 release 构建、把版本号写入 `Info.plist`、用 `create-dmg` 生成带 Applications 拖拽快捷方式的 DMG，再用 `GITHUB_TOKEN` 创建 GitHub Release 并上传。登录项的判断放在可注入的 `LoginItemRegistration` 后面；macOS 适配器调用 `SMAppService.mainApp`。pull request 的 CI 会打包同一份 DMG，挂载后检查 `Supervim.app` 和 Applications 链接，并上传 artifact。Safari、Finder、系统设置上的 200ms 和 90% 覆盖率，以及微信、备忘录、Safari 地址栏不吞字，仍写在手工验收清单里，没有改成已经测到。

**Task 15 publishes the unsigned DMG and registers the login item from the saved preference.** Pushing a `v*` tag, or running the Release workflow with a version number, does a release build on `macos-latest`, writes the version into `Info.plist`, builds a DMG with an Applications drop link via `create-dmg`, and uploads it to a GitHub Release with `GITHUB_TOKEN`. The decision lives behind the injectable `LoginItemRegistration`. The macOS adapter calls `SMAppService.mainApp`. Pull-request CI packages the same kind of DMG, mounts it, checks for `Supervim.app` and the Applications link, and uploads the image as an artifact. The 200ms and 90% targets, and not swallowing characters in WeChat, Notes, and the Safari address bar, stay on the manual checklist. They are not marked as measured.

## v0.1.5：线程模型、扫描与标签

**v0.1.5 把按键钩子、扫描、动作分到各自的线程上。** 钩子回调只读缓存并立刻返回；被系统停用时立刻重新打开，另有看门狗每 500ms 检查一次。每次 `f` 都重新扫描窗口，每个节点一次批量读取，消息超时 0.75 秒。标签面板创建一次后复用。可点元素的识别和去重重写了。滚动不再依赖过期的行程，指针不在前台窗口里时会先移动指针。原因、修改和测量见 [v0.1.5 证据](v0.1.5-evidence.md)。这些都没有在真机上验证。

**v0.1.5 moves the key hook, scanning, and actions onto their own threads.** The hook callback reads cached state and returns; when macOS disables the tap it is re-enabled at once, and a watchdog checks every 500ms. Every `f` rescans the window with one batched read per node and a 0.75s messaging timeout. Label panels are created once and reused. Clickable detection and de-duplication were rewritten. Scrolling no longer depends on stale travel and moves the pointer first when it is outside the front window. Causes, changes, and measurements are in [the v0.1.5 evidence](v0.1.5-evidence.md). None of it was verified on a real Mac.
