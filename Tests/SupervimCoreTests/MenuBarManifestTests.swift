import XCTest
@testable import SupervimCore

final class MenuBarManifestTests: XCTestCase {
    func testRejectsManifestThatWouldShowTheDockIcon() {
        var manifest = validManifest()
        manifest.hidesDockIcon = false
        expectValidation(manifest, .dockIconNotSuppressed)
    }

    func testRejectsDeploymentTargetBelowMacOS13() {
        var manifest = validManifest()
        manifest.minimumSystemVersion = SystemVersion(major: 12, minor: 9, patch: 9)
        expectValidation(
            manifest,
            .deploymentTargetTooOld(
                found: SystemVersion(major: 12, minor: 9, patch: 9),
                required: SystemVersion(major: 13, minor: 0, patch: 0)
            )
        )
    }

    func testAcceptsMacOS13AndNewer() throws {
        try MenuBarManifestValidator.validate(validManifest())
        var newer = validManifest()
        newer.minimumSystemVersion = SystemVersion(major: 14, minor: 0, patch: 0)
        try MenuBarManifestValidator.validate(newer)
    }

    func testRejectsBlankBundleIdentifier() {
        var manifest = validManifest()
        manifest.bundleIdentifier = " \n\t "
        expectValidation(manifest, .missingBundleIdentifier)
    }

    func testRejectsBlankBundleName() {
        var manifest = validManifest()
        manifest.bundleName = " "
        expectValidation(manifest, .missingBundleName)
    }

    func testRejectsBlankExecutableName() {
        var manifest = validManifest()
        manifest.bundleExecutable = ""
        expectValidation(manifest, .missingExecutableName)
    }

    func testRejectsMissingOrNonApplicationPackageType() {
        var missing = validManifest()
        missing.packageType = nil
        expectValidation(missing, .notAnApplicationBundle(found: nil))

        var tool = validManifest()
        tool.packageType = "BNDL"
        expectValidation(tool, .notAnApplicationBundle(found: "BNDL"))
    }

    func testParsesDottedSystemVersions() throws {
        XCTAssertEqual(try SystemVersion.parse("13.0"), SystemVersion(major: 13, minor: 0, patch: 0))
        XCTAssertEqual(try SystemVersion.parse("13"), SystemVersion(major: 13, minor: 0, patch: 0))
        XCTAssertEqual(try SystemVersion.parse("14.2.1"), SystemVersion(major: 14, minor: 2, patch: 1))
    }

    func testRejectsUnusableSystemVersionStrings() {
        for raw in ["", "13.", "13.0b", "13.00", "v13.0"] {
            XCTAssertThrowsError(try SystemVersion.parse(raw)) { error in
                XCTAssertEqual(error as? SystemVersionParseError, .invalid(raw))
            }
        }
    }

    func testDecoderReadsAMenuBarPropertyList() throws {
        let manifest = try MenuBarPlistDecoder.decode(Data(menuBarPlist().utf8))
        XCTAssertEqual(manifest.bundleIdentifier, "com.lijigang.supervim")
        XCTAssertEqual(manifest.bundleName, "Supervim")
        XCTAssertEqual(manifest.bundleExecutable, "Supervim")
        XCTAssertEqual(manifest.packageType, "APPL")
        XCTAssertEqual(manifest.minimumSystemVersion, SystemVersion(major: 13, minor: 0, patch: 0))
        XCTAssertTrue(manifest.hidesDockIcon)
    }

    func testDecoderReadsExplicitDockIcon() throws {
        let manifest = try MenuBarPlistDecoder.decode(Data(menuBarPlist(lsuiElement: "<false/>").utf8))
        XCTAssertFalse(manifest.hidesDockIcon)
    }

    func testDecoderTreatsMissingLSUIElementAsDockVisible() throws {
        let manifest = try MenuBarPlistDecoder.decode(Data(menuBarPlist(lsuiElement: nil).utf8))
        XCTAssertFalse(manifest.hidesDockIcon)
    }

    func testDecoderRejectsNonBooleanLSUIElement() {
        let xml = menuBarPlist(lsuiElement: "<integer>1</integer>")
        XCTAssertThrowsError(try MenuBarPlistDecoder.decode(Data(xml.utf8))) { error in
            XCTAssertEqual(error as? PlistDecodeError, .invalidBoolean("LSUIElement"))
        }
    }

