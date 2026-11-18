# 文档索引

安装和使用见仓库根目录的 [README](../README.md)。

## 要求和计划

| 文档 | 内容 |
| --- | --- |
| [宪法](constitution.md) | 已批准的原则：原生轻量、不干扰输入、默认 Vimium、测试先行、隐私 |
| [规格 v0.1](spec.md) | 行为要求，文末列出还不能保证的平台行为 |
| [计划](plan.md) | 模块划分、运行路径和线程模型 |
| [任务与依赖](tasks.md) | 任务 1–15 的顺序、依赖和状态 |
| [手工验收清单](manual-acceptance.md) | 还没有在真机上做过的验收项目 |

## 参考

| 文档 | 内容 |
| --- | --- |
| [与 Vimium 的差异](vimium-differences.md) | 偏离 Vimium 的地方，以及浏览器名单 |
| [开发说明](development.md) | 构建、打包、发布、CI、脚本和工程结构 |
| [稳定签名](stable-signing.md) | 为什么升级后权限能保留，证书怎么生成和配置 |
| [界面打磨](ui-polish.md) | 视觉语言，以及 `ui-polish/` 里的预览图怎么来的 |
| [提示标签改版方案](label-redesign.md) | 四个候选标签样式的字体、字号、颜色和形状，`label-redesign/` 里的预览图。默认样式还没有改 |

## 过程记录

| 文档 | 内容 |
| --- | --- |
| [实现过程记录](history.md) | 原来写在 README 里的各任务和 v0.1.5 说明 |
| [v0.1.5 证据](v0.1.5-evidence.md) | 响应、偶发无响应、标签覆盖与重复、外观 |
| [应用图标测试记录](app-icon-test-evidence.md) | 图标的生成和校验 |

任务测试记录：
[1](task1-test-evidence.md) ·
[2](task2-test-evidence.md) ·
[3](task3-test-evidence.md) ·
[4](task4-test-evidence.md) ·
[5](task5-test-evidence.md) ·
[6](task6-test-evidence.md) ·
[7](task7-test-evidence.md) ·
[8](task8-test-evidence.md) ·
[9](task9-test-evidence.md) ·
[10](task10-test-evidence.md) ·
[11](task11-test-evidence.md) ·
[12](task12-test-evidence.md) ·
[13](task13-test-evidence.md) ·
[14](task14-test-evidence.md) ·
[15](task15-test-evidence.md)

修复记录：

| 文档 | 内容 |
| --- | --- |
| [fix-jk-insert-evidence.md](fix-jk-insert-evidence.md) | `Esc` 之后 `j` / `k` 被送回 Insert |
| [fix-hint-offset-evidence.md](fix-hint-offset-evidence.md) | 标签和点击错位，多显示器坐标 |
| [fix-gg-G-evidence.md](fix-gg-G-evidence.md) | `gg` / `G` 在浏览器里滚到顶部和底部 |
| [fix-wechat-hints-evidence.md](fix-wechat-hints-evidence.md) | 微信里按 `f` 没有标签 |
| [fix-wechat-f-v2-evidence.md](fix-wechat-f-v2-evidence.md) | 微信里按 `f` 仍然没有画面，标签字母表 |
| [fix-wechat-vision-gi-evidence.md](fix-wechat-vision-gi-evidence.md) | 微信的滚动、文字识别标签和 `gi` |
