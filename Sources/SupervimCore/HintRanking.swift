import Foundation

/// One candidate the hint ranker can order.
/// `index` is the caller's original position and is the last tie-break.
public struct HintRankItem: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var frame: HintRect
    public var index: Int

    public init(role: String?, subrole: String?, frame: HintRect, index: Int) {
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.index = index
    }
}

/// Orders hint targets so the easiest label lands on the control most likely
/// to be clicked.
///
/// Role comes first: buttons, then links, then tabs, then menu items, then
/// text fields, then generic groups, static text, and images. A control whose
/// shorter side is below `tinySide` sorts after every normal-sized control.
/// Inside a tier, closer to the window center (or the union of the candidates)
/// wins, then closer to the pointer when one was supplied, then larger area,
/// then the original index. Off-screen candidates are dropped when a window
/// is known and at least one candidate still intersects it.
///
/// The order is deterministic. This type does not read the pointer or the
/// accessibility tree.
public enum HintRanking {
    public static let tinySide: Double = 8

    public static func order(
        _ items: [HintRankItem],
        window: HintRect? = nil,
        pointer: HintPoint? = nil
    ) -> [HintRankItem] {
        let visible = onScreen(items, window: window)
        let content = window ?? union(of: visible.map(\.frame))
        let center = content?.center ?? HintPoint(x: 0, y: 0)
        return visible.sorted { lhs, rhs in
            key(lhs, center: center, pointer: pointer) < key(rhs, center: center, pointer: pointer)
        }
    }

    /// Buttons and the other pressable controls, then links, tabs, menu items,
    /// text entry, and everything else.
    public static func tier(role: String?, subrole: String?) -> Int {
        switch subrole {
        case "AXSearchField", "AXSecureTextField":
            return 20
        default:
            break
        }
        switch role {
        case "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
             "AXComboBox", "AXDisclosureTriangle", "AXIncrementor", "AXColorWell":
            return 60
        case "AXLink":
            return 50
        case "AXTab":
            return 40
        case "AXMenuItem":
            return 30
        case "AXTextField", "AXTextArea", "AXSlider":
            return 20
        default:
            return 10
        }
    }

    private static func onScreen(_ items: [HintRankItem], window: HintRect?) -> [HintRankItem] {
        guard let window, window.isUsable else {
            return items
        }
        let visible = items.filter { intersects($0.frame, window) }
        return visible.isEmpty ? items : visible
    }

    private static func intersects(_ frame: HintRect, _ window: HintRect) -> Bool {
        guard frame.isUsable, window.isUsable else {
            return false
        }
        let left = max(frame.x, window.x)
        let right = min(frame.x + frame.width, window.x + window.width)
        let top = max(frame.y, window.y)
        let bottom = min(frame.y + frame.height, window.y + window.height)
        return right - left > 0 && bottom - top > 0
    }

    private static func union(of frames: [HintRect]) -> HintRect? {
        let usable = frames.filter(\.isUsable)
        guard var box = usable.first else {
            return nil
        }
        for frame in usable.dropFirst() {
            let maxX = max(box.x + box.width, frame.x + frame.width)
            let maxY = max(box.y + box.height, frame.y + frame.height)
            box.x = min(box.x, frame.x)
            box.y = min(box.y, frame.y)
            box.width = maxX - box.x
            box.height = maxY - box.y
        }
        return box
    }

    private struct Key: Comparable {
        var tiny: Bool
        var tier: Int
        var distance: Double
        var pointerDistance: Double
        var area: Double
        var index: Int

        static func < (lhs: Key, rhs: Key) -> Bool {
            if lhs.tiny != rhs.tiny {
                return rhs.tiny
            }
            if lhs.tier != rhs.tier {
                return lhs.tier < rhs.tier
            }
            if lhs.distance != rhs.distance {
                return lhs.distance < rhs.distance
            }
            if lhs.pointerDistance != rhs.pointerDistance {
                return lhs.pointerDistance < rhs.pointerDistance
            }
            if lhs.area != rhs.area {
                return lhs.area < rhs.area
            }
            return lhs.index < rhs.index
        }
    }

    private static func key(_ item: HintRankItem, center: HintPoint, pointer: HintPoint?) -> Key {
        let frame = item.frame
        let area = frame.isUsable ? frame.width * frame.height : 0
        let tiny = !frame.isUsable || frame.width < tinySide || frame.height < tinySide
        return Key(
            tiny: tiny,
            tier: -tier(role: item.role, subrole: item.subrole),
            distance: distance(from: frame.center, to: center),
            pointerDistance: pointer.map { distance(from: frame.center, to: $0) } ?? 0,
            area: -area,
            index: item.index
        )
    }

    private static func distance(from: HintPoint, to: HintPoint) -> Double {
        let dx = from.x - to.x
        let dy = from.y - to.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
