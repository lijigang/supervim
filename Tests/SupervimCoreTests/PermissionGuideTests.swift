import XCTest
@testable import SupervimCore

/// Permission guidance from an injected status. No real Accessibility or Input Monitoring check.
final class PermissionGuideTests: XCTestCase {
    func testBothMissingShowsGuidanceAndBothSettingsLinks() {
        let guide = makeGuide(status: .missingBoth)
        let guidance = guide.refresh()
        assertVisible(
            guidance,
            lead: "Supervim needs Accessibility and Input Monitoring. Open the System Settings pane for each one and turn Supervim on.",
            links: [accessibilityLink, inputMonitoringLink]
        )
        XCTAssertEqual(guidance.notice, "")
    }

    func testMissingAccessibilityShowsOnlyThatPane() {
        let guide = makeGuide(
            status: PermissionStatus(accessibility: .missing, inputMonitoring: .granted)
        )
        let guidance = guide.refresh()
        assertVisible(
            guidance,
            lead: "Supervim needs Accessibility. Open the System Settings pane and turn Supervim on.",
            links: [accessibilityLink]
        )
        XCTAssertFalse(guidance.body.contains(inputMonitoringLink.destination))
    }

    func testMissingInputMonitoringShowsOnlyThatPane() {
        let guide = makeGuide(
            status: PermissionStatus(accessibility: .granted, inputMonitoring: .missing)
        )
        let guidance = guide.refresh()
        assertVisible(
            guidance,
            lead: "Supervim needs Input Monitoring. Open the System Settings pane and turn Supervim on.",
            links: [inputMonitoringLink]
        )
        XCTAssertFalse(guidance.body.contains(accessibilityLink.destination))
    }

    func testScreenRecordingAloneDoesNotOpenTheGuide() {
        let guide = makeGuide(status: PermissionStatus(
            accessibility: .granted,
            inputMonitoring: .granted,
            screenRecording: .missing
        ))
        assertHidden(guide.refresh())
    }

    func testAMissingRequiredPermissionAlsoOffersScreenRecording() {
        let guide = makeGuide(status: PermissionStatus(
            accessibility: .missing,
            inputMonitoring: .granted,
            screenRecording: .missing
        ))
        let guidance = guide.refresh()
        XCTAssertTrue(guidance.isVisible)
        XCTAssertEqual(guidance.links.map(\.kind), [.accessibility, .screenRecording])
        XCTAssertTrue(guidance.body.contains("Screen Recording is optional"))
        XCTAssertTrue(guidance.body.contains("Turn on Screen Recording"))
        XCTAssertEqual(
            guidance.links[1].destination,
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        )
    }

    func testBothGrantedHidesGuidance() {
        let guide = makeGuide(status: .complete)
        assertHidden(guide.refresh())
    }

    func testRefreshHidesGuidanceAfterALaterGrant() {
        let status = ScriptedPermissionStatus(.missingBoth)
        let guide = makeGuide(status: status)
        XCTAssertTrue(guide.refresh().isVisible)
        status.status = .complete
        assertHidden(guide.refresh())
        XCTAssertEqual(status.reads, 2)
    }

    func testRefreshShowsGuidanceAgainIfAGrantDisappears() {
        let status = ScriptedPermissionStatus(.complete)
        let guide = makeGuide(status: status)
        assertHidden(guide.refresh())
        status.status = PermissionStatus(accessibility: .granted, inputMonitoring: .missing)
        let guidance = guide.refresh()
        XCTAssertTrue(guidance.isVisible)
        XCTAssertEqual(guidance.links, [inputMonitoringLink])
        XCTAssertEqual(status.reads, 2)
    }

    func testOpeningAMissingPaneUsesThatSettingsLink() {
        let status = ScriptedPermissionStatus(.missingBoth)
        let opener = ScriptedPaneOpener()
        let guide = makeGuide(status: status, opener: opener)
        let guidance = guide.openLink(.inputMonitoring)
        XCTAssertEqual(opener.destinations, [inputMonitoringLink.destination])
        XCTAssertEqual(guidance.notice, "")
        XCTAssertTrue(guidance.isVisible)
        XCTAssertEqual(status.reads, 2)
    }

    func testOpeningTheAccessibilityPaneUsesTheAccessibilityLink() {
        let opener = ScriptedPaneOpener()
        let guide = makeGuide(status: .missingBoth, opener: opener)
        _ = guide.openLink(.accessibility)
        XCTAssertEqual(opener.destinations, [accessibilityLink.destination])
    }

