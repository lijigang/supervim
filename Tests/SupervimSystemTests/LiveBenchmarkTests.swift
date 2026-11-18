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
        for count in [50, 150, 300] {
            let markers = Self.markers(count)
            let first = Self.milliseconds {
                panel.present(OverlayPresentation(markers: markers, policy: .hintLabels))
            }
            let narrowed = Array(markers.prefix(max(1, count / 3)))
            let keystroke = Self.milliseconds {
                panel.present(OverlayPresentation(markers: narrowed, policy: .hintLabels, typedPrefix: "f"))
            }
            let again = Self.milliseconds {
                panel.present(OverlayPresentation(markers: markers, policy: .hintLabels))
            }
            let hide = Self.milliseconds {
                panel.hideOverlay()
            }
            print(
                "BENCH overlay labels=\(count) first_ms=\(Self.text(first)) keystroke_ms=\(Self.text(keystroke)) "
                    + "reshow_ms=\(Self.text(again)) hide_ms=\(Self.text(hide))"
            )
        }
    }

    func testLiveAccessibilityScanTimings() throws {
        guard ProcessInfo.processInfo.environment["SUPERVIM_LIVE_AX_BENCH"] == "1" else {
            throw XCTSkip("set SUPERVIM_LIVE_AX_BENCH=1 to time a real accessibility tree")
        }
        guard AXIsProcessTrusted() else {
            print("BENCH ax trusted=0")
            throw XCTSkip("this process is not trusted for Accessibility")
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications", isDirectory: true))
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != "com.apple.finder" {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
                .first?.activate(options: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-"
        print("BENCH ax trusted=1 frontmost=\(front)")

        let reader = AXSystemReader()
        let limits = TreeWalkLimits.standard
        var nodes = 0
        for round in 0..<3 {
            var choices: [AccessibilityWindowChoice] = []
            let elapsed = Self.milliseconds {
                choices = reader.readWindowChoices(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth)
            }
            nodes = choices.reduce(0) { total, choice in
                total + (choice.element.map { AccessibilityTreeSummary.counts(in: $0, limits: limits).nodes } ?? 0)
            }
            print(
                "BENCH ax window-choices round=\(round) windows=\(choices.filter(\.found).count) "
                    + "nodes=\(nodes) ms=\(Self.text(elapsed))"
            )
        }
        if nodes == 0 {
            throw XCTSkip("the frontmost app exposed no accessibility nodes")
        }

        let pipeline = FocusPipeline(
            decider: EventInterpreter(clock: SystemKeyClock()),
            reader: reader,
            signals: BenchSignals()
        )
        for round in 0..<3 {
            var hits = 0
            let scan = Self.milliseconds {
                if case .elements(let snapshot) = pipeline.scanner.clickableElements() {
                    hits = snapshot.elements.count
                }
            }
            print("BENCH ax hint-scan round=\(round) hits=\(hits) ms=\(Self.text(scan))")
        }
        for round in 0..<3 {
            let refresh = Self.milliseconds {
                _ = pipeline.scanner.clickableElements()
                _ = reader.readFrontmostWindow(maxNodes: limits.maxNodes, maxDepth: limits.maxDepth)
                _ = reader.readFocusedElement()
                _ = pipeline.scanner.firstEditableInput()
            }
            print("BENCH ax focus-refresh-sequence round=\(round) ms=\(Self.text(refresh))")
        }
        for round in 0..<3 {
            let focus = Self.milliseconds {
                _ = pipeline.scanner.noteFocusChanged()
            }
            print("BENCH ax focus-read round=\(round) ms=\(Self.text(focus))")
        }
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

private final class BenchSignals: FocusChangeSignaling, @unchecked Sendable {
    func start(_ handler: @escaping @Sendable () -> Void) {
        _ = handler
    }

    func stop() {}
}
#endif
