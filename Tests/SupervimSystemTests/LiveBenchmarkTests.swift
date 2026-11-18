#if os(macOS)
import AppKit
import ApplicationServices
import CoreGraphics
import Vision
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

/// Prints timings for docs/v0.1.5-evidence.md. Nothing here asserts a speed:
/// a shared CI machine is not a stopwatch. The lines start with `BENCH` so
/// they can be read back out of the CI log.
///
/// The accessibility half needs a trusted process and a real window, so it
/// only runs when `SUPERVIM_LIVE_AX_BENCH=1` and skips when either is missing.
final class LiveBenchmarkTests: XCTestCase {
    func testOverlayPresentationTimings() {
        let panel = NonActivatingHintPanel()
        print("BENCH overlay screens=\(NSScreen.screens.count)")
        let cold = Self.milliseconds {
            panel.present(OverlayPresentation(markers: Self.markers(50), policy: .hintLabels))
        }
        panel.hideOverlay()
        print("BENCH overlay cold labels=50 first_ms=\(Self.text(cold))")

        // What the app does: the panel is made and drawn once at launch,
        // before the first `f`.
        let warmed = NonActivatingHintPanel()
        warmed.prewarm()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let afterPrewarm = Self.milliseconds {
            warmed.present(OverlayPresentation(markers: Self.markers(50), policy: .hintLabels))
        }
        warmed.hideOverlay()
        print("BENCH overlay prewarmed labels=50 first_ms=\(Self.text(afterPrewarm))")
        for count in [50, 150, 300] {
            let markers = Self.markers(count)
            var first: [Double] = []
            var keystroke: [Double] = []
            var hide: [Double] = []
            let narrowed = Array(markers.prefix(max(1, count / 3)))
            for _ in 0..<5 {
                first.append(Self.milliseconds {
                    panel.present(OverlayPresentation(markers: markers, policy: .hintLabels))
                })
                keystroke.append(Self.milliseconds {
                    panel.present(OverlayPresentation(markers: narrowed, policy: .hintLabels, typedPrefix: "f"))
                })
                hide.append(Self.milliseconds {
                    panel.hideOverlay()
                })
            }
            print(
                "BENCH overlay labels=\(count) show_ms=\(Self.text(Self.median(first))) "
                    + "keystroke_ms=\(Self.text(Self.median(keystroke))) hide_ms=\(Self.text(Self.median(hide)))"
            )
        }
    }

    /// Times text recognition on the same drawn chat window at the size
    /// v0.1.4 captured (every backing pixel) and at the capped size. The
    /// picture is drawn here, so no Screen Recording permission is needed.
    func testVisionRecognitionTimings() throws {
        guard ProcessInfo.processInfo.environment["SUPERVIM_LIVE_AX_BENCH"] == "1" else {
            throw XCTSkip("set SUPERVIM_LIVE_AX_BENCH=1 to time text recognition")
        }
        let points = CGSize(width: 1_400, height: 900)
        let capped = VisionCaptureSizing.scale(width: 1_400, height: 900, backingScale: 2)
        let sizes: [(String, Double)] = [("v0.1.4-every-pixel", 2), ("capped", capped), ("one-per-point", 1)]
        var images: [CGImage] = []
        for size in sizes {
            guard let image = Self.chatImage(points: points, scale: size.1) else {
                throw XCTSkip("could not draw the test image")
            }
            images.append(image)
        }
        // The first request loads the recognition model. It is not counted.
        _ = SystemVisionHints.recognize(images[1])
        var samples = [[Double]](repeating: [], count: sizes.count)
        var lines = [Int](repeating: 0, count: sizes.count)
        for _ in 0..<3 {
            for index in sizes.indices {
                samples[index].append(Self.milliseconds {
                    lines[index] = SystemVisionHints.recognize(images[index]).filter { $0.kind == .text }.count
                })
            }
        }
        for index in sizes.indices {
            print(
                "BENCH vision recognize=\(sizes[index].0) image=\(images[index].width)x\(images[index].height) "
                    + "text_lines=\(lines[index]) drawn_lines=\(Self.chatLineCount) \(Self.summary(samples[index]))"
            )
        }

        // Not used by the app. The app only needs where the text is, not
        // what it says; this is what finding the regions alone costs.
        for index in sizes.indices {
            var regions = 0
            var detect: [Double] = []
            for round in 0..<4 {
                let took = Self.milliseconds {
                    let request = VNDetectTextRectanglesRequest()
                    let handler = VNImageRequestHandler(cgImage: images[index], options: [:])
                    try? handler.perform([request])
                    regions = request.results?.count ?? 0
                }
                if round > 0 {
                    detect.append(took)
                }
            }
            print(
                "BENCH vision regions-only=\(sizes[index].0) image=\(images[index].width)x\(images[index].height) "
                    + "regions=\(regions) drawn_lines=\(Self.chatLineCount) \(Self.summary(detect))"
            )
        }
    }

