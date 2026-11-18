import Foundation
import XCTest
@testable import SupervimCore
@testable import SupervimSystem

final class ContextRefreshTests: XCTestCase {
    // MARK: One walk per scan

    func testOneScanReadsTheWindowOnceAndFeedsHintsInputAndCatalog() {
        let reader = LazyReader(windows: [("focused", window(button: true, field: true))])
        let rig = ScannerRig(reader: reader)
        let scan = rig.scanner.scanWindow()
        XCTAssertEqual(reader.walks, 1, "hints, gi and the scroll catalog must share one walk")
        XCTAssertEqual(reader.eagerReads, 0)
        XCTAssertEqual(scan.hits, 2)
        XCTAssertEqual(scan.source, "focused")
        guard case .found(let input) = scan.firstInput else {
            return XCTFail("expected the text field, got \(scan.firstInput)")
        }
        XCTAssertEqual(input.path, [1])
        guard case .value(let root) = scan.window else {
            return XCTFail("expected the window tree")
        }
        XCTAssertEqual(root.children.count, 3)
        XCTAssertEqual(reader.adopted, [1])
    }

    func testHintScanHasADeadlineAndABackgroundScanHasNone() {
        let reader = LazyReader(windows: [("focused", window(button: true, field: false))])
        let rig = ScannerRig(reader: reader)
        _ = rig.scanner.clickableElements()
        _ = rig.scanner.scanWindow()
        XCTAssertEqual(reader.budgets, [AXScanner.hintScanBudgetMilliseconds, nil])
        // Long enough for a full page in a slow app, short enough that a
        // tree that never ends still gives labels.
        XCTAssertEqual(AXScanner.hintScanBudgetMilliseconds, 1_000)
    }

    func testWindowsAfterTheFirstUsableOneAreNotWalked() {
        let reader = LazyReader(windows: [
            ("focused", window(button: true, field: false)),
            ("main", window(button: true, field: true)),
            ("windows", window(button: true, field: true)),
        ])
        let rig = ScannerRig(reader: reader)
        _ = rig.scanner.clickableElements()
        XCTAssertEqual(reader.walks, 1)
    }

    func testAWindowWithNothingClickableFallsThroughToTheNextAndAdoptsThatWalk() {
        let reader = LazyReader(windows: [
            ("focused", window(button: false, field: false)),
            ("main", window(button: true, field: false)),
        ])
        let rig = ScannerRig(reader: reader)
        let scan = rig.scanner.scanWindow()
        XCTAssertEqual(reader.walks, 2)
        XCTAssertEqual(scan.source, "main")
        XCTAssertEqual(reader.adopted, [2])
        XCTAssertEqual(scan.firstInput, .none)
    }

    func testScanHandlerSeesEveryScan() {
        let reader = LazyReader(windows: [("focused", window(button: true, field: false))])
        let rig = ScannerRig(reader: reader)
        let seen = Recorder()
        rig.scanner.onWindowScan { scan in
            seen.add("\(scan.source):\(scan.hits)")
        }
        _ = rig.scanner.clickableElements()
        _ = rig.scanner.scanWindow(budgetMilliseconds: 50)
        XCTAssertEqual(seen.values, ["focused:1", "focused:1"])
        XCTAssertEqual(reader.budgets, [AXScanner.hintScanBudgetMilliseconds, 50])
    }

