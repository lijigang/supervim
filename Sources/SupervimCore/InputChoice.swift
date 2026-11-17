import Foundation

/// One text field already copied out of an accessibility tree.
public struct InputCandidate: Equatable, Sendable {
    public var role: String?
    public var subrole: String?
    public var frame: HintRect
    public var path: [Int]
    public var editable: Bool
    public var identity: String?
    public var inFocusedWindow: Bool

    public init(
        role: String?,
        subrole: String?,
        frame: HintRect,
        path: [Int],
        editable: Bool,
        identity: String?,
        inFocusedWindow: Bool
    ) {
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.path = path
        self.editable = editable
        self.identity = identity
        self.inFocusedWindow = inFocusedWindow
    }
}

/// Picks the field `gi` should focus.
///
/// Eligible roles are `AXTextField`, `AXTextArea`, `AXComboBox`, and
/// `AXSearchField`. The field has to be editable and on screen. Fields in
/// the focused window win. The last focused field wins when it is still
/// there. Otherwise the bottom-most, then the largest, field wins. That is
/// the composer rather than a search field at the top of the window.
public enum InputChoice {
    public static func isTextInput(role: String?, subrole: String?) -> Bool {
        if subrole == "AXSearchField" {
            return true
        }
        switch role {
        case "AXTextField", "AXTextArea", "AXComboBox":
            return true
        default:
            return false
        }
    }

    public static func best(
        _ candidates: [InputCandidate],
        lastFocusedIdentity: String?,
        window: HintRect?
    ) -> InputCandidate? {
        let eligible = candidates.filter { candidate in
            candidate.editable
                && isTextInput(role: candidate.role, subrole: candidate.subrole)
                && candidate.frame.isUsable
                && onScreen(candidate.frame, window: window)
        }
        guard !eligible.isEmpty else {
            return nil
        }
        let focused = eligible.filter(\.inFocusedWindow)
        let pool = focused.isEmpty ? eligible : focused
        if let lastFocusedIdentity,
           let match = pool.first(where: { $0.identity == lastFocusedIdentity }) {
            return match
        }
        return pool.max { lhs, rhs in
            rank(lhs) < rank(rhs)
        }
    }

    /// A point inside the bottom of the window, where a chat composer sits
    /// when the accessibility tree has no text field. Nil for a tiny window.
    public static func bottomCenter(of window: HintRect) -> HintPoint? {
        guard window.isUsable, window.width >= 80, window.height >= 80 else {
            return nil
        }
        let inset = min(48, window.height * 0.12)
        let y = window.y + window.height - inset
        guard y > window.y, y < window.y + window.height else {
            return nil
        }
        return HintPoint(x: window.x + window.width / 2, y: y)
    }

    public static func logLine(decision: String, fields: [String]) -> String {
        (["gi decision=\(decision)"] + fields).joined(separator: " ")
    }

    private static func onScreen(_ frame: HintRect, window: HintRect?) -> Bool {
        guard let window else {
            return true
        }
        guard window.isUsable, frame.isUsable else {
            return false
        }
        let left = max(frame.x, window.x)
        let right = min(frame.x + frame.width, window.x + window.width)
        let top = max(frame.y, window.y)
        let bottom = min(frame.y + frame.height, window.y + window.height)
        return right - left > 0 && bottom - top > 0
    }

    /// Higher is better: lower on the screen, then larger, then an earlier path.
    private static func rank(_ candidate: InputCandidate) -> (Double, Double, Int) {
        let bottom = candidate.frame.y + candidate.frame.height
        let area = candidate.frame.width * candidate.frame.height
        let path = candidate.path.reduce(0) { $0 &* 100 + $1 }
        return (bottom, area, -path)
    }
}