    private static let chatNames = [
        "文件传输助手", "产品讨论组", "李继刚", "Design Weekly", "家人群", "王小明",
        "订阅号消息", "项目进度同步", "张三", "Supervim 测试", "周末爬山", "读书会",
    ]
    private static let chatMessages = [
        "早上好，今天的会议改到下午三点", "收到，我把文档发到群里", "The build is green on main now",
        "好的，辛苦了", "晚上一起吃饭吗", "可以，六点半楼下见", "标签出现得比以前快多了",
        "Please review the pull request when you can", "明天见", "没问题",
    ]
    private static var chatLineCount: Int {
        chatNames.count * 2 + chatMessages.count
    }

    /// A chat window in the shape of WeChat: a list of conversations on the
    /// left, messages on the right. `scale` is pixels per point.
    private static func chatImage(points: CGSize, scale: Double) -> CGImage? {
        let width = Int((points.width * scale).rounded())
        let height = Int((points.height * scale).rounded())
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: points).fill()
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 300, height: points.height).fill()
        let name: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.black,
        ]
        let preview: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.darkGray,
        ]
        for (index, title) in chatNames.enumerated() {
            let y = points.height - 70 - CGFloat(index) * 66
            (title as NSString).draw(at: NSPoint(x: 70, y: y + 22), withAttributes: name)
            ("好的，明天上午十点见 \(index + 1)" as NSString).draw(at: NSPoint(x: 70, y: y), withAttributes: preview)
        }
        for (index, message) in chatMessages.enumerated() {
            let y = points.height - 90 - CGFloat(index) * 72
            let x: CGFloat = index % 2 == 0 ? 360 : 820
            (message as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: name)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Times one real window three ways: the v0.1.4 reader, which asks for
    /// each attribute separately; one batched call per node; and the walk
    /// the app now uses, batched, on several threads, skipping what is hidden.
    func testLiveAccessibilityScanTimings() throws {
        guard ProcessInfo.processInfo.environment["SUPERVIM_LIVE_AX_BENCH"] == "1" else {
            throw XCTSkip("set SUPERVIM_LIVE_AX_BENCH=1 to time a real accessibility tree")
        }
        guard AXIsProcessTrusted() else {
            print("BENCH ax trusted=0")
            throw XCTSkip("this process is not trusted for Accessibility")
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        if let settings = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: settings, configuration: NSWorkspace.OpenConfiguration())
        }
        var best: (name: String, pid: pid_t, window: AXUIElement, nodes: Int)?
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(1))
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
                let element = AXUIElementCreateApplication(app.processIdentifier)
                _ = AXUIElementSetMessagingTimeout(element, 1)
                var value: CFTypeRef?
                guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
                      let windows = value as? [AXUIElement]
                else {
                    continue
                }
                for window in windows.prefix(4) {
                    let walked = AXSystemReader.copyTree(
                        window,
                        options: TreeWalkOptions(budgetMilliseconds: 3_000, workers: 4, prunesHidden: false)
                    )
                    if walked.read > (best?.nodes ?? 0) {
                        best = (app.bundleIdentifier ?? "-", app.processIdentifier, window, walked.read)
                    }
                }
            }
            if let best, best.nodes >= 150 {
                break
            }
        }
        print("BENCH ax trusted=1 target=\(best?.name ?? "-") nodes=\(best?.nodes ?? 0)")
        guard let best, best.nodes > 0 else {
            throw XCTSkip("no app on this machine exposed a window through Accessibility")
        }

        // The four readers take turns, seven rounds each, after one round
        // that is not counted. A window that is still filling in, or a busy
        // minute on the machine, then costs each reader the same.
        let variants: [(String, TreeWalkOptions)] = [
            ("batched-1-thread", TreeWalkOptions(workers: 1, prunesHidden: false)),
            ("batched-4-threads", TreeWalkOptions(workers: 4, prunesHidden: false)),
            ("batched-4-threads-pruned", TreeWalkOptions(workers: AXSystemReader.walkWorkers, prunesHidden: true)),
        ]
        var legacyNodes = 0
        var legacySamples: [Double] = []
        var samples = [[Double]](repeating: [], count: variants.count)
        var walks = [WalkedTree<LiveNode>?](repeating: nil, count: variants.count)
        for round in 0..<8 {
            let legacy = Self.milliseconds {
                legacyNodes = LegacyWalk.count(best.window, limits: .standard)
            }
            if round > 0 {
                legacySamples.append(legacy)
            }
            for (index, variant) in variants.enumerated() {
                let taken = Self.milliseconds {
                    walks[index] = AXSystemReader.copyTree(best.window, options: variant.1)
                }
                if round > 0 {
                    samples[index].append(taken)
                }
            }
        }
        print("BENCH ax walk=v0.1.4-per-attribute nodes=\(legacyNodes) \(Self.summary(legacySamples))")
        for (index, variant) in variants.enumerated() {
            let walked = walks[index]
            print(
                "BENCH ax walk=\(variant.0) nodes=\(walked?.read ?? 0) pruned=\(walked?.pruned ?? 0) "
                    + "levels=\(walked?.levels ?? 0) \(Self.summary(samples[index]))"
            )
            if let root = walked?.root {
                var hits = 0
                let detect = Self.rounds {
                    hits = FocusClassification.countedClickables(in: root, limits: .standard).snapshot.elements.count
                }
                print("BENCH ax detect walk=\(variant.0) hits=\(hits) \(detect)")
            }
        }

        // Bring the measured app to the front so the scan the app itself
        // runs for `f` has a window to find.
        let target = NSRunningApplication(processIdentifier: best.pid)
        if let bundle = target?.bundleURL {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
        }
        target?.activate(options: [.activateAllWindows])
        let settle = Date().addingTimeInterval(5)
        while Date() < settle, NSWorkspace.shared.frontmostApplication?.processIdentifier != best.pid {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"

        let reader = AXSystemReader()
        let pipeline = FocusPipeline(
            decider: EventInterpreter(clock: SystemKeyClock()),
            reader: reader,
            signals: BenchSignals()
        )
        var scan: WindowScan?
        let whole = Self.rounds {
            scan = pipeline.scanner.scanWindow(budgetMilliseconds: nil)
        }
        print(
            "BENCH ax scan-frontmost app=\(front) window=\(scan?.source ?? "-") "
                + "nodes=\(scan?.visited ?? 0) hits=\(scan?.hits ?? 0) \(whole)"
        )
        let focus = Self.rounds {
            _ = pipeline.scanner.noteFocusChanged()
        }
        print("BENCH ax focus-read \(focus)")
    }

    private static func rounds(_ body: () -> Void) -> String {
        var samples: [Double] = []
        for _ in 0..<5 {
            samples.append(milliseconds(body))
        }
        return summary(samples)
    }

    private static func summary(_ samples: [Double]) -> String {
        "min_ms=\(text(samples.min() ?? 0)) median_ms=\(text(median(samples))) max_ms=\(text(samples.max() ?? 0))"
    }

    private static func median(_ samples: [Double]) -> Double {
        let sorted = samples.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }

    private static func markers(_ count: Int) -> [HintMarker] {
        let labels = HintLabeler(elementCount: count).labels
        return labels.enumerated().map { index, label in
            let column = index % 20
            let row = index / 20
            return HintMarker(
                index: index,
                text: label.displayText,
                anchor: HintPoint(x: 40 + Double(column) * 56, y: 60 + Double(row) * 38),
                elementWidth: 48,
                elementHeight: 24
            )
        }
    }

    private static func milliseconds(_ body: () -> Void) -> Double {
        let started = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    private static func text(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

/// The v0.1.4 reader: every attribute of every node is its own round trip.
private enum LegacyWalk {
    static func count(_ element: AXUIElement, limits: TreeWalkLimits) -> Int {
        var remaining = limits.maxNodes
        visit(element, depth: 0, limits: limits, remaining: &remaining)
        return limits.maxNodes - remaining
    }

    private static func visit(_ element: AXUIElement, depth: Int, limits: TreeWalkLimits, remaining: inout Int) {
        remaining -= 1
        _ = copy(element, kAXRoleAttribute)
        _ = copy(element, kAXSubroleAttribute)
        var names: CFArray?
        _ = AXUIElementCopyActionNames(element, &names)
        _ = copy(element, "AXEditable")
        _ = copy(element, kAXPositionAttribute)
        _ = copy(element, kAXSizeAttribute)
        for bar in [kAXVerticalScrollBarAttribute, kAXHorizontalScrollBarAttribute] {
            if let found = copy(element, bar), CFGetTypeID(found) == AXUIElementGetTypeID() {
                let scroll = unsafeBitCast(found, to: AXUIElement.self)
                _ = copy(scroll, kAXValueAttribute)
                _ = copy(scroll, kAXMinValueAttribute)
                _ = copy(scroll, kAXMaxValueAttribute)
            }
        }
        guard remaining > 0, depth < limits.maxDepth,
              let children = copy(element, kAXChildrenAttribute) as? [AXUIElement]
        else {
            return
        }
        for child in children {
            if remaining <= 0 {
                return
            }
            visit(child, depth: depth + 1, limits: limits, remaining: &remaining)
        }
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}

private final class BenchSignals: FocusChangeSignaling, @unchecked Sendable {
    func start(_ handler: @escaping @Sendable () -> Void) {
        _ = handler
    }

    func stop() {}
}
#endif
