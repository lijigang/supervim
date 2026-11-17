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

    func testPackageScriptUsesCreateDMGAndTheStableSigner() throws {
        let text = try packagingText("scripts/package-dmg.sh")
        XCTAssertTrue(text.contains("create-dmg"))
        XCTAssertTrue(text.contains("--app-drop-link"))
        XCTAssertTrue(text.contains("sign-app.sh"))
        XCTAssertTrue(text.contains("Supervim.app"))
        XCTAssertFalse(text.contains("-s -"))
        XCTAssertFalse(text.contains("Developer ID"))
    }

    func testSignScriptUsesOneCertificateAndFallsBackLoudly() throws {
        let text = try packagingText("scripts/sign-app.sh")
        XCTAssertTrue(text.contains("com.lijigang.supervim"))
        XCTAssertTrue(text.contains("SUPERVIM_SIGNING_P12_BASE64"))
        XCTAssertTrue(text.contains("SUPERVIM_SIGNING_P12_PASSWORD"))
        XCTAssertTrue(text.contains("certificate leaf"))
        XCTAssertTrue(text.contains("cdhash"))
        XCTAssertTrue(text.contains("-s -"))
        XCTAssertTrue(text.contains("WARNING"))
        XCTAssertFalse(text.contains("Developer ID"))
        XCTAssertFalse(text.contains("--options runtime"))
    }

    func testMakeSigningCertScriptBuildsALongLivedCodeSigningP12() throws {
        let text = try packagingText("scripts/make-signing-cert.sh")
        XCTAssertTrue(text.contains("codeSigning"))
        XCTAssertTrue(text.contains("7300"))
        XCTAssertTrue(text.contains("pkcs12"))
        XCTAssertTrue(text.contains("SUPERVIM_SIGNING_P12_PASSWORD"))
        XCTAssertTrue(text.contains("refusing to write"))
        XCTAssertFalse(text.contains("BEGIN PRIVATE KEY"))
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
        XCTAssertTrue(text.contains("SUPERVIM_SIGNING_P12_BASE64"))
        XCTAssertTrue(text.contains("SUPERVIM_SIGNING_P12_PASSWORD"))
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

    func testCheckedInInfoPlistNamesTheAppIcon() throws {
        let url = repoRoot().appendingPathComponent("App/Supervim/Info.plist")
        let data = try Data(contentsOf: url)
        let raw = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(raw["CFBundleIconFile"] as? String, "AppIcon")
        XCTAssertEqual(raw["CFBundleShortVersionString"] as? String, "0.1.0")
        XCTAssertEqual(raw["CFBundleVersion"] as? String, "1")
    }

    func testAssembleScriptInstallsTheAppIcon() throws {
        let text = try packagingText("scripts/assemble-app.sh")
        XCTAssertTrue(text.contains("Contents/Resources"))
        XCTAssertTrue(text.contains("AppIcon.icns"))
        XCTAssertTrue(text.contains("CFBundleShortVersionString"))
    }

    func testPackageScriptSetsTheVolumeIcon() throws {
        let text = try packagingText("scripts/package-dmg.sh")
        XCTAssertTrue(text.contains("--volicon"))
        XCTAssertTrue(text.contains("AppIcon.icns"))
        XCTAssertTrue(text.contains("--app-drop-link"))
        XCTAssertTrue(text.contains("sign-app.sh"))
        XCTAssertFalse(text.contains("Developer ID"))
    }

    func testVerifyScriptChecksTheBundledAppIcon() throws {
        let text = try packagingText("scripts/verify-dmg.sh")
        XCTAssertTrue(text.contains("AppIcon.icns"))
        XCTAssertTrue(text.contains("CFBundleIconFile"))
        XCTAssertTrue(text.contains("AppIcon"))
        XCTAssertTrue(text.contains(".VolumeIcon.icns"))
        XCTAssertTrue(text.contains("codesign -d -r-"))
    }

    func testAppSourcesDoNotResetTCCOrChangeTheBundleIdentifier() throws {
        let root = repoRoot().appendingPathComponent("Sources")
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
        XCTAssertFalse(files.isEmpty)
        for relative in files {
            let text = try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            XCTAssertFalse(text.contains("tccutil"), relative)
            XCTAssertFalse(text.contains("TCC.db"), relative)
            XCTAssertFalse(text.contains("resetSystemPrivacy"), relative)
        }
        let plist = try String(
            contentsOf: repoRoot().appendingPathComponent("App/Supervim/Info.plist"),
            encoding: .utf8
        )
        XCTAssertTrue(plist.contains("com.lijigang.supervim"))
    }

    func testMakeIconScriptBuildsAnIconset() throws {
        let text = try packagingText("scripts/make-icon.sh")
        XCTAssertTrue(text.contains("iconutil"))
        XCTAssertTrue(text.contains("AppIcon.iconset"))
        XCTAssertTrue(text.contains("AppIcon.icns"))
        XCTAssertTrue(text.contains("AppIcon.svg"))
    }

    func testPullRequestCIChecksTheAssembledAppIcon() throws {
        let text = try packagingText(".github/workflows/ci.yml")
        XCTAssertTrue(text.contains("CFBundleIconFile"))
        XCTAssertTrue(text.contains("Contents/Resources/AppIcon.icns"))
        XCTAssertTrue(text.contains("make-icon.sh"))
    }

    func testAppIconSourceDrawsOnlyTheCursorBlock() throws {
        let text = try packagingText("Resources/AppIcon.svg")
        XCTAssertTrue(text.contains("1024"))
        XCTAssertTrue(text.contains("#34C759"))
        XCTAssertTrue(text.contains("#F7F7F8"))
        XCTAssertTrue(text.contains("#E9E9EC"))
        XCTAssertFalse(text.contains("<text"))
    }

    func testCommittedIconFilesAreTheStandardSizes() throws {
        let root = repoRoot()
        let pngURL = root.appendingPathComponent("Resources/AppIcon-1024.png")
        let icnsURL = root.appendingPathComponent("Resources/AppIcon.icns")
        guard FileManager.default.fileExists(atPath: pngURL.path) else {
            XCTFail("missing Resources/AppIcon-1024.png")
            return
        }
        guard FileManager.default.fileExists(atPath: icnsURL.path) else {
            XCTFail("missing Resources/AppIcon.icns")
            return
        }

        let png = try Data(contentsOf: pngURL)
        let header = try pngHeader(png)
        XCTAssertEqual(header.width, 1024)
        XCTAssertEqual(header.height, 1024)
        XCTAssertEqual(header.bitDepth, 8)
        XCTAssertEqual(header.colorType, 6)

        let icns = try Data(contentsOf: icnsURL)
        let chunks = try icnsChunks(icns)
        let expected: [(String, Int, Int)] = [
            ("icp4", 16, 16),
            ("icp5", 32, 32),
            ("ic07", 128, 128),
            ("ic08", 256, 256),
            ("ic09", 512, 512),
            ("ic10", 1024, 1024),
            ("ic11", 32, 32),
            ("ic12", 64, 64),
            ("ic13", 256, 256),
            ("ic14", 512, 512),
        ]
        for (type, width, height) in expected {
            let chunk = try XCTUnwrap(chunks.first { $0.type == type }, "missing \(type)")
            let image = try pngHeader(chunk.data)
            XCTAssertEqual(image.width, width, type)
            XCTAssertEqual(image.height, height, type)
            XCTAssertEqual(image.colorType, 6, type)
        }
    }
}