    func testOpenDoesNotClaimTheGrantAndHidesWhenTheNextReadIsComplete() {
        let status = ScriptedPermissionStatus(.missingBoth)
        let opener = ScriptedPaneOpener()
        opener.onOpen = { status.status = .complete }
        let guide = makeGuide(status: status, opener: opener)
        let guidance = guide.openLink(.accessibility)
        XCTAssertEqual(opener.destinations, [accessibilityLink.destination])
        assertHidden(guidance)
        XCTAssertEqual(guidance.notice, "")
        XCTAssertFalse(guidance.body.contains("takes effect immediately"))
    }

    func testOpenLeavesTheOtherMissingPermissionVisible() {
        let status = ScriptedPermissionStatus(.missingBoth)
        let opener = ScriptedPaneOpener()
        opener.onOpen = {
            status.status = PermissionStatus(accessibility: .granted, inputMonitoring: .missing)
        }
        let guide = makeGuide(status: status, opener: opener)
        let guidance = guide.openLink(.accessibility)
        XCTAssertTrue(guidance.isVisible)
        XCTAssertEqual(guidance.links, [inputMonitoringLink])
        XCTAssertEqual(guidance.notice, "")
    }

    func testOpenForAnAlreadyGrantedPermissionDoesNotOpenSettings() {
        let status = ScriptedPermissionStatus(
            PermissionStatus(accessibility: .granted, inputMonitoring: .missing)
        )
        let opener = ScriptedPaneOpener()
        let guide = makeGuide(status: status, opener: opener)
        let guidance = guide.openLink(.accessibility)
        XCTAssertEqual(opener.destinations, [])
        XCTAssertEqual(guidance.links, [inputMonitoringLink])
        XCTAssertEqual(status.reads, 1)
    }

    func testFailedOpenKeepsGuidanceAndDoesNotPretendItWasGranted() {
        let opener = ScriptedPaneOpener()
        opener.shouldOpen = false
        let guide = makeGuide(status: .missingBoth, opener: opener)
        let guidance = guide.openLink(.accessibility)
        XCTAssertEqual(opener.destinations, [accessibilityLink.destination])
        XCTAssertTrue(guidance.isVisible)
        XCTAssertEqual(guidance.links.map(\.kind), [.accessibility, .inputMonitoring])
        XCTAssertEqual(guidance.notice, "Could not open System Settings.")
        XCTAssertTrue(guidance.body.contains("does not guarantee"))
    }

    func testRefreshClearsAnOpenFailureNotice() {
        let opener = ScriptedPaneOpener()
        opener.shouldOpen = false
        let guide = makeGuide(status: .missingBoth, opener: opener)
        XCTAssertEqual(guide.openLink(.accessibility).notice, "Could not open System Settings.")
        XCTAssertEqual(guide.refresh().notice, "")
    }

    func testGuidesUseTheInjectedStatus() {
        let first = makeGuide(status: .missingBoth)
        let second = makeGuide(status: .complete)
        XCTAssertTrue(first.refresh().isVisible)
        assertHidden(second.refresh())
    }

    func testListenEventGrantRequiresTheHidGrantAndThePreflight() {
        XCTAssertEqual(
            ListenEventAccess.resolve(
                hidGranted: true,
                hidDenied: false,
                hidUnknown: false,
                preflightGranted: true
            ),
            .granted
        )
        XCTAssertEqual(
            ListenEventAccess.resolve(
                hidGranted: true,
                hidDenied: false,
                hidUnknown: false,
                preflightGranted: false
            ),
            .unknown
        )
        XCTAssertEqual(
            ListenEventAccess.resolve(
                hidGranted: true,
                hidDenied: true,
                hidUnknown: false,
                preflightGranted: true
            ),
            .unknown
        )
        XCTAssertEqual(
            ListenEventAccess.resolve(
                hidGranted: false,
                hidDenied: true,
                hidUnknown: false,
                preflightGranted: true
            ),
            .denied
        )
        XCTAssertEqual(
            ListenEventAccess.resolve(
                hidGranted: false,
                hidDenied: true,
                hidUnknown: false,
                preflightGranted: false
            ),
            .denied
        )
        XCTAssertEqual(
            ListenEventAccess.resolve(
                hidGranted: false,
                hidDenied: false,
                hidUnknown: true,
                preflightGranted: true
            ),
            .unknown
        )
        XCTAssertEqual(
            ListenEventAccess.resolve(
                hidGranted: false,
                hidDenied: false,
                hidUnknown: false,
                preflightGranted: true
            ),
            .unknown
        )
    }

