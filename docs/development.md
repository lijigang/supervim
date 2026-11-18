# 开发说明

安装和使用见 [README](../README.md)。这一页讲构建、打包、发布和 CI。

## 环境

- macOS 13 或更高
- Xcode，提供 Swift 6 工具链和 AppKit

Linux 上可以编译并运行纯逻辑测试，菜单栏应用不能在 Linux 上运行。

## 构建和运行

```bash
swift build
swift test
scripts/assemble-app.sh
open build/Supervim.app
```

`scripts/assemble-app.sh` 把调试版二进制装进 `build/Supervim.app`。SwiftPM 是唯一的构建描述，没有 Xcode 工程，原因写在 [计划](plan.md#任务-1-的应用包脚手架)。

应用包的 `Info.plist` 设置了 `LSUIElement=true`，bundle id 是 `com.lijigang.supervim`，所以从 Finder 或 `open` 启动时没有 Dock 图标。直接 `swift run Supervim` 时系统不读 `LSUIElement`，程序改用 accessory 激活策略，同样不出现 Dock 图标。

本地组装的 `.app` 没有用稳定证书签名。每次重新构建后，系统可能要求重新授予辅助功能和输入监控。

调试日志除了 README 里的 `defaults write`，也可以用环境变量 `SUPERVIM_LOG=1` 打开。日志在 `~/Library/Logs/Supervim.log`。

## 工程结构

```text
Package.swift                  SwiftPM 描述，macOS 13+，Swift 6
Sources/SupervimCore           纯逻辑，不导入 AppKit 或事件框架：模式机、按键解析、命令表、标签、设置、权限引导、帮助
Sources/SupervimSystem         系统适配：事件钩子、辅助功能扫描、点击和滚动、标签和帮助浮层、文字识别、登录项
Sources/Supervim               菜单栏应用入口，设置窗口和权限窗口
Tools/UISnapshots              把界面渲染成 PNG 的可执行目标
Tests/SupervimCoreTests        纯逻辑的 XCTest
Tests/SupervimSystemTests      系统适配的 XCTest，系统接口用替身
App/Supervim/Info.plist        应用包清单
Resources/                     应用图标（键帽、绿色小写 f、黄色 F 标签）：AppIcon.svg、AppIcon-1024.png、AppIcon.icns
scripts/                       见下表
.github/workflows/ci.yml       构建、测试、覆盖率、DMG 冒烟
.github/workflows/release.yml  发布 DMG
.taskmaster/tasks/tasks.json   任务 1–15 的机器可读清单
docs/                          见 docs/README.md
```

| 脚本 | 作用 |
| --- | --- |
| `scripts/assemble-app.sh [release] [版本]` | 组装 `build/Supervim.app`。带版本号时写入 `CFBundleShortVersionString` 和 `CFBundleVersion` |
| `scripts/package-dmg.sh <app> <dmg>` | 用 `create-dmg` 打包，带 Applications 拖拽快捷方式。内部调用 `scripts/sign-app.sh` |
| `scripts/sign-app.sh <app>` | 用稳定的自签名证书签名。没有证书时退回 ad-hoc 签名并打印 `WARNING` |
| `scripts/verify-dmg.sh <dmg>` | 挂载 DMG，检查应用、Applications 链接、图标和卷图标 |
| `scripts/make-signing-cert.sh` | 生成稳定签名用的证书，只需做一次。见 [稳定签名](stable-signing.md) |
| `scripts/make-icon.sh` | 从 `scripts/render_icon.py` 生成 `Resources/` 里的图标。`--check` 检查提交的图标和脚本一致。`--artifacts docs/icon` 重画 [图标预览](icon)；其中 Finder 和 Dock 示意图需要本机有 Chrome |
| `scripts/render-ui-snapshots.sh [目录]` | 只在 macOS 上运行，把各个界面渲染成 2 倍 PNG。见 [界面打磨](ui-polish.md) |
| `scripts/*-coverage.sh` | 14 个覆盖率脚本，每个要求对应源文件的行覆盖率不低于 90% |

## 打包 DMG

```bash
scripts/assemble-app.sh release 0.1.0
brew install create-dmg
scripts/package-dmg.sh build/Supervim.app build/Supervim-0.1.0.dmg
scripts/verify-dmg.sh build/Supervim-0.1.0.dmg
```

不写版本号时，沿用 `App/Supervim/Info.plist` 里的 `0.1.0` 和 `1`。

环境变量 `SUPERVIM_SIGNING_P12_BASE64` 和 `SUPERVIM_SIGNING_P12_PASSWORD` 都有值时，`sign-app.sh` 用稳定证书签名；缺任何一个就退回 ad-hoc 签名，这样的构建每次安装都要重新授权。证书的生成和配置见 [稳定签名](stable-signing.md)。发布物没有公证。

## 发布

两种方式用一种即可：

- 推送 tag，例如 `v0.1.6`。
- 在 GitHub Actions 里手动运行 Release 工作流，填版本号 `0.1.6`。

工作流在 `macos-latest` 上做 release 构建，把版本号写进 `Info.plist`，打包并校验 DMG，然后创建 GitHub Release 并上传 `Supervim-<版本>.dmg`。推 tag 时如果这个 Release 里已经有同名 DMG，工作流会跳过重建。

## CI

每次 push 和 pull request 都在 `macos-latest` 上运行 `.github/workflows/ci.yml`：

1. `swift build` 和 `swift test`。
2. `scripts/render-ui-snapshots.sh`，结果作为 `ui-snapshots` artifact 上传。
3. 14 个覆盖率脚本。
4. `scripts/make-icon.sh --check`。
5. `scripts/assemble-app.sh`，并检查 `Info.plist` 里的 `LSUIElement`、bundle id、版本号、`CFBundleIconFile` 和应用包里的 `AppIcon.icns`。
6. 打包 DMG，挂载校验，作为 `Supervim-dmg` artifact 上传。

只在 macOS 上编译的 AppKit 和系统胶水代码不计入覆盖率门槛。

## 界面预览图

`docs/ui-polish/` 里的 PNG 是 CI 用真实的 AppKit 视图离屏渲染的。要更新它们，从一次 CI 运行下载 `ui-snapshots`，把 `polished-*.png` 按 [界面打磨](ui-polish.md#预览图) 里列出的名字复制过来。README 用路径引用这些图，替换文件即可，不用改 README。

## 任务清单和工作流工具

仓库里没有 spec-kit，也没有 task-master CLI。`.taskmaster/tasks/tasks.json` 是按上游 schema 手写的，说明见 [任务文档](tasks.md#task-master-格式)。`TaskGraphTests` 把任务的依赖和状态锁进了测试，改任务状态时要同时改这两处。

各任务的测试记录在 `docs/task1-test-evidence.md` 到 `docs/task15-test-evidence.md`。还没有在真机上做过的项目收在 [手工验收清单](manual-acceptance.md)。