private struct PNGHeader {
    var width: Int
    var height: Int
    var bitDepth: Int
    var colorType: Int
}

private struct ICNSChunk {
    var type: String
    var data: Data
}

private func pngHeader(_ data: Data) throws -> PNGHeader {
    let signature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    guard data.count >= 24, data.prefix(8) == signature else {
        throw PNGReadError.notPNG
    }
    let chunk = data.subdata(in: 12..<16)
    guard String(data: chunk, encoding: .ascii) == "IHDR" else {
        throw PNGReadError.missingIHDR
    }
    func u32(_ offset: Int) -> Int {
        let bytes = data.subdata(in: offset..<(offset + 4))
        return bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
    return PNGHeader(
        width: u32(16),
        height: u32(20),
        bitDepth: Int(data[24]),
        colorType: Int(data[25])
    )
}

private func icnsChunks(_ data: Data) throws -> [ICNSChunk] {
    guard data.count >= 8, String(data: data.prefix(4), encoding: .ascii) == "icns" else {
        throw PNGReadError.notICNS
    }
    func u32(_ offset: Int) -> Int {
        data.subdata(in: offset..<(offset + 4)).reduce(0) { ($0 << 8) | Int($1) }
    }
    let declared = u32(4)
    guard declared == data.count else {
        throw PNGReadError.badICNSLength
    }
    var offset = 8
    var chunks: [ICNSChunk] = []
    while offset + 8 <= data.count {
        let type = String(data: data.subdata(in: offset..<(offset + 4)), encoding: .ascii) ?? ""
        let length = u32(offset + 4)
        guard length >= 8, offset + length <= data.count else {
            throw PNGReadError.badICNSChunk
        }
        let body = data.subdata(in: (offset + 8)..<(offset + length))
        if type != "TOC " {
            chunks.append(ICNSChunk(type: type, data: body))
        }
        offset += length
    }
    guard offset == data.count else {
        throw PNGReadError.badICNSChunk
    }
    return chunks
}

private enum PNGReadError: Error {
    case notPNG
    case missingIHDR
    case notICNS
    case badICNSLength
    case badICNSChunk
}

private func packagingText(_ relative: String) throws -> String {
    let url = repoRoot().appendingPathComponent(relative)
    return try String(contentsOf: url, encoding: .utf8)
}
