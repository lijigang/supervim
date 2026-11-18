# 界面打磨 / UI polish

状态：视觉层。扫描、命令、标签落点的数学都没有改。`HintGeometry` 仍决定标签放在哪；这里只改标签内部的形状、颜色、字体和阴影所占的边距。

This pass changes what Supervim draws. It does not change scanning, command handling, or the math that places a hint label. `HintGeometry` still decides where a label goes. Only the size of the badge passed to it changes: since v0.1.5 it is smaller than in v0.1.4, because the padding shrank. The shadow margin is the same.

## 视觉语言

跟着应用图标走：浅灰圆角方块（`#F7F7F8` → `#E9E9EC`）和一块绿色的普通模式光标（`#34C759`）。界面保持少、静、对齐，亮色和暗色都用同一套角色。

The app icon is the palette: a light-gray rounded square and one green normal-mode cursor. Every surface uses that gray for fills and that green as a mark. Text that sits on the gray uses a darker green, `#0F7A32`, because the icon green is too light for 12pt type on `#F7F7F8` (contrast about 2.2:1). On the dark fill `#242426` the icon green itself is the matched-prefix color (about 6.5:1). Fills are 0.97 (light) and 0.96 (dark) so a label stays readable on white, black, yellow, blue, red, and the icon green. Increase Contrast and Reduce Transparency make the fill opaque and the hairline heavier.

## 各块怎么画

v0.1.5 在同一套配色里把每一块重画了一遍，目标是更小、更齐、边更细。

- **提示标签。** 圆角 5 的灰底，一条 1pt 的细边（文字色的 22%），一层很轻的阴影，左侧 2.5 × 11pt 的绿色光标条，SF Mono Semibold 12。已输入的前缀变绿，字重不变，所以键入时标签不变宽、不抖。单字母标签的底约 24 × 19pt（v0.1.4 约 29 × 21pt）。比较大小写不敏感，显示仍用标签自己的大写。阴影在标签矩形内部的 4pt 边距里，不改 `HintGeometry` 的公式。第一次出现时面板用 0.05s 淡入；已经可见时继续输入不再重播。减弱动态效果时不淡入。提高对比度时底不透明、边加粗、阴影不再发散；不以颜色区分时已输入的前缀加下划线。
- **菜单栏。** 状态是 16pt 模板图像，系统负责着色。三个形状都由和图标里一样的圆角条组成：Normal（含 Hint）是一块竖条，Insert 是带上下横线的细竖线，Paused 是两条竖条。平时不写文字；「没找到可点击元素」出现时，文字排在图标旁边。VoiceOver 仍读模式名。
- **提示条。** 「没找到可点击元素」在指针所在的屏幕顶部显示成一个胶囊：和标签相同的底色、细边、阴影，文字前是绿色光标条。
- **菜单项。** Pause / Resume / Settings / Quit / Permissions 用系统符号 `pause.fill`、`play.fill`、`gearshape`、`power`、`lock.fill`。标题和启用状态仍来自原来的菜单快照。
- **帮助。** `?` 打开的浮层按 Scroll、Hints、Find 和 Navigation、Modes 分成两列，这样不用滚动（浮层不接收鼠标）。标题左边是图标；每组标题是加了字距的小号大写字，前面一小块绿色光标；按键是等宽字的键帽，下缘深一线，像一颗键；同一组里键帽这一列等宽，说明左对齐。右上角用两个键帽写「? esc to close」。只有快捷键、承诺的应用，或和 Vimium 的差异才出现在第二行。圆角 16。底是 `NSVisualEffectView` 的 HUD 材质，上面再铺一层灰，保证快照和任意桌面上都能读。浮层居中在鼠标所在的显示器上。行的位置仍由 `HelpMetrics` 决定，没有改。
- **权限窗口。** 系统标题栏窗口。图标和圆体标题下面是一句要做什么；要打开的权限各占卡片里的一行，右侧一个「Open Settings」按钮（悬停提示和 VoiceOver 读原来的完整标题）；其余几段背景说明用小一号的次要色。
- **设置窗口。** 登录启动是卡片里的一行加一个开关。排除的应用是一张卡片，每行一个等宽字的 bundle id 和右侧的 Remove。没有排除项时卡片里写「Nothing excluded.」。
- **查找和标记。** 没有单独的查找浮层或标记浮层。`/` 仍是应用自己的查找快捷键，标记不在规格里。帮助页里的 Find 一组就是它们在界面上的样子。

