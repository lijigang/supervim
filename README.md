# Supervim

[English](README.en.md) · [下载最新版](https://github.com/lijigang/supervim/releases/latest)

Supervim 是一个原生 macOS 菜单栏应用，把 Vimium 的键盘操作带到整个系统：按 `f` 给当前窗口里能点的元素标上字母，按字母就点击；`j` / `k` 滚动。Swift + AppKit 编写，运行时不联网，不记录按键。

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/ui-polish/help-dark.png">
  <img src="docs/ui-polish/help-light.png" width="512" alt="按 ? 打开的快捷键帮助">
</picture>

## 安装

需要 macOS 13 或更高版本。

1. 从 [Releases](https://github.com/lijigang/supervim/releases/latest) 下载 `Supervim-<版本>.dmg`，打开后把 `Supervim.app` 拖进「应用程序」。
2. 从「应用程序」打开它。应用没有公证，第一次会被系统拦住：到「系统设置 → 隐私与安全性」点「仍要打开」。macOS 14 及更早也可以在 Finder 里右键点「打开」。还不行就在终端执行 `xattr -dr com.apple.quarantine /Applications/Supervim.app` 再打开。
3. 按弹出的权限窗口授权，然后点 `Check Again`。授权后仍没反应，就退出 Supervim 再打开一次。

| 权限 | 是否必需 | 用途 |
| --- | --- | --- |
| 辅助功能（Accessibility） | 必需 | 读取焦点和可点击元素，执行点击和滚动 |
| 输入监控（Input Monitoring） | 必需 | 接收全局按键 |
| 屏幕录制（Screen Recording） | 可选 | 只有微信这类读不到辅助功能元素的应用才需要。第一次在这种应用里按 `f` 时才请求；截图只在本机做文字识别，不存盘、不上传 |

装好后菜单栏出现 Supervim 图标，Dock 里没有图标。

**升级**：下载新的 DMG，覆盖「应用程序」里的旧版本。v0.1.3 起每个版本都用同一张固定的自签名证书签名，所以升级后已授予的权限保留，不用重新授权。原理见 [稳定签名](docs/stable-signing.md)。

## 快速上手

Supervim 启动后处于 Normal 模式。菜单栏图标显示当前模式：

| 模式 | 菜单栏图标 | 什么时候 | 按键去哪里 |
| --- | --- | --- | --- |
| Normal | 一块竖条 | 默认 | [下表](#按键)里的键是命令，其余按键原样交给应用 |
| Insert | I 形光标 | 焦点进入输入框时自动进入，或按 `i` | 全部交给应用，正常打字 |
| Paused | 两条竖线 | 手动暂停 | 全部交给应用 |

试一下：

1. 打开 Safari 里任意网页，按 `j` / `k` 滚动。
2. 按 `f`，每个可点击的元素上出现字母标签。键入标签就点击它，`Esc` 取消。
3. 点进一个输入框，图标变成 Insert，可以正常打字。按 `Esc` 回到 Normal。
4. 按 `?` 查看全部快捷键。

按 `Esc` 回到 Normal 之后，光标可能还留在输入框里，但按键已经是命令，同一个输入框不会再自动进入 Insert。想继续在里面打字，用鼠标点一下它，或者按 `i` 或 `gi`。

## 按键

除 `Esc` 和最后一行外，都只在 Normal 模式下生效。

| 按键 | 作用 |
| --- | --- |
| `f` | 给当前窗口的可点击元素标上字母，键入标签即点击 |
| `F` | 同 `f`，但按住 Command 点击（例如在浏览器里用新标签页打开链接） |
| `j` / `k` | 向下 / 向上滚动 |
| `h` / `l` | 向左 / 向右滚动 |
| `d` / `u` | 向下 / 向上滚动半页 |
| `gg` | 滚到顶部 |
| `G` | 滚到底部 |
| `gi` | 聚焦窗口里的输入框，并进入 Insert |
| `i` | 手动进入 Insert |
| `Esc` | 从 Insert 回到 Normal；取消标签；关闭帮助 |
| `?` | 打开快捷键帮助，再按一次关闭 |
| `/` | 查找，发送应用自己的 `Command+F` |
| `x` | 关闭，发送 `Command+W` |
| `t` | 新建，发送 `Command+T` |
| `r` | 刷新，发送 `Command+R` |
| `H` / `L` | 后退 / 前进，发送 `Command+[` / `Command+]`。仅浏览器 |
| `J` / `K` | 上一个 / 下一个标签页，发送 `Command+Shift+[` / `Command+Shift+]`。仅浏览器 |
| `yy` | 复制当前网址，发送 `Command+L` 再 `Command+C`。仅浏览器 |
| `Ctrl+]` | 把下一个按键原样交给应用 |
| `Ctrl+Option+V` | 暂停 / 恢复 Supervim，Insert 里也有效 |

- 「仅浏览器」指 Safari、Chrome、Chromium、Edge、Brave、Arc、Vivaldi。在其他应用里这几个键不起作用。
- 标签显示期间，`Backspace` 删掉上一个输入的字符，`Esc` 或不匹配的字符取消。
- `gg`、`gi`、`yy` 的两下要在 1 秒内按完。
- 滚动作用在鼠标指针下面的可滚动区域。指针不在前台窗口里（例如在另一块显示器上）时，会先把指针移到要滚动的区域。
- 没有数字前缀（`3j`）、自定义按键、omnibar、marks 和视觉模式。完整的差异见 [与 Vimium 的差异](docs/vimium-differences.md)。

## 菜单栏与设置

暂停：点菜单栏图标选 Pause，或按 `Ctrl+Option+V`。退出：点菜单栏图标选 Quit Supervim。

| 菜单项 | 作用 |
| --- | --- |
| Pause / Resume | 暂停 / 恢复，等同 `Ctrl+Option+V`。暂停状态会保存，下次启动仍是暂停 |
| Settings | 打开设置窗口 |
| Permissions | 只在缺权限时出现，重新打开权限窗口 |
| Quit Supervim | 退出 |

设置窗口里有两项：

| 设置 | 作用 |
| --- | --- |
| Launch at Login | 登录时自动启动。需要 Supervim 在「应用程序」文件夹里 |
| Excluded Apps | 排除列表。列表里的应用在前台时，Supervim 完全不拦截按键，包括暂停快捷键。默认有 Terminal、iTerm2、Emacs。添加按钮加的是打开设置窗口之前所在的应用，按钮上写着它的名字，例如 `Add "WeChat"`；要加别的应用，先切过去再切回设置窗口。`Remove` 移除 |

## 排查问题

| 现象 | 原因和处理 |
| --- | --- |
| 按键完全没反应 | 看菜单栏图标。两条竖线是 Paused：点 Resume 或按 `Ctrl+Option+V`。菜单里有 Permissions 是缺权限：授权后点 `Check Again`，仍不行就退出重开。当前应用在排除列表里（默认 Terminal、iTerm2、Emacs）时不拦截是正常的。读不出当前焦点能不能编辑时，Supervim 也会把按键全部交给应用，以免吞掉正在输入的字：点一下窗口里的内容再试 |
| 系统设置里已经打开了 Supervim，仍提示缺权限 | 那一行属于旧版本。选中它，点减号删除，再把现在的 Supervim 加回去并打开。从 0.1.2 及更早版本升级时需要做一次 |
| 命令键被打进了输入框 | 焦点在输入框里，当前是 Insert。按 `Esc` 回到 Normal |
| `j` / `k` 滚的不是想要的区域 | 把鼠标指针移到要滚动的区域上再按 |
| `H` `L` `J` `K` `yy` 没反应 | 这几个键只在上面列出的浏览器里生效 |
| 微信里按 `f` 没有标签，提示「需要“屏幕录制”权限才能在此应用显示标签」 | 微信读不到辅助功能元素，Supervim 改用窗口截图和本机文字识别来标标签。到「系统设置 → 隐私与安全性 → 屏幕录制」（macOS 15 叫「录屏与系统录音」）打开 Supervim，然后退出重开 |
| 微信里标签出现得慢 | 标签要等文字识别，大约 1 秒。这是已知问题 |
| 微信里 `gi` 点的位置不对 | 微信没有可读的输入框，`gi` 点的是窗口底部输入区的估计位置。直接用鼠标点输入框即可 |
| 按 `f` 提示「没找到可点击元素」 | 辅助功能和文字识别都没有在这个窗口里找到可点的目标 |
| 多显示器上标签位置不对 | 先升级到最新版（v0.1.4 起标签按目标所在的屏幕放置）。仍然不对，就打开调试日志，按一次 `f`，把日志里 `hint-screen`、`hint-panel`、`hint-label` 开头的行附在 [issue](https://github.com/lijigang/supervim/issues) 里 |

### 调试日志

默认关闭。打开后退出并重开 Supervim：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool true
```

日志写在 `~/Library/Logs/Supervim.log`。用完关掉：

```bash
defaults write com.lijigang.supervim SupervimDebugLog -bool false
```

## 开发

需要 macOS 13+ 和带 Swift 6 的 Xcode。

```bash
swift build                 # 构建
swift test                  # 运行 XCTest
scripts/assemble-app.sh     # 组装调试版 build/Supervim.app
open build/Supervim.app
```

打包 DMG、发布、CI 和覆盖率门槛见 [开发说明](docs/development.md)。

```text
Sources/SupervimCore      纯逻辑：模式机、按键解析、命令表、标签、设置。不依赖 AppKit
Sources/SupervimSystem    系统适配：事件钩子、辅助功能扫描、点击和滚动、浮层、文字识别
Sources/Supervim          菜单栏应用入口，设置窗口和权限窗口
Tests/                    XCTest
Tools/UISnapshots         把界面渲染成 docs/ui-polish/ 里的 PNG
scripts/                  组装 .app、打包和签名 DMG、覆盖率、图标
App/Supervim/Info.plist   应用包清单
Resources/                应用图标
docs/                     宪法、规格、计划、验收清单和各版本的记录
.github/workflows/        CI 和 Release
```

文档：[宪法](docs/constitution.md) · [规格](docs/spec.md) · [计划](docs/plan.md) · [任务](docs/tasks.md) · [手工验收清单](docs/manual-acceptance.md) · [全部文档](docs/README.md)