    func testDecoderRejectsMissingOrJunkDeploymentTarget() {
        for version in [nil as String?, "", "13.0b"] {
            let xml = menuBarPlist(minimumSystem: version)
            XCTAssertThrowsError(try MenuBarPlistDecoder.decode(Data(xml.utf8))) { error in
                XCTAssertEqual(error as? PlistDecodeError, .invalidVersion(version ?? ""))
            }
        }
    }

    func testDecoderRejectsMalformedPropertyList() {
        XCTAssertThrowsError(try MenuBarPlistDecoder.decode(Data("not a plist".utf8))) { error in
            XCTAssertEqual(error as? PlistDecodeError, .unreadablePropertyList)
        }
    }

    func testDecoderRejectsPropertyListThatIsNotADictionary() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <array><string>Supervim</string></array>
        </plist>
        """
        XCTAssertThrowsError(try MenuBarPlistDecoder.decode(Data(xml.utf8))) { error in
            XCTAssertEqual(error as? PlistDecodeError, .notADictionary)
        }
    }

    func testCheckedInInfoPlistPassesMenuBarContract() throws {
        let url = repoRoot().appendingPathComponent("App/Supervim/Info.plist")
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("missing App/Supervim/Info.plist")
            return
        }
        let data = try Data(contentsOf: url)
        let manifest = try MenuBarPlistDecoder.decode(data)
        try MenuBarManifestValidator.validate(manifest)
        XCTAssertEqual(manifest.bundleIdentifier, "com.lijigang.supervim")
        XCTAssertEqual(manifest.bundleName, "Supervim")
        XCTAssertEqual(manifest.bundleExecutable, "Supervim")
        XCTAssertEqual(manifest.packageType, "APPL")
        XCTAssertEqual(manifest.minimumSystemVersion, SystemVersion(major: 13, minor: 0, patch: 0))
        XCTAssertTrue(manifest.hidesDockIcon)

        let raw = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(raw?["NSPrincipalClass"] as? String, "NSApplication")
        XCTAssertEqual(raw?["CFBundleDisplayName"] as? String, "Supervim")
        XCTAssertEqual(raw?["LSMinimumSystemVersion"] as? String, "13.0")
    }

    func testSupervimCoreSourcesDoNotImportSystemUIOrEventFrameworks() throws {
        let directory = repoRoot().appendingPathComponent("Sources/SupervimCore")
        let files = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertFalse(files.isEmpty, "SupervimCore has no Swift sources")

        var violations: [String] = []
        for relative in files {
            let text = try String(contentsOf: directory.appendingPathComponent(relative), encoding: .utf8)
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            for (index, rawLine) in lines.enumerated() {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("//") { continue }
                if let module = importedModule(from: line), forbiddenSystemModules.contains(module) {
                    violations.append("\(relative):\(index + 1) imports \(module)")
                }
                for module in forbiddenSystemModules where line.contains("canImport(\(module))") {
                    violations.append("\(relative):\(index + 1) canImport(\(module))")
                }
            }
        }
        XCTAssertEqual(violations, [])
    }
}

private let forbiddenSystemModules: Set<String> = [
    "AppKit",
    "Cocoa",
    "SwiftUI",
    "UIKit",
    "ApplicationServices",
    "Carbon",
    "IOKit",
    "CoreGraphics",
    "Quartz",
    "Accessibility",
]

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

private func expectValidation(
    _ manifest: MenuBarManifest,
    _ expected: ManifestValidationError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    XCTAssertThrowsError(try MenuBarManifestValidator.validate(manifest), file: file, line: line) { error in
        XCTAssertEqual(error as? ManifestValidationError, expected, file: file, line: line)
    }
}

private func menuBarPlist(
    minimumSystem: String? = "13.0",
    lsuiElement: String? = "<true/>"
) -> String {
    var body = """
    <key>CFBundleIdentifier</key>
    <string>com.lijigang.supervim</string>
    <key>CFBundleName</key>
    <string>Supervim</string>
    <key>CFBundleExecutable</key>
    <string>Supervim</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    """
    if let minimumSystem {
        body += """

        <key>LSMinimumSystemVersion</key>
        <string>\(minimumSystem)</string>
        """
    }
    if let lsuiElement {
        body += """

        <key>LSUIElement</key>
        \(lsuiElement)
        """
    }
    return """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \(body)
    </dict>
    </plist>
    """
}

private func importedModule(from line: String) -> String? {
    let pattern = #"^(?:@\S+\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|func|var|let)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(line.startIndex..., in: line)
    guard let match = regex.firstMatch(in: line, range: range),
          let moduleRange = Range(match.range(at: 1), in: line) else {
        return nil
    }
    return String(line[moduleRange])
}