Hint labels are rounded gray pills (radius 5) with a 1pt hairline, a soft shadow, and a 2.5 × 11pt green cursor bar. The font is SF Mono Semibold 12 for the whole label; the typed prefix only changes color, so a label keeps its width while it is typed. A one-letter pill is about 24 × 19pt, down from about 29 × 21pt. The shadow lives inside a 4pt margin that is part of the badge size passed to the unchanged placement function. The panel fades in over 0.05s once; further keystrokes do not replay it. Reduce Motion skips the fade. Increase Contrast makes the fill opaque and the edge heavier, and the shadow loses its blur.

The menu-bar status item is a 16pt template image built from the rounded bar of the app icon: one block for Normal (Hint stays on that title), a thin beam with serifs for Insert, two bars for Paused. The miss text `没找到可点击元素` sits beside the glyph and also appears as a capsule toast, in the label's own style, on the display under the pointer.

The help sheet is two columns with the icon mark by the title, a small green cursor block before each section name, key caps with a darker lower lip, one key-cap column width per section, and `? esc to close` written with key caps. Row positions still come from `HelpMetrics`. The permission window puts each missing permission on a row of one card with its own button, and sets the background paragraphs smaller in the secondary color. The settings window uses a switch for launch at login and one card for the excluded apps.

There is no find overlay and no marks overlay. `/` is still the app's own find shortcut. The Find group in help is the on-screen form of that command.

## 预览图

`docs/ui-polish/` 里的 PNG 是 macOS CI 用真正的 AppKit 视图离屏画出来的，取自 `ui-snapshots` artifact（`scripts/render-ui-snapshots.sh`），2 倍像素。v0.1.4 以前这里放的是在 Linux 上用 DejaVu 字体画的设计稿，生成它们的 `scripts/render_ui_previews.py` 已经删掉：它画的是旧设计，而且字体不对。

The PNGs in `docs/ui-polish/` are the real AppKit views, rendered offscreen by macOS CI at 2x and copied from the `ui-snapshots` artifact. Earlier versions kept Linux-drawn design previews here; the script that drew them is removed.

- `docs/ui-polish/hints-light.png`、`docs/ui-polish/hints-dark.png`
- `docs/ui-polish/help-light.png`、`docs/ui-polish/help-dark.png`
- `docs/ui-polish/banner-light.png`、`docs/ui-polish/banner-dark.png`
- `docs/ui-polish/status-light.png`、`docs/ui-polish/status-dark.png`
- `docs/ui-polish/menu-light.png`、`docs/ui-polish/menu-dark.png`
- `docs/ui-polish/permissions-light.png`、`docs/ui-polish/permissions-dark.png`
- `docs/ui-polish/settings-light.png`、`docs/ui-polish/settings-dark.png`
- `docs/ui-polish/hints-contrast-light.png`、`docs/ui-polish/hints-contrast-dark.png`（提高对比度 / Increase Contrast）

CI 每次运行都会重新画这些图，并且同时画出改版前的黄标签和奶油色帮助页（`legacy-*.png`）作对照。要更新这里的图，从一次 CI 运行下载 `ui-snapshots`，把 `polished-*.png` 按上面的名字复制过来。

## 没在真机上核对的事

这次没有在一台物理 Mac 上打开菜单栏应用。淡入、HUD 毛玻璃、模板图标在系统浅色和深色菜单栏里的着色、多显示器上的实际落点，都以 CI 的离屏 PNG 和代码为准。离屏快照里的毛玻璃没有桌面可以模糊，所以帮助页的灰底是材质后面的保底色。
