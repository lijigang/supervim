#if canImport(AppKit)
import AppKit

/// The two mock windows the labels are previewed over. Every name, address
/// and message in them is made up.
@MainActor
enum PreviewScenes {
    static let browser = PreviewScene(
        name: "browser",
        size: NSSize(width: 700, height: 440),
        build: drawBrowser
    )

    static let chat = PreviewScene(
        name: "chat",
        size: NSSize(width: 540, height: 440),
        build: drawChat
    )

    // MARK: Browser

    /// A browser window on an article page: tab strip, toolbar, site header,
    /// an article with inline links and tags, and a sidebar with a dense
    /// list and a form.
    private static func drawBrowser(_ b: SceneBuilder) {
        let p = b.palette
        let width: CGFloat = 700
        let height: CGFloat = 440
        b.fill(NSRect(x: 0, y: 0, width: width, height: height), p.page)

        // Tab strip.
        b.fill(NSRect(x: 0, y: 0, width: width, height: 38), p.chrome)
        for (index, color) in [UInt32(0xFF5F57), 0xFEBC2E, 0x28C840].enumerated() {
            let light = NSRect(x: 14 + CGFloat(index) * 20, y: 13, width: 12, height: 12)
            b.oval(light, rgb(color))
            b.target(light, role: "AXButton")
        }
        let tabs: [(title: String, active: Bool)] = [
            ("Tideline Weekly · Issue 48", true),
            ("Release notes", false),
            ("Inbox (3)", false),
        ]
        var tabX: CGFloat = 88
        for tab in tabs {
            let frame = NSRect(x: tabX, y: 5, width: 172, height: 28)
            if tab.active {
                b.fill(frame, p.toolbar, radius: 7)
            }
            b.symbol(
                "globe",
                center: NSPoint(x: frame.minX + 15, y: frame.midY),
                pointSize: 11,
                color: tab.active ? p.secondary : p.tertiary
            )
            b.text(
                tab.title,
                x: frame.minX + 28,
                y: frame.minY + 6,
                size: 12,
                weight: tab.active ? .medium : .regular,
                color: tab.active ? p.text : p.secondary,
                maxWidth: 118
            )
            b.symbol(
                "xmark",
                center: NSPoint(x: frame.maxX - 14, y: frame.midY),
                pointSize: 8,
                weight: .semibold,
                color: p.tertiary
            )
            b.target(frame, role: "AXTab")
            tabX += 176
        }
        b.iconButton(
            "plus",
            in: NSRect(x: tabX + 4, y: 7, width: 24, height: 24),
            pointSize: 12,
            weight: .medium,
            color: p.secondary
        )

        // Toolbar.
        b.fill(NSRect(x: 0, y: 38, width: width, height: 44), p.toolbar)
        b.hairline(x: 0, y: 82, width: width)
        let leading = ["chevron.left", "chevron.right", "arrow.clockwise"]
        for (index, name) in leading.enumerated() {
            b.iconButton(
                name,
                in: NSRect(x: 12 + CGFloat(index) * 34, y: 46, width: 28, height: 28),
                pointSize: 14,
                weight: .medium,
                color: index == 1 ? p.tertiary : p.secondary
            )
        }
        let address = NSRect(x: 122, y: 46, width: 444, height: 28)
        b.fill(address, p.field, radius: 8)
        b.symbol("lock.fill", center: NSPoint(x: address.minX + 16, y: address.midY), pointSize: 10, color: p.secondary)
        b.text("tideline.example/weekly/issue-48", x: address.minX + 28, y: address.minY + 6, size: 12.5, color: p.text)
        b.target(address, role: "AXTextField")
        let trailing = ["square.and.arrow.up", "bookmark", "ellipsis"]
        for (index, name) in trailing.enumerated() {
            b.iconButton(
                name,
                in: NSRect(x: 578 + CGFloat(index) * 34, y: 46, width: 28, height: 28),
                pointSize: 14,
                weight: .medium,
                color: p.secondary
            )
        }

        // Site header.
        let mark = NSRect(x: 24, y: 94, width: 22, height: 22)
        b.fill(mark, rgb(0x14B8A6), radius: 6)
        b.centeredText("T", in: mark, size: 13, weight: .heavy, color: .white)
        let wordmark = b.text("Tideline", x: 53, y: 94, size: 17, weight: .bold, color: p.text)
        b.target(mark.union(wordmark), role: "AXLink")
        var navX: CGFloat = 150
        for (index, item) in ["Latest", "Guides", "Podcast", "Newsletter", "About"].enumerated() {
            let frame = b.link(
                item, x: navX, y: 97, size: 13, weight: .medium,
                color: index == 0 ? p.text : p.secondary
            )
            navX = frame.maxX + 20
        }
        let search = NSRect(x: 478, y: 92, width: 126, height: 26)
        b.fill(search, p.raised, radius: 13)
        b.symbol("magnifyingglass", center: NSPoint(x: search.minX + 15, y: search.midY), pointSize: 11, color: p.secondary)
        b.text("Search", x: search.minX + 27, y: search.minY + 5, size: 12.5, color: p.tertiary)
        b.target(search, role: "AXTextField", subrole: "AXSearchField")
        let signIn = NSRect(x: 614, y: 92, width: 62, height: 26)
        b.fill(signIn, p.accent, radius: 6)
        b.centeredText("Sign in", in: signIn, size: 12, weight: .semibold, color: .white)
        b.target(signIn, role: "AXButton")
        b.hairline(x: 24, y: 128, width: width - 48)

        // Article.
        b.text("ISSUE 48  ·  ENGINEERING", x: 24, y: 142, size: 10.5, weight: .semibold, color: p.secondary, kern: 0.6)
        let first = b.text("The keyboard-first desktop:", x: 24, y: 158, size: 21, weight: .bold, color: p.text)
        let second = b.text("what changes when you stop reaching", x: 24, y: 184, size: 21, weight: .bold, color: p.text)
        b.target(first.union(second), role: "AXLink")
        var bylineX: CGFloat = 24
        bylineX = b.text("By ", x: bylineX, y: 218, size: 12, color: p.secondary).maxX
        bylineX = b.link("Mara Lindqvist", x: bylineX, y: 218, size: 12, weight: .medium).maxX
        bylineX = b.text("  ·  12 min read  ·  ", x: bylineX, y: 218, size: 12, color: p.secondary).maxX
        b.link("64 comments", x: bylineX, y: 218, size: 12, weight: .medium)
        let paragraphEnd = b.paragraph(
            [
                ("Most of what we click is text we could have typed. This issue looks at ", false),
                ("hint-based navigation", true),
                (", the ", false),
                ("accessibility tree", true),
                (" it relies on, and why ", false),
                ("small labels are tiring to find", true),
                (" on a dense page. We measured how long a reader takes to spot a label at four sizes.", false),
            ],
            x: 24, y: 244, width: 424, size: 13, lineHeight: 19
        )
        var chipX: CGFloat = 24
        let chipY = paragraphEnd + 8
        for tag in ["swift", "accessibility", "macos", "vim", "typography"] {
            let textWidth = b.measure(tag, size: 12, weight: .medium).width
            let chip = NSRect(x: chipX, y: chipY, width: textWidth + 20, height: 24)
            b.fill(chip, p.raised, radius: 12)
            b.centeredText(tag, in: chip, size: 12, weight: .medium, color: p.secondary)
            b.target(chip, role: "AXLink")
            chipX = chip.maxX + 8
        }
        let moreY = chipY + 38
        b.text("MORE FROM THIS ISSUE", x: 24, y: moreY, size: 10.5, weight: .semibold, color: p.secondary, kern: 0.6)
        let more = [
            ("doc.text", "Reading the AX tree without blocking the main thread", "8 min"),
            ("textformat", "A field guide to label alphabets", "5 min"),
        ]
        for (index, item) in more.enumerated() {
            let y = moreY + 20 + CGFloat(index) * 25
            b.symbol(item.0, center: NSPoint(x: 32, y: y + 9), pointSize: 12, color: p.secondary)
            b.link(item.1, x: 48, y: y, size: 13, weight: .medium, color: p.text)
            b.trailingText(item.2, right: 448, y: y + 1, size: 11.5, color: p.tertiary)
        }

        // Sidebar: a dense list, then a form.
        let trending = NSRect(x: 472, y: 142, width: 204, height: 178)
        b.fill(trending, p.raised, radius: 10)
        b.text("Trending", x: trending.minX + 14, y: trending.minY + 11, size: 13, weight: .semibold, color: p.text)
        let stories = [
            "Why yellow labels still win",
            "Fourteen points is the new twelve",
            "Homing keys, ranked",
            "Designing for the glance",
            "Dark mode is not one color",
            "The cost of a mouse trip",
        ]
        for (index, story) in stories.enumerated() {
            let y = trending.minY + 38 + CGFloat(index) * 22
            b.text("\(index + 1)", x: trending.minX + 14, y: y, size: 12.5, weight: .semibold, color: p.tertiary)
            b.link(story, x: trending.minX + 30, y: y, size: 12.5, color: p.text)
        }
        let subscribe = NSRect(x: 472, y: 330, width: 204, height: 98)
        b.fill(subscribe, p.raised, radius: 10)
        b.text("Get the weekly issue", x: subscribe.minX + 14, y: subscribe.minY + 10, size: 13, weight: .semibold, color: p.text)
        let email = NSRect(x: subscribe.minX + 12, y: subscribe.minY + 34, width: 180, height: 24)
        b.fill(email, p.page, radius: 6)
        b.stroke(email, p.separator, radius: 6)
        b.text("you@example.com", x: email.minX + 9, y: email.minY + 4, size: 12, color: p.tertiary)
        b.target(email, role: "AXTextField")
        let button = NSRect(x: subscribe.minX + 12, y: subscribe.minY + 64, width: 180, height: 24)
        b.fill(button, p.accent, radius: 6)
        b.centeredText("Subscribe", in: button, size: 12, weight: .semibold, color: .white)
        b.target(button, role: "AXButton")
    }

