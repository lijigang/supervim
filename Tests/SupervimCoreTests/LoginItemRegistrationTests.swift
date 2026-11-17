import XCTest
@testable import SupervimCore

final class LoginItemRegistrationTests: XCTestCase {
    func testTurningThePreferenceOnRegistersTheMainApp() {
        let service = ScriptedLoginItems(state: .notRegistered)
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(registration.apply(launchAtLogin: true), .registered)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(service.state, .enabled)
    }

    func testAMissingBundleStillAttemptsRegistration() {
        let service = ScriptedLoginItems(state: .notFound)
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(registration.apply(launchAtLogin: true), .registered)
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testAnEnabledItemIsNotRegisteredAgain() {
        let service = ScriptedLoginItems(state: .enabled)
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(registration.apply(launchAtLogin: true), .unchanged)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
    }

    func testPendingApprovalIsLeftWaitingForTheUser() {
        let service = ScriptedLoginItems(state: .requiresApproval)
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(registration.apply(launchAtLogin: true), .unchanged)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.unregisterCalls, 0)
        XCTAssertEqual(service.state, .requiresApproval)
    }

    func testTurningThePreferenceOffUnregistersAnEnabledItem() {
        let service = ScriptedLoginItems(state: .enabled)
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(registration.apply(launchAtLogin: false), .unregistered)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertEqual(service.state, .notRegistered)
    }

    func testTurningThePreferenceOffWithdrawsPendingApproval() {
        let service = ScriptedLoginItems(state: .requiresApproval)
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(registration.apply(launchAtLogin: false), .unregistered)
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(service.state, .notRegistered)
    }

    func testTurningThePreferenceOffLeavesAnAbsentItemAlone() {
        for state in [LoginItemState.notRegistered, .notFound] {
            let service = ScriptedLoginItems(state: state)
            let registration = LoginItemRegistration(controller: service)
            XCTAssertEqual(registration.apply(launchAtLogin: false), .unchanged, "\(state)")
            XCTAssertEqual(service.unregisterCalls, 0, "\(state)")
            XCTAssertEqual(service.registerCalls, 0, "\(state)")
        }
    }

    func testAFailedRegistrationDoesNotPretendTheItemChanged() {
        let service = ScriptedLoginItems(state: .notRegistered)
        service.registerError = ScriptedLoginFailure()
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(
            registration.apply(launchAtLogin: true),
            .failed(LoginItemRegistration.failureNotice)
        )
        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertEqual(service.state, .notRegistered)
        XCTAssertTrue(LoginItemRegistration.failureNotice.contains("Applications"))
    }

    func testAFailedUnregistrationDoesNotPretendTheItemChanged() {
        let service = ScriptedLoginItems(state: .enabled)
        service.unregisterError = ScriptedLoginFailure()
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(
            registration.apply(launchAtLogin: false),
            .failed(LoginItemRegistration.failureNotice)
        )
        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertEqual(service.state, .enabled)
    }

    func testASecondApplyReadsTheServiceInsteadOfRemembering() {
        let service = ScriptedLoginItems(state: .notRegistered)
        let registration = LoginItemRegistration(controller: service)
        XCTAssertEqual(registration.apply(launchAtLogin: true), .registered)
        XCTAssertEqual(registration.apply(launchAtLogin: true), .unchanged)
        XCTAssertEqual(service.registerCalls, 1)
    }

    func testFailureNoticeCanBeShownInTheSettingsEditor() throws {
        let fixture = try menuForLoginPreference(enabled: false)
        let editor = fixture.session.reportNotice(LoginItemRegistration.failureNotice)
        XCTAssertEqual(editor.notice, LoginItemRegistration.failureNotice)
        XCTAssertFalse(editor.launchAtLogin)
    }

    func testLoginItemLogicDoesNotImportServiceManagement() throws {
        let text = try repoSource("Sources/SupervimCore/LoginItemRegistration.swift")
        for token in ["SMAppService", "ServiceManagement", "import AppKit", "URLSession", "print("] {
            XCTAssertFalse(text.contains(token), token)
        }
        XCTAssertTrue(text.contains("func apply(launchAtLogin:"))
    }

    func testSystemAdapterCallsMainAppRegisterAndUnregister() throws {
        let text = try repoSource("Sources/SupervimSystem/MainAppLoginItemController.swift")
        XCTAssertTrue(text.contains("#if canImport(ServiceManagement)"))
        XCTAssertTrue(text.contains("SMAppService.mainApp"))
        XCTAssertTrue(text.contains(".register()"))
        XCTAssertTrue(text.contains(".unregister()"))
        XCTAssertTrue(text.contains("struct MainAppLoginItemController"))
        XCTAssertFalse(text.contains("URLSession"))
        XCTAssertFalse(text.contains("print("))
    }

    func testAppAppliesTheSavedPreferenceWithoutNamingTheSystemService() throws {
        let text = try repoSource("Sources/Supervim/ExclusionSettingsPanel.swift")
        XCTAssertFalse(text.contains("SMAppService"))
        XCTAssertFalse(text.contains("ServiceManagement"))
        XCTAssertTrue(text.contains("LoginItemRegistration"))
        XCTAssertTrue(text.contains("MainAppLoginItemController"))
        XCTAssertTrue(text.contains("apply(launchAtLogin:"))
        let calls = text.components(separatedBy: "synchronizeLoginItem()").count - 1
        XCTAssertGreaterThanOrEqual(calls, 2)
        XCTAssertTrue(text.contains("func applicationDidFinishLaunching"))
        XCTAssertTrue(text.contains("func exclusionPanelDidSetLaunchAtLogin"))
    }
}

private final class ScriptedLoginItems: LoginItemControlling, @unchecked Sendable {
    var state: LoginItemState
    var registerCalls = 0
    var unregisterCalls = 0
    var registerError: Error?
    var unregisterError: Error?

    init(state: LoginItemState) {
        self.state = state
    }

    func currentState() -> LoginItemState {
        state
    }

    func register() throws {
        registerCalls += 1
        if let registerError {
            throw registerError
        }
        state = .enabled
    }

    func unregister() throws {
        unregisterCalls += 1
        if let unregisterError {
            throw unregisterError
        }
        state = .notRegistered
    }
}

private struct ScriptedLoginFailure: Error {}

private struct NamedFrontApp: FrontmostBundleProviding {
    var bundleIdentifier: String

    func frontmostBundleIdentifier() -> String {
        bundleIdentifier
    }
}

private struct LoginMenuFixture {
    var session: MenuBarController<ManualKeyClock>
}

private func menuForLoginPreference(enabled: Bool) throws -> LoginMenuFixture {
    let repository = SettingsRepository(store: InMemorySettingsStore())
    var settings = Settings.defaults
    settings.launchAtLogin = enabled
    try repository.save(settings)
    let session = try MenuBarController(
        repository: repository,
        clock: ManualKeyClock(),
        frontmost: NamedFrontApp(bundleIdentifier: "com.apple.Safari")
    )
    return LoginMenuFixture(session: session)
}

private func repoSource(_ relative: String) throws -> String {
    let url = repoRoot().appendingPathComponent(relative)
    return try String(contentsOf: url, encoding: .utf8)
}
