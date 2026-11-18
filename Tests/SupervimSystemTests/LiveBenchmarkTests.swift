#if os(macOS)
import AppKit
import ApplicationServices
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