    func testScanTimingIsLogged() {
        let reader = LazyReader(windows: [("focused", window(button: true, field: false))])
        let rig = ScannerRig(reader: reader)
        let lines = ModeTrace.capture {
            _ = rig.scanner.scanWindow()
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("timing stage=ax-scan ms=") && $0.contains("hits=1") }, "\(lines)")
    }

    // MARK: Refresher

    func testFocusSignalReadsFocusOffTheCallerAndWalksOnceAfterTheBurst() {
        let rig = RefreshRig()
        for _ in 0..<5 {
            rig.refresher.focusMayHaveChanged()
        }
        XCTAssertEqual(rig.scanner.focusReads, 0, "nothing may run on the thread that delivered the signal")
        XCTAssertEqual(rig.scanner.scans, 0)
        rig.work.runPending()
        XCTAssertEqual(rig.scanner.focusReads, 1, "queued reads are not queued again")
        XCTAssertEqual(rig.scanner.scans, 0)
        rig.work.advance(milliseconds: 199)
        XCTAssertEqual(rig.scanner.scans, 0)
        rig.work.advance(milliseconds: 1)
        XCTAssertEqual(rig.scanner.scans, 1, "five signals cost one walk")
        XCTAssertEqual(rig.published.count, 1)
    }

    func testASignalDuringTheSettleTimeRestartsIt() {
        let rig = RefreshRig()
        rig.refresher.focusMayHaveChanged()
        rig.work.advance(milliseconds: 150)
        rig.refresher.focusMayHaveChanged()
        rig.work.advance(milliseconds: 150)
        XCTAssertEqual(rig.scanner.scans, 0)
        rig.work.advance(milliseconds: 50)
        XCTAssertEqual(rig.scanner.scans, 1)
    }

    func testAFailedFocusReadIsRetriedUntilItSucceeds() {
        let rig = RefreshRig()
        rig.scanner.focusResults = [.failed, .failed, .known]
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        XCTAssertEqual(rig.scanner.focusReads, 1)
        XCTAssertEqual(rig.cache.currentFocus().editability, .unknown)
        rig.work.advance(milliseconds: 80)
        XCTAssertEqual(rig.scanner.focusReads, 2)
        rig.work.advance(milliseconds: 250)
        XCTAssertEqual(rig.scanner.focusReads, 3)
        XCTAssertEqual(rig.cache.currentFocus().editability, .notEditable)
        rig.work.advance(milliseconds: 5_000)
        XCTAssertEqual(rig.scanner.focusReads, 3, "a good read ends the retries")
    }

    func testRetriesStopAfterTheLastDelay() {
        let rig = RefreshRig()
        rig.scanner.focusResults = Array(repeating: .failed, count: 10)
        rig.refresher.focusMayHaveChanged()
        for step in [0, 80, 250, 700, 5_000, 5_000] {
            rig.work.advance(milliseconds: step)
        }
        XCTAssertEqual(rig.scanner.focusReads, 4)
    }

    func testAnUnknownRoleIsNotAFailedReadAndIsNotRetried() {
        let rig = RefreshRig()
        rig.scanner.focusResults = [.unknownRole]
        rig.refresher.focusMayHaveChanged()
        rig.work.advance(milliseconds: 150)
        XCTAssertEqual(rig.scanner.focusReads, 1)
    }

    func testAClickReadsFocusAgainForAppsThatSendNoNotification() {
        let rig = RefreshRig()
        rig.refresher.pointerClicked()
        rig.work.runPending()
        XCTAssertEqual(rig.scanner.focusReads, 0)
        rig.work.advance(milliseconds: 60)
        XCTAssertEqual(rig.scanner.focusReads, 1)
        rig.work.advance(milliseconds: 240)
        XCTAssertEqual(rig.scanner.focusReads, 2)
        XCTAssertEqual(rig.scanner.scans, 1)
    }

    func testKeysWhileFocusIsUnknownReadFocusAtMostOncePerInterval() {
        let rig = RefreshRig()
        rig.scanner.focusResults = [.unknownRole, .unknownRole, .unknownRole]
        rig.refresher.keyWhileFocusUnknown()
        rig.refresher.keyWhileFocusUnknown()
        rig.work.runPending()
        XCTAssertEqual(rig.scanner.focusReads, 1)
        rig.now.value = 100
        rig.refresher.keyWhileFocusUnknown()
        rig.work.runPending()
        XCTAssertEqual(rig.scanner.focusReads, 1)
        rig.now.value = 151
        rig.refresher.keyWhileFocusUnknown()
        rig.work.runPending()
        XCTAssertEqual(rig.scanner.focusReads, 2)
        XCTAssertEqual(rig.scanner.scans, 0, "a key does not walk the window")
    }

    func testNoWalkStartsWhileLabelsAreShowing() {
        let rig = RefreshRig()
        rig.mode.value = .hint(.plain)
        rig.refresher.focusMayHaveChanged()
        rig.work.advance(milliseconds: 500)
        XCTAssertEqual(rig.scanner.scans, 0)
        XCTAssertEqual(rig.scanner.focusReads, 1)
    }

    func testAHintScanIsAdoptedAndCancelsThePendingWalk() {
        let rig = RefreshRig()
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        rig.scanner.deliver(RefreshRig.scan(input: .found(EditableInputTarget(
            frame: ElementFrame(x: 1, y: 2, width: 30, height: 10),
            path: [4]
        ))))
        XCTAssertEqual(rig.published.count, 1)
        XCTAssertEqual(rig.published.last?.firstInput, .found(EditableInputTarget(
            frame: ElementFrame(x: 1, y: 2, width: 30, height: 10),
            path: [4]
        )))
        XCTAssertEqual(rig.published.last?.windowFrame, ActuatorRect(x: 0, y: 0, width: 800, height: 600))
        rig.work.advance(milliseconds: 500)
        XCTAssertEqual(rig.scanner.scans, 0, "the hint scan was the walk")
    }

    func testAWindowWithoutAFrameUsesTheWindowListFrame() {
        let rig = RefreshRig()
        rig.scanner.deliver(WindowScan(
            clickables: .unavailable,
            firstInput: .unavailable,
            window: .unavailable,
            source: "missing",
            visited: 0,
            hits: 0
        ))
        XCTAssertEqual(rig.published.last?.windowFrame, ActuatorRect(x: 5, y: 6, width: 700, height: 500))
        XCTAssertEqual(rig.published.last?.scrollCatalogReady, false)
    }

    func testModeChangeIsReportedOncePerChange() {
        let rig = RefreshRig()
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        XCTAssertEqual(rig.modeChanges.values.count, 1)
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        XCTAssertEqual(rig.modeChanges.values.count, 1)
        rig.mode.value = .insert
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        XCTAssertEqual(rig.modeChanges.values.count, 2)
    }

    /// The settings window names the front app. Switching apps without a
    /// mode change still has to reach the menu.
    func testAnotherFrontAppIsReportedEvenWhenTheModeIsTheSame() {
        let rig = RefreshRig()
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        XCTAssertEqual(rig.modeChanges.values.count, 1)
        rig.scanner.bundle = "com.example.Other"
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        XCTAssertEqual(rig.modeChanges.values.count, 2)
        rig.refresher.focusMayHaveChanged()
        rig.work.runPending()
        XCTAssertEqual(rig.modeChanges.values.count, 2)
    }

    func testFocusReadTimingIsLogged() {
        let rig = RefreshRig()
        let lines = ModeTrace.capture {
            rig.refresher.focusMayHaveChanged()
            rig.work.runPending()
        }
        XCTAssertTrue(lines.contains { $0.hasPrefix("timing stage=focus-read ms=") && $0.contains("failed=0") }, "\(lines)")
    }

    // MARK: Menu notifications

    func testMenuIsToldOnlyWhenTheModeChanges() {
        let inner = CountingObserver()
        let observer = ModeChangeObserver(inner: inner)
        let normal = EventDecision(delivery: .swallow, mode: .normal)
        observer.runtimeDidHandle(normal)
        observer.runtimeDidHandle(normal)
        observer.runtimeDidHandle(EventDecision(delivery: .passThrough, mode: .normal))
        XCTAssertEqual(inner.count, 1)
        observer.runtimeDidHandle(EventDecision(delivery: .swallow, mode: .hint(.plain)))
        XCTAssertEqual(inner.count, 2)
        observer.runtimeDidHandle(nil)
        observer.runtimeDidHandle(nil)
        XCTAssertEqual(inner.count, 4, "nil is an explicit refresh")
    }

    func testBannerReportRunsItsHandler() {
        let banner = HintMissBanner()
        let seen = Recorder()
        banner.onReport { seen.add("report") }
        banner.reportMissingClickableElements()
        banner.report(HintMissBanner.inputMissingMessage)
        XCTAssertEqual(seen.values, ["report", "report"])
        XCTAssertEqual(banner.title(fallback: "Normal"), HintMissBanner.inputMissingMessage)
    }

    // MARK: Focus roles

    func testRolesThatNeverTakeTextAreNotEditable() {
        for role in [
            "AXCell", "AXHeading", "AXColumn", "AXGrid", "AXDockItem", "AXRadioGroup",
            "AXValueIndicator", "AXProgressIndicator", "AXBusyIndicator", "AXLevelIndicator", "AXPopover",
            "AXSwitch", "AXToggle",
        ] {
            XCTAssertEqual(
                FocusClassification.editability(of: AccessibilityElement(role: role)),
                .notEditable,
                role
            )
        }
        XCTAssertEqual(
            FocusClassification.editability(of: AccessibilityElement(role: "AXCell", editableAttribute: true)),
            .editable
        )
        XCTAssertEqual(FocusClassification.editability(of: AccessibilityElement(role: "AXUnknown")), .unknown)
        XCTAssertEqual(FocusClassification.editability(of: AccessibilityElement(role: nil)), .unknown)
        XCTAssertEqual(FocusClassification.editability(of: AccessibilityElement(role: "AXMadeUp")), .unknown)
    }

    // MARK: Fixtures

    private func window(button: Bool, field: Bool) -> AccessibilityElement {
        var children: [AccessibilityElement] = []
        if button {
            children.append(AccessibilityElement(
                role: "AXButton",
                actions: ["AXPress"],
                frame: ElementFrame(x: 10, y: 10, width: 60, height: 20)
            ))
        }
        if field {
            children.append(AccessibilityElement(
                role: "AXTextField",
                frame: ElementFrame(x: 10, y: 50, width: 200, height: 22)
            ))
        }
        children.append(AccessibilityElement(
            role: "AXStaticText",
            frame: ElementFrame(x: 10, y: 90, width: 100, height: 16)
        ))
        return AccessibilityElement(
            role: "AXWindow",
            frame: ElementFrame(x: 0, y: 0, width: 800, height: 600),
            children: children
        )
    }
}

