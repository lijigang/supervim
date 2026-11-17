import XCTest
@testable import SupervimCore
@testable import SupervimSystem

final class MenuBarPreflightTests: XCTestCase {
    func testValidManifestOnMacHostIsReady() throws {
        let result = try MenuBarLauncher.preflight(validManifest(), host: .macOS)
        XCTAssertEqual(result, .readyForMenuBarLaunch)
    }

    func testValidManifestOnNonMacHostIsUnsupported() throws {
        let result = try MenuBarLauncher.preflight(validManifest(), host: .other)
        XCTAssertEqual(result, .unsupportedPlatform)
    }

    func testInvalidManifestIsNotReadyOnMacOS() {
        var manifest = validManifest()
        manifest.hidesDockIcon = false
        XCTAssertThrowsError(try MenuBarLauncher.preflight(manifest, host: .macOS)) { error in
            XCTAssertEqual(
                error as? MenuBarPreflightError,
                .invalidManifest(.dockIconNotSuppressed)
            )
        }
    }

    func testInvalidManifestIsNotReportedAsUnsupportedPlatform() {
        var manifest = validManifest()
        manifest.hidesDockIcon = false
        XCTAssertThrowsError(try MenuBarLauncher.preflight(manifest, host: .other)) { error in
            XCTAssertEqual(
                error as? MenuBarPreflightError,
                .invalidManifest(.dockIconNotSuppressed)
            )
        }
    }

    func testCurrentHostMatchesCompiledPlatform() {
        #if os(macOS)
        XCTAssertEqual(MenuBarLauncher.currentHost(), .macOS)
        #else
        XCTAssertEqual(MenuBarLauncher.currentHost(), .other)
        #endif
    }
}

private func validManifest() -> MenuBarManifest {
    MenuBarManifest(
        bundleIdentifier: "com.lijigang.supervim",
        bundleName: "Supervim",
        bundleExecutable: "Supervim",
        packageType: "APPL",
        minimumSystemVersion: SystemVersion(major: 13, minor: 0, patch: 0),
        hidesDockIcon: true
    )
}