    func testUnknownOrDeniedListenEventIsNotAGrant() {
        let rows: [(Bool, ListenEventAccess, PermissionGrant, PermissionGrant)] = [
            (false, .unknown, .missing, .missing),
            (false, .denied, .missing, .missing),
            (false, .granted, .missing, .granted),
            (true, .unknown, .granted, .missing),
            (true, .denied, .granted, .missing),
            (true, .granted, .granted, .granted),
        ]
        for row in rows {
            let status = PermissionStatus(accessibilityTrusted: row.0, listenEvent: row.1)
            XCTAssertEqual(status.accessibility, row.2, "\(row)")
            XCTAssertEqual(status.inputMonitoring, row.3, "\(row)")
        }
    }

    func testMissingPermissionDoesNotAskToStartTheRuntime() {
        let gate = PermissionLaunchGate(guide: makeGuide(status: .missingBoth))
        let step = gate.refresh()
        XCTAssertTrue(step.guidance.isVisible)
        XCTAssertFalse(step.shouldStartRuntime)
    }

    func testALaterGrantAsksToStartTheRuntimeOnce() {
        let status = ScriptedPermissionStatus(.missingBoth)
        let gate = PermissionLaunchGate(guide: makeGuide(status: status))
        XCTAssertFalse(gate.refresh().shouldStartRuntime)
        status.status = .complete
        let granted = gate.refresh()
        XCTAssertFalse(granted.guidance.isVisible)
        XCTAssertTrue(granted.shouldStartRuntime)
        gate.noteRuntimeStarted()
        XCTAssertFalse(gate.refresh().shouldStartRuntime)
    }

    func testGrantedAtLaunchAsksToStartWithoutShowingTheGuide() {
        let gate = PermissionLaunchGate(guide: makeGuide(status: .complete))
        let step = gate.refresh()
        XCTAssertFalse(step.guidance.isVisible)
        XCTAssertTrue(step.shouldStartRuntime)
    }

    func testOpeningTheLastMissingPaneAsksToStartAfterTheGrant() {
        let status = ScriptedPermissionStatus(
            PermissionStatus(accessibility: .granted, inputMonitoring: .missing)
        )
        let opener = ScriptedPaneOpener()
        opener.onOpen = { status.status = .complete }
        let gate = PermissionLaunchGate(guide: makeGuide(status: status, opener: opener))
        let step = gate.openLink(.inputMonitoring)
        XCTAssertFalse(step.guidance.isVisible)
        XCTAssertTrue(step.shouldStartRuntime)
        XCTAssertEqual(opener.destinations, [inputMonitoringLink.destination])
    }

    func testAGrantThatTheRuntimeRefusesCanBeAskedAgain() {
        let gate = PermissionLaunchGate(guide: makeGuide(status: .complete))
        XCTAssertTrue(gate.refresh().shouldStartRuntime)
        XCTAssertTrue(gate.refresh().shouldStartRuntime)
        gate.noteRuntimeStarted()
        XCTAssertFalse(gate.openLink(.accessibility).shouldStartRuntime)
    }

    func testVisibleCopyDoesNotPromiseARestartFreeGrant() {
        let guidance = makeGuide(status: .missingBoth).refresh()
        XCTAssertTrue(guidance.body.contains("does not guarantee"))
        XCTAssertTrue(guidance.body.contains("without quitting and reopening"))
        XCTAssertTrue(guidance.body.contains("not verified"))
        XCTAssertTrue(guidance.body.contains("minus button"))
        XCTAssertTrue(guidance.body.contains("ad-hoc"))
        XCTAssertTrue(guidance.body.contains("stable identity"))
        XCTAssertFalse(guidance.body.contains("no restart is required"))
        XCTAssertFalse(guidance.body.contains("takes effect immediately"))
        XCTAssertFalse(guidance.body.contains("AXManualAccessibility"))
    }