private final class ScannerRig {
    let scanner: AXScanner

    init(reader: LazyReader) {
        scanner = AXScanner(reader: reader, signals: QuietSignals(), cache: LockedFocusCache())
    }
}

private final class QuietSignals: FocusChangeSignaling, @unchecked Sendable {
    func start(_ handler: @escaping @Sendable () -> Void) {
        _ = handler
    }

    func stop() {}
}

private final class LazyReader: AccessibilityReading, @unchecked Sendable {
    private let windows: [(String, AccessibilityElement)]
    private(set) var walks = 0
    private(set) var eagerReads = 0
    private(set) var adopted: [Int?] = []
    private(set) var budgets: [Double?] = []

    init(windows: [(String, AccessibilityElement)]) {
        self.windows = windows
    }

    func readFocusedElement() -> AccessibilityRead<AccessibilityElement> {
        .unavailable
    }

    func readFrontmostBundleIdentifier() -> AccessibilityRead<String> {
        .value("com.example.App")
    }

    func readFrontmostWindow(maxNodes: Int, maxDepth: Int) -> AccessibilityRead<AccessibilityElement> {
        eagerReads += 1
        return .unavailable
    }

    func readWindowChoices(maxNodes: Int, maxDepth: Int) -> [AccessibilityWindowChoice] {
        eagerReads += 1
        return []
    }

