# 与 Vimium 的差异

[宪法](constitution.md) 第 3 条要求默认按键和行为跟随 Vimium，凡是偏离都写进文档。这一页就是那份清单。按键表在 [README](../README.md#按键)。

## 帮助里标出的三处

`?` 打开的帮助里，带 `differs from Vimium` 的只有三行：

| 按键 | Supervim | Vimium |
| --- | --- | --- |
| `F` | 按住 Command 点击。不是右键菜单 | 在新标签页打开链接 |
| `/` | 发送前台应用自己的 `Command+F` | Vimium 自己的查找模式 |
| `?` | 显示由命令表生成的帮助，再按 `?` 或 `Esc` 关闭 | Vimium 自己的帮助页 |

## 帮助里没有标出的差异

| 方面 | Supervim 的行为 |
| --- | --- |
| 没有的功能 | 没有 omnibar、标记（marks）、视觉模式、自定义按键，也没有 `3j` 这种数字前缀 |
| 滚动 | 一下到位，没有平滑滚动 |
| 滚动的位置 | 滚的是鼠标指针下面的可滚动区域。指针不在前台窗口里，或 Normal 被 `Esc` 按住在一个输入框上时，会先移动指针。规则见 [规格](spec.md) 第 4 条 |
| 到头之后 | 在页面顶部按 `k`、在底部按 `j`，按键被吞掉，页面不动，不交给应用 |
| 标签字母 | 字母表是 `fjdkslaghrueiwotypqvbncmxz`：先主键行，再上排，再下排。目标不超过 26 个时全是单字母，最好按的字母分给最可能被点的目标。规格第 1 条写的是 `asdfghjkl` |
| `gi` | 聚焦当前窗口里最合适的文本框，不一定是第一个。没有可读文本框的应用（默认是微信）点窗口底部的估计位置。规则见规格第 5 条 |
| `H` `L` `J` `K` | 只在下面名单里的浏览器里发送快捷键，其他应用里按键被吞掉，什么也不做 |
| `yy` | 先 `Command+L` 聚焦地址栏，再 `Command+C` 复制。不保证复制出来的是规范化的 URL。只在下面名单里的浏览器里发送 |
| `x` `t` `r` | 对任何应用发送 `Command+W`、`Command+T`、`Command+R`，不限于浏览器 |
| 前缀中的 `Esc` | `g` 或 `y` 按了一半时按 `Esc`，除了取消前缀，还会把 `Esc` 交给模式机，这样 Insert 和标签模式也能离开 |

## 浏览器名单

规格只写了「Safari 和 Chromium」，没有给 bundle identifier。下面是实现里采用的标识，没有经过所有者确认，定义在 `Sources/SupervimSystem/Actuator.swift` 的 `PromisedApplications`。

| 浏览器 | Bundle identifier |
| --- | --- |
| Safari | `com.apple.Safari` |
| Chrome | `com.google.Chrome` |
| Chromium | `org.chromium.Chromium` |
| Edge | `com.microsoft.edgemac` |
| Brave | `com.brave.Browser` |
| Arc | `company.thebrowser.Browser` |
| Vivaldi | `com.vivaldi.Vivaldi` |

Firefox 和 Opera 不在名单里。

默认排除列表的三个标识同样没有经过所有者确认：Terminal `com.apple.Terminal`、iTerm2 `com.googlecode.iterm2`、GNU Emacs `org.gnu.Emacs`。

## English

The help sheet marks three rows with `differs from Vimium`: `F` Command-clicks instead of opening a link in a new tab, and it is not a context menu; `/` sends the frontmost app's own `Command+F` instead of Vimium's find mode; `?` shows help generated from Supervim's command table.

These also differ and are not marked on the sheet. There is no omnibar, marks, visual mode, custom keys, or count prefix such as `3j`. Scrolling jumps instead of animating, goes to the scrollable area under the pointer, and may move the pointer first. `k` at the top of a page and `j` at the bottom are swallowed. Hint labels use the alphabet `fjdkslaghrueiwotypqvbncmxz`, single letters first. `gi` focuses the most suitable text field, not necessarily the first. `H` `L` `J` `K` and `yy` send their shortcuts only in the browsers listed above; `x` `t` `r` send `Command+W`, `Command+T`, `Command+R` to any app. `yy` focuses the address bar and copies it, so the result is not guaranteed to be a normalized URL. `Esc` during an unfinished `g` or `y` prefix also reports escape, so Insert and Hint can leave.

The browser and exclusion bundle identifiers were chosen by the implementation and were not confirmed by the owner.