    // MARK: Chat

    /// A chat client in the layout of a desktop messenger: an icon rail, a
    /// list of conversations, and one open conversation with a composer.
    private static func drawChat(_ b: SceneBuilder) {
        let p = b.palette
        let width: CGFloat = 540
        let height: CGFloat = 440
        let rail = b.dark ? rgb(0x1F1F1F) : rgb(0x2E2E2E)
        let list = b.dark ? rgb(0x262626) : rgb(0xF7F7F7)
        let thread = b.dark ? rgb(0x111111) : rgb(0xF5F5F5)
        let incoming = b.dark ? rgb(0x2C2C2C) : rgb(0xFFFFFF)
        let outgoing = b.dark ? rgb(0x3EB575) : rgb(0x95EC69)
        let green = rgb(0x07C160)

        // Icon rail.
        b.fill(NSRect(x: 0, y: 0, width: 56, height: height), rail)
        let me = NSRect(x: 10, y: 20, width: 36, height: 36)
        b.avatar("我", in: me, color: rgb(0x5B8DEF), radius: 6)
        b.target(me, role: "AXButton")
        let railIcons = ["message.fill", "person.2.fill", "cube.fill", "folder.fill", "camera.aperture"]
        for (index, name) in railIcons.enumerated() {
            b.iconButton(
                name,
                in: NSRect(x: 10, y: 74 + CGFloat(index) * 44, width: 36, height: 36),
                pointSize: 17,
                color: index == 0 ? green : rgb(0x9A9A9A)
            )
        }
        for (index, name) in ["iphone", "line.3.horizontal"].enumerated() {
            b.iconButton(
                name,
                in: NSRect(x: 10, y: 356 + CGFloat(index) * 40, width: 36, height: 36),
                pointSize: 16,
                color: rgb(0x9A9A9A)
            )
        }

        // Conversation list.
        b.fill(NSRect(x: 56, y: 0, width: 230, height: height), list)
        let search = NSRect(x: 68, y: 14, width: 172, height: 26)
        b.fill(search, b.dark ? rgb(0x3A3A3A) : rgb(0xE2E2E2), radius: 5)
        b.symbol("magnifyingglass", center: NSPoint(x: search.minX + 14, y: search.midY), pointSize: 11, color: p.secondary)
        b.text("搜索", x: search.minX + 26, y: search.minY + 5, size: 12, color: p.secondary)
        b.target(search, role: "AXTextField", subrole: "AXSearchField")
        let add = NSRect(x: 248, y: 14, width: 26, height: 26)
        b.fill(add, b.dark ? rgb(0x3A3A3A) : rgb(0xE2E2E2), radius: 5)
        b.iconButton("plus", in: add, pointSize: 12, weight: .medium, color: p.secondary)

        let rows: [(name: String, message: String, time: String, glyph: String, color: UInt32, unread: Int)] = [
            ("产品讨论组", "周岚：新版标签我再出一版对比图", "14:32", "产", 0x4C8DF6, 3),
            ("林晓", "好的，下午三点会议室见", "13:05", "林", 0xF2994A, 0),
            ("设计周会", "[链接] 标签配色方案 v3", "11:48", "设", 0x9B6BDF, 12),
            ("文件传输助手", "[文件] label-redesign.pdf", "昨天", "文", 0x2DB67D, 0),
            ("效率周刊", "让键盘接管你的 Mac", "昨天", "效", 0xE5674B, 0),
            ("周末徒步小队", "阿哲：周六七点地铁口集合", "星期一", "周", 0x38B6A0, 1),
        ]
        for (index, row) in rows.enumerated() {
            let frame = NSRect(x: 56, y: 52 + CGFloat(index) * 62, width: 230, height: 62)
            if index == 0 {
                b.fill(frame, b.dark ? rgb(0x3A3A3A) : rgb(0xDEDEDE))
            }
            let picture = NSRect(x: frame.minX + 12, y: frame.minY + 11, width: 40, height: 40)
            b.avatar(row.glyph, in: picture, color: rgb(row.color))
            b.text(row.name, x: picture.maxX + 10, y: frame.minY + 12, size: 13.5, color: p.text, maxWidth: 118)
            b.trailingText(row.time, right: frame.maxX - 10, y: frame.minY + 14, size: 10.5, color: p.tertiary)
            b.text(row.message, x: picture.maxX + 10, y: frame.minY + 34, size: 12, color: p.secondary, maxWidth: 156)
            if row.unread > 0 {
                let count = "\(row.unread)"
                let badgeWidth: CGFloat = count.count > 1 ? 22 : 16
                let badge = NSRect(x: picture.maxX - badgeWidth / 2 - 2, y: picture.minY - 6, width: badgeWidth, height: 16)
                b.fill(badge, rgb(0xFA5151), radius: 8)
                b.centeredText(count, in: badge, size: 10, weight: .semibold, color: .white)
            }
            b.target(frame, role: "AXRow")
        }
        b.verticalHairline(x: 286, y: 0, height: height)

        // Open conversation.
        b.fill(NSRect(x: 287, y: 0, width: width - 287, height: height), thread)
        b.text("产品讨论组 (8)", x: 302, y: 17, size: 15, weight: .medium, color: p.text)
        b.iconButton("ellipsis", in: NSRect(x: 500, y: 12, width: 28, height: 28), pointSize: 15, weight: .medium, color: p.secondary)
        b.hairline(x: 287, y: 52, width: width - 287)

        let firstPicture = NSRect(x: 298, y: 66, width: 32, height: 32)
        b.avatar("岚", in: firstPicture, color: rgb(0xD96BA0))
        b.target(firstPicture, role: "AXImage")
        b.fill(NSRect(x: 338, y: 66, width: 186, height: 34), incoming, radius: 6)
        b.text("标签的字是不是可以再大一点？", x: 348, y: 74, size: 13, color: p.text)

        let myPicture = NSRect(x: 500, y: 112, width: 32, height: 32)
        b.avatar("我", in: myPicture, color: rgb(0x5B8DEF))
        b.target(myPicture, role: "AXImage")
        b.fill(NSRect(x: 348, y: 112, width: 144, height: 34), outgoing, radius: 6)
        b.text("可以，我出四个方向", x: 358, y: 120, size: 13, color: rgb(0x111111))

        let secondPicture = NSRect(x: 298, y: 158, width: 32, height: 32)
        b.avatar("哲", in: secondPicture, color: rgb(0x38B6A0))
        b.target(secondPicture, role: "AXImage")
        b.fill(NSRect(x: 338, y: 158, width: 186, height: 54), incoming, radius: 6)
        b.text("对比图放这里了：", x: 348, y: 166, size: 13, color: p.text)
        b.link("tideline.example/labels", x: 348, y: 186, size: 13)

        let file = NSRect(x: 338, y: 222, width: 186, height: 56)
        b.fill(file, incoming, radius: 6)
        b.text("label-redesign.pdf", x: file.minX + 10, y: file.minY + 10, size: 12.5, color: p.text)
        b.text("2.4 MB", x: file.minX + 10, y: file.minY + 31, size: 10.5, color: p.secondary)
        b.symbol("doc.fill", center: NSPoint(x: file.maxX - 24, y: file.midY), pointSize: 24, color: rgb(0xFA5151))
        b.target(file, role: "AXButton")

        // Composer.
        b.hairline(x: 287, y: 290, width: width - 287)
        b.fill(NSRect(x: 287, y: 291, width: width - 287, height: height - 291), b.dark ? rgb(0x1E1E1E) : rgb(0xFFFFFF))
        let tools = ["face.smiling", "folder", "scissors", "text.bubble"]
        for (index, name) in tools.enumerated() {
            b.iconButton(
                name,
                in: NSRect(x: 298 + CGFloat(index) * 32, y: 298, width: 24, height: 24),
                pointSize: 15,
                color: p.secondary
            )
        }
        for (index, name) in ["phone", "video"].enumerated() {
            b.iconButton(
                name,
                in: NSRect(x: 474 + CGFloat(index) * 32, y: 298, width: 24, height: 24),
                pointSize: 15,
                color: p.secondary
            )
        }
        let input = NSRect(x: 296, y: 328, width: 236, height: 66)
        b.text("四个方向都渲染好了", x: input.minX + 4, y: input.minY + 4, size: 13, color: p.text)
        b.target(input, role: "AXTextArea")
        let send = NSRect(x: 462, y: 402, width: 66, height: 26)
        b.fill(send, b.dark ? rgb(0x2C2C2C) : rgb(0xE9E9E9), radius: 4)
        b.centeredText("发送(S)", in: send, size: 12, color: green)
        b.target(send, role: "AXButton")
    }
}
#endif