    func readWindowChoices(
        limits: TreeWalkLimits,
        budgetMilliseconds: Double?,
        accept: (AccessibilityWindowChoice) -> Bool
    ) -> [AccessibilityWindowChoice] {
        budgets.append(budgetMilliseconds)
        var choices: [AccessibilityWindowChoice] = []
        for (source, element) in windows {
            walks += 1
            let choice = AccessibilityWindowChoice(source: source, found: true, element: element, walk: walks)
            choices.append(choice)
            if accept(choice) {
                break
            }
        }
        return choices
    }

    func adoptWalk(_ walk: Int?) {
        adopted.append(walk)
    }
}

private final class Box<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private final class RefreshRig {
    let scanner = ScriptedScanner()
    let cache = LockedFocusCache()
    let work = ManualWork()
    let mode = Box<SupervimMode>(.normal)
    let now = Box<Double>(0)
    let modeChanges = Recorder()
    private let sink = Box<[CommandSnapshot]>([])
    let refresher: ContextRefresher

    var published: [CommandSnapshot] {
        sink.value
    }

    init() {
        scanner.cache = cache
        refresher = ContextRefresher(
            scanner: scanner,
            focus: cache,
            mode: { [mode] in mode.value },
            work: work,
            publish: { [sink] snapshot in sink.value.append(snapshot) },
            modeChanged: { [modeChanges] in modeChanges.add("mode") },
            windows: FixedWindow(),
            clock: { [now] in now.value }
        )
    }

