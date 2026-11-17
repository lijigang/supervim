# 界面打磨 / UI polish

状态：视觉层。扫描、命令、标签落点的数学都没有改。`HintGeometry` 仍决定标签放在哪；这里只改标签内部的形状、颜色、字体和阴影所占的边距。

This pass changes what Supervim draws. It does not change scanning, command handling, or the math that places a hint label. `HintGeometry` still decides where a label goes. The badge is larger because its own padding and shadow margin grew.

## 视觉语言

跟着应用图标走：浅灰圆角方块（`#F7F7F8` → `#E9E9EC`）和一块绿色的普通模式光标（`#34C759`）。界面保持少、静、对齐，亮色和暗色都用同一套角色。

The app icon is the palette: a light-gray rounded square and one green normal-mode cursor. Every surface uses that gray for fills and that green as a mark. Text that sits on the gray uses a darker green, `#0F7A32`, because the icon green is too light for 12pt type on `#F7F7F8` (contrast about 2.2:1). On the dark fill `#242426` the icon green itself is the matched-prefix color (about 6.5:1). Fills are 0.97 (light) and 0.96 (dark) so a label stays readable on white, black, yellow, blue, red, and the icon green. Increase Contrast and Reduce Transparency make the fill opaque and the hairline heavier.

## 各块怎么画

- **提示标签。** 圆角 6 的灰底，左侧 3pt 绿色光标条，SF Mono：已输入的前缀是粗体，剩下的是中等字重。比较大小写不敏感，显示仍用标签自己的大写。阴影在标签矩形内部的 4pt 边距里，不改 `HintGeometry` 的公式。出现时整个面板用 0.14s 淡入；已经可见时继续输入不再重播。减弱动态效果时不淡入。
- **菜单栏。** 状态是 16pt 模板图像，系统负责着色。Normal（含 Hint）是竖条光标，Insert 是 I 形，Paused 是两条竖杠。没有视觉模式，规格里也没有。平时不写文字；「没找到可点击元素」出现时，文字排在图标旁边，并在指针所在的屏幕顶部放一条同样语言的横幅。VoiceOver 仍读模式名。
- **菜单项。** Pause / Resume / Settings / Quit / Permissions 用系统符号 `pause.fill`、`play.fill`、`gearshape`、`power`、`lock.fill`。标题和启用状态仍来自原来的菜单快照。
- **帮助。** `?` 打开的浮层按 Scroll、Hints、Find 和 Navigation、Modes 分成两列，这样不用滚动（浮层不接收鼠标）。按键是等宽字的键帽。只有快捷键、承诺的应用，或和 Vimium 的差异才出现在第二行。标题用系统圆体。底是 `NSVisualEffectView` 的 HUD 材质，上面再铺一层灰，保证快照和任意桌面上都能读。浮层居中在鼠标所在的显示器上。
- **权限和设置。** 系统标题栏窗口，内容区用图标、圆体标题、13pt 正文，链接和主按钮是系统圆角按钮。设置里的 bundle id 用等宽字体。
- **查找和标记。** 没有单独的查找浮层或标记浮层。`/` 仍是应用自己的查找快捷键，标记不在规格里。帮助页里的 Find 一组就是它们在界面上的样子。

Hint labels are rounded gray rectangles with a 3pt green cursor bar. The typed prefix is SF Mono Bold; the rest is SF Mono Medium. The shadow lives inside a 4pt margin that is part of the badge size passed to the unchanged placement function. The panel fades in over 0.14s once; further keystrokes do not replay it. Reduce Motion skips the fade.

The menu-bar status item is a 16pt template image: a cursor bar for Normal (Hint stays on that title), an I-beam for Insert, two bars for Paused. There is no visual-mode glyph because the mode machine has no visual mode. The miss text `没找到可点击元素` sits beside the glyph and also appears as a toast on the display under the pointer.

Menu items use system symbols. The help sheet is two columns (Scroll / Hints / Find, and Navigation / Modes) with key caps, an SF Rounded title, and an `NSVisualEffectView` HUD material under the gray tint. It is centered on the screen that contains the pointer. Permission and settings windows keep the system title bar and use the icon mark, rounded buttons, and monospaced bundle identifiers.

There is no find overlay and no marks overlay. `/` is still the app's own find shortcut. The Find group in help is the on-screen form of that command.

## 预览图

`docs/ui-polish/` 里的 PNG 是同一套配色的设计预览，在没有 AppKit 的环境里用 DejaVu 代替 SF Mono / SF Rounded 画的。macOS CI 会用真正的视图再画一遍，包括改版前的黄标签和奶油色帮助页，亮色和暗色各一份，并上传名为 `ui-snapshots` 的 artifact。

The PNGs in `docs/ui-polish/` are design previews of the palette. They were drawn without AppKit, with DejaVu standing in for SF Mono and SF Rounded. macOS CI renders the real views, including the previous yellow labels and cream help sheet, in light and dark, and uploads them as the `ui-snapshots` artifact.

- `docs/ui-polish/hints-light.png`
- `docs/ui-polish/hints-dark.png`
- `docs/ui-polish/help-light.png`
- `docs/ui-polish/status-and-banner.png`
- `docs/ui-polish/permissions-light.png`

重新生成设计预览需要本机的 Pillow，它不是应用依赖：`python3 scripts/render_ui_previews.py`。CI 上的真实渲染是 `scripts/render-ui-snapshots.sh`。

## 没在真机上核对的事

这次没有在一台物理 Mac 上打开菜单栏应用。淡入、HUD 毛玻璃、模板图标在系统浅色和深色菜单栏里的着色、多显示器上的实际落点，都以 CI 的离屏 PNG 和代码为准。离屏快照里的毛玻璃没有桌面可以模糊，所以帮助页的灰底是材质后面的保底色。