    func testAppPresentsGuidanceWithoutPromptingOrInstallingATap() throws {
        let directory = repoRoot().appendingPathComponent("Sources/Supervim")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertFalse(files.contains("main.swift"))
        var combined = ""
        for relative in files {
            combined += try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
        }
        XCTAssertTrue(combined.contains("PermissionGuide"))
        XCTAssertTrue(combined.contains("PermissionLaunchGate"))
        XCTAssertTrue(combined.contains("shouldStartRuntime"))
        XCTAssertTrue(combined.contains("noteRuntimeStarted"))
        XCTAssertTrue(combined.contains("MenuHookAssembly"))
        XCTAssertTrue(combined.contains("runtime.start()"))
        XCTAssertTrue(combined.contains("SystemPermissionStatus"))
        XCTAssertTrue(combined.contains("WorkspacePrivacyPaneOpener"))
        XCTAssertTrue(combined.contains("openLink"))
        XCTAssertTrue(combined.contains("isVisible"))
        XCTAssertTrue(combined.contains("checkAgainTitle"))
        XCTAssertTrue(combined.contains("menuTitle"))
        let entry = try String(
            contentsOf: directory.appendingPathComponent("SupervimApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(entry.hasPrefix("#if os(macOS)\n"))
        XCTAssertTrue(entry.contains("@main"))
        XCTAssertFalse(entry.contains("canImport(AppKit)"))
        for token in [
            "AXIsProcessTrustedWithOptions",
            "AXManualAccessibility",
            "kAXManualAccessibility",
            "CGRequestListenEventAccess",
            "IOHIDRequestAccess",
            "URLSession",
            "CGEvent",
            "EventTap",
        ] {
            XCTAssertFalse(combined.contains(token), token)
        }
    }

    func testCoreDoesNotImportSystemFrameworks() throws {
        let directory = repoRoot().appendingPathComponent("Sources/SupervimCore")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
        var combined = ""
        for relative in files {
            combined += try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
        }
        for token in ["import AppKit", "import ApplicationServices", "import IOKit", "import CoreGraphics"] {
            XCTAssertFalse(combined.contains(token), token)
        }
        let guide = try String(
            contentsOf: directory.appendingPathComponent("PermissionGuide.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(guide.contains("protocol PermissionStatusProviding"))
        XCTAssertTrue(guide.contains("protocol PrivacyPaneOpening"))
    }
}

private let accessibilityLink = PrivacyPaneLink(
    kind: .accessibility,
    title: "Open Accessibility Settings",
    destination: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
)

private let inputMonitoringLink = PrivacyPaneLink(
    kind: .inputMonitoring,
    title: "Open Input Monitoring Settings",
    destination: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
)

private func makeGuide(
    status: PermissionStatus,
    opener: ScriptedPaneOpener = ScriptedPaneOpener()
) -> PermissionGuide {
    makeGuide(status: ScriptedPermissionStatus(status), opener: opener)
}

private func makeGuide(
    status: ScriptedPermissionStatus,
    opener: ScriptedPaneOpener = ScriptedPaneOpener()
) -> PermissionGuide {
    PermissionGuide(status: status, opener: opener)
}

private func expectedBody(_ lead: String) -> String {
    """
    \(lead)

    If Supervim is already in that list but this copy still has no permission, the old row belongs to a previous build. Select it, click the minus button to remove it, then add this Supervim and turn it on. That is required once when moving from an ad-hoc build to a build signed with the stable identity. Later upgrades keep the same signing certificate, so the grant stays.

    Granting a permission does not guarantee that this process receives it without quitting and reopening Supervim. Whether that happens depends on the system version and whether the permission database refreshes. It is not verified.

    Screen Recording is optional. Supervim asks for it the first time an app has no accessibility elements to label. The capture stays on this Mac and is not uploaded.
    """
}

private func assertVisible(
    _ guidance: PermissionGuidance,
    lead: String,
    links: [PrivacyPaneLink],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertTrue(guidance.isVisible, file: file, line: line)
    XCTAssertEqual(guidance.title, "Supervim Needs Permissions", file: file, line: line)
    XCTAssertEqual(guidance.body, expectedBody(lead), file: file, line: line)
    XCTAssertEqual(guidance.links, links, file: file, line: line)
    XCTAssertEqual(guidance.checkAgainTitle, "Check Again", file: file, line: line)
    XCTAssertEqual(guidance.menuTitle, "Permissions", file: file, line: line)
}

private func assertHidden(
    _ guidance: PermissionGuidance,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertFalse(guidance.isVisible, file: file, line: line)
    XCTAssertEqual(guidance.title, "", file: file, line: line)
    XCTAssertEqual(guidance.body, "", file: file, line: line)
    XCTAssertEqual(guidance.links, [], file: file, line: line)
    XCTAssertEqual(guidance.notice, "", file: file, line: line)
    XCTAssertEqual(guidance.checkAgainTitle, "Check Again", file: file, line: line)
    XCTAssertEqual(guidance.menuTitle, "Permissions", file: file, line: line)
}

private extension PermissionStatus {
    static let missingBoth = PermissionStatus(accessibility: .missing, inputMonitoring: .missing)
    static let complete = PermissionStatus(accessibility: .granted, inputMonitoring: .granted)
}

private final class ScriptedPermissionStatus: PermissionStatusProviding, @unchecked Sendable {
    var status: PermissionStatus
    var reads = 0

    init(_ status: PermissionStatus) {
        self.status = status
    }

    func currentPermissionStatus() -> PermissionStatus {
        reads += 1
        return status
    }
}

private final class ScriptedPaneOpener: PrivacyPaneOpening, @unchecked Sendable {
    var destinations: [String] = []
    var shouldOpen = true
    var onOpen: () -> Void = {}

    func openPrivacyPane(destination: String) -> Bool {
        destinations.append(destination)
        onOpen()
        return shouldOpen
    }
}