    static func scan(input: EditableInputQuery = .none) -> WindowScan {
        WindowScan(
            clickables: .elements(ClickableSnapshot(elements: [], truncated: false)),
            firstInput: input,
            window: .value(AccessibilityElement(
                role: "AXWindow",
                frame: ElementFrame(x: 0, y: 0, width: 800, height: 600)
            )),
            source: "focused",
            visited: 1,
            hits: 0
        )
    }
}

private final class FixedWindow: FrontWindowReading, @unchecked Sendable {
    func frontWindowFrame() -> ActuatorRect? {
        ActuatorRect(x: 5, y: 6, width: 700, height: 500)
    }
}

private final class ScriptedScanner: ContextScanning, @unchecked Sendable {
    enum FocusResult {
        case failed
        case unknownRole
        case known
    }

    var cache: LockedFocusCache?
    var bundle = "com.example.App"
    var focusResults: [FocusResult] = []
    private(set) var focusReads = 0
    private(set) var scans = 0
    private var handler: (@Sendable (WindowScan) -> Void)?

    func noteFocusChanged() -> EventDecision {
        let result = focusReads < focusResults.count ? focusResults[focusReads] : .known
        focusReads += 1
        switch result {
        case .failed:
            cache?.replace(CachedFocus(editability: .unknown, bundleIdentifier: bundle))
        case .unknownRole:
            cache?.replace(CachedFocus(
                editability: .unknown,
                bundleIdentifier: bundle,
                role: "AXUnknown"
            ))
        case .known:
            cache?.replace(CachedFocus(
                editability: .notEditable,
                bundleIdentifier: bundle,
                role: "AXGroup"
            ))
        }
        return EventDecision(delivery: .passThrough, mode: .normal)
    }

    func scanWindow(budgetMilliseconds: Double?) -> WindowScan {
        _ = budgetMilliseconds
        scans += 1
        let scan = RefreshRig.scan()
        handler?(scan)
        return scan
    }

    func onWindowScan(_ handler: @escaping @Sendable (WindowScan) -> Void) {
        self.handler = handler
    }

    func deliver(_ scan: WindowScan) {
        handler?(scan)
    }
}

private final class CountingObserver: RuntimeObserving, @unchecked Sendable {
    private(set) var count = 0

    func runtimeDidHandle(_ decision: EventDecision?) {
        _ = decision
        count += 1
    }
}
