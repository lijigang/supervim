#if os(macOS)
import AppKit
import CoreGraphics
import Foundation

/// The largest on-screen window of the frontmost process.
///
/// Bounds come from `CGWindowList` and use the same top-left, y-down space as
/// accessibility frames. This is the fallback when the accessibility window
/// has no frame. It does not capture pixels.
public final class CGFrontWindow: FrontWindowReading, @unchecked Sendable {
    public init() {}

    public func frontWindowFrame() -> ActuatorRect? {
        CGFrontWindowList.frontmost()?.frame
    }
}

enum CGFrontWindowList {
    struct Window {
        var id: CGWindowID
        var frame: ActuatorRect
    }

    static func frontmost() -> Window? {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        guard pid != 0 else {
            return nil
        }
        return largestWindow(ownedBy: pid)
    }

    static func largestWindow(ownedBy pid: pid_t) -> Window? {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        var best: Window?
        var bestArea = 0.0
        for info in raw {
            guard let owner = integer(info[kCGWindowOwnerPID as String]), owner == Int(pid) else {
                continue
            }
            let layer = integer(info[kCGWindowLayer as String]) ?? 0
            guard layer == 0 else {
                continue
            }
            let alpha = double(info[kCGWindowAlpha as String]) ?? 1
            guard alpha > 0 else {
                continue
            }
            guard let number = integer(info[kCGWindowNumber as String]), number > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = rect(bounds),
                  frame.width >= 40, frame.height >= 40
            else {
                continue
            }
            let area = frame.width * frame.height
            if area > bestArea {
                bestArea = area
                best = Window(id: CGWindowID(number), frame: frame)
            }
        }
        return best
    }

    private static func rect(_ bounds: [String: Any]) -> ActuatorRect? {
        guard let x = double(bounds["X"]),
              let y = double(bounds["Y"]),
              let width = double(bounds["Width"]),
              let height = double(bounds["Height"]),
              width > 0, height > 0
        else {
            return nil
        }
        return ActuatorRect(x: x, y: y, width: width, height: height)
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? UInt32 {
            return Int(value)
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? CGFloat {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }
}
#endif
