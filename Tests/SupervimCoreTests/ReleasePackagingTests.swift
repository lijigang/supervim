import XCTest
@testable import SupervimCore

final class ReleasePackagingTests: XCTestCase {
    func testCheckedInInfoPlistCarriesTheReleaseIdentity() throws {
        let url = repoRoot().appendingPathComponent("App/Supervim/Info.plist")
        let data = try Data(contentsOf: url)
        let manifest = try MenuBarPlistDecoder.decode(data)
        XCTAssertEqual(manifest.bundleIdentifier, "com.lijigang.supervim")
        XCTAssertEqual(manifest.bundleExecutable, "Supervim")
        XCTAssertEqual(manifest.packageType, "APPL")
        XCTAssertEqual(manifest.minimumSystemVersion, SystemVersion(major: 13, minor: 0, patch: 0))
        XCTAssertTrue(manifest.hidesDockIcon)

        let raw = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(raw["CFBundleShortVersionString"] as? String, "0.1.0")
        XCTAssertEqual(raw["CFBundleVersion"] as? String, "1")
        XCTAssertEqual(raw["LSMinimumSystemVersion"] as? String, "13.0")
    }

    func testAssembleScriptStampsTheReleaseVersion() throws {
        let text = try packagingText("scripts/assemble-app.sh")
        XCTAssertTrue(text.contains("CFBundleShortVersionString"))
        XCTAssertTrue(text.contains("CFBundleVersion"))
        XCTAssertTrue(text.contains("PlistBuddy"))
        XCTAssertTrue(text.contains("LSUIElement"))
        XCTAssertTrue(text.contains("com.lijigang.supervim") || text.contains("Info.plist"))
    }

    func testPackageScriptUsesCreateDMGAndAdHocCodesign() throws {
        let text = try packagingText("scripts/package-dmg.sh")
        XCTAssertTrue(text.contains("create-dmg"))
        XCTAssertTrue(text.contains("--app-drop-link"))
        XCTAssertTrue(text.contains("codesign"))
        XCTAssertTrue(text.contains("-s -"))
        XCTAssertTrue(text.contains("Supervim.app"))
        XCTAssertFalse(text.contains("Developer ID"))
    }

    func testVerifyScriptMountsAndChecksTheApplicationsLink() throws {
        let text = try packagingText("scripts/verify-dmg.sh")
        XCTAssertTrue(text.contains("hdiutil attach"))
        XCTAssertTrue(text.contains("hdiutil detach"))
        XCTAssertTrue(text.contains("Supervim.app"))
        XCTAssertTrue(text.contains("Applications"))
        XCTAssertTrue(text.contains("-L"))
        XCTAssertTrue(text.contains("/Applications"))
    }

    func testReleaseWorkflowPublishesTheDMGWithTheToken() throws {
        let text = try packagingText(".github/workflows/release.yml")
        XCTAssertTrue(text.contains("workflow_dispatch"))
        XCTAssertTrue(text.contains("version:"))
        XCTAssertTrue(text.contains("v*"))
        XCTAssertTrue(text.contains("macos-latest"))
        XCTAssertTrue(text.contains("contents: write"))
        XCTAssertTrue(text.contains("GITHUB_TOKEN"))
        XCTAssertTrue(text.contains("assemble-app.sh release"))
        XCTAssertTrue(text.contains("package-dmg.sh"))
        XCTAssertTrue(text.contains("gh release"))
        XCTAssertTrue(text.contains("permissions:"))
    }

    func testPullRequestCIPackagesMountsAndUploadsTheDMG() throws {
        let text = try packagingText(".github/workflows/ci.yml")
        XCTAssertTrue(text.contains("package-dmg.sh"))
        XCTAssertTrue(text.contains("verify-dmg.sh"))
        XCTAssertTrue(text.contains("upload-artifact"))
        XCTAssertTrue(text.contains("Supervim.dmg"))
        XCTAssertTrue(text.contains("create-dmg"))
    }
}

private func packagingText(_ relative: String) throws -> String {
    let url = repoRoot().appendingPathComponent(relative)
    return try String(contentsOf: url, encoding: .utf8)
}
