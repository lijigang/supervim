import XCTest

/// The macOS adapter is source-checked here. This test does not grant TCC permissions.
final class PermissionAccessTests: XCTestCase {
    func testMacOSAdapterChecksTrustAndOpensSettingsWithoutPrompting() throws {
        let url = repoRoot().appendingPathComponent("Sources/SupervimSystem/PermissionAccess.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("AXIsProcessTrusted()"))
        XCTAssertTrue(text.contains("IOHIDCheckAccess"))
        XCTAssertTrue(text.contains("kIOHIDRequestTypeListenEvent"))
        XCTAssertTrue(text.contains("kIOHIDAccessTypeGranted"))
        XCTAssertTrue(text.contains("kIOHIDAccessTypeDenied"))
        XCTAssertTrue(text.contains("kIOHIDAccessTypeUnknown"))
        XCTAssertTrue(text.contains("CGPreflightListenEventAccess"))
        XCTAssertTrue(text.contains("ListenEventAccess.resolve"))
        XCTAssertTrue(text.contains("NSWorkspace"))
        XCTAssertTrue(text.contains("canImport(IOKit)"))
        XCTAssertTrue(text.contains("canImport(AppKit)"))
        XCTAssertTrue(text.contains("PermissionStatus("))
        XCTAssertTrue(text.contains("listenEvent:"))
        for token in [
            "AXIsProcessTrustedWithOptions",
            "AXManualAccessibility",
            "kAXManualAccessibility",
            "CGRequestListenEventAccess",
            "IOHIDRequestAccess",
            "URLSession",
        ] {
            XCTAssertFalse(text.contains(token), token)
        }
    }
}

private func repoRoot(file: String = #filePath) -> URL {
    URL(fileURLWithPath: file)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}
