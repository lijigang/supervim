import Foundation

public struct SystemVersion: Equatable, Sendable, Comparable {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: SystemVersion, rhs: SystemVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    public static func parse(_ raw: String) throws -> SystemVersion {
        let parts = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else {
            throw SystemVersionParseError.invalid(raw)
        }
        var numbers: [Int] = []
        for part in parts {
            guard let value = canonicalComponent(part) else {
                throw SystemVersionParseError.invalid(raw)
            }
            numbers.append(value)
        }
        while numbers.count < 3 {
            numbers.append(0)
        }
        return SystemVersion(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    private static func canonicalComponent(_ part: Substring) -> Int? {
        guard !part.isEmpty else { return nil }
        for character in part {
            guard character >= "0", character <= "9" else { return nil }
        }
        if part.count > 1, part.first == "0" {
            return nil
        }
        return Int(part)
    }
}

public enum SystemVersionParseError: Error, Equatable, Sendable {
    case invalid(String)
}

public struct MenuBarManifest: Equatable, Sendable {
    public var bundleIdentifier: String
    public var bundleName: String
    public var bundleExecutable: String
    public var packageType: String?
    public var minimumSystemVersion: SystemVersion
    public var hidesDockIcon: Bool

    public init(
        bundleIdentifier: String,
        bundleName: String,
        bundleExecutable: String,
        packageType: String?,
        minimumSystemVersion: SystemVersion,
        hidesDockIcon: Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.bundleName = bundleName
        self.bundleExecutable = bundleExecutable
        self.packageType = packageType
        self.minimumSystemVersion = minimumSystemVersion
        self.hidesDockIcon = hidesDockIcon
    }
}

public enum ManifestValidationError: Error, Equatable, Sendable {
    case dockIconNotSuppressed
    case deploymentTargetTooOld(found: SystemVersion, required: SystemVersion)
    case missingBundleIdentifier
    case missingBundleName
    case missingExecutableName
    case notAnApplicationBundle(found: String?)
}

public enum MenuBarManifestValidator {
    public static let minimumSystemVersion = SystemVersion(major: 13, minor: 0, patch: 0)

    public static func validate(_ manifest: MenuBarManifest) throws {
        if !manifest.hidesDockIcon {
            throw ManifestValidationError.dockIconNotSuppressed
        }
        if manifest.minimumSystemVersion < minimumSystemVersion {
            throw ManifestValidationError.deploymentTargetTooOld(
                found: manifest.minimumSystemVersion,
                required: minimumSystemVersion
            )
        }
        if manifest.bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ManifestValidationError.missingBundleIdentifier
        }
        if manifest.bundleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ManifestValidationError.missingBundleName
        }
        if manifest.bundleExecutable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ManifestValidationError.missingExecutableName
        }
        guard manifest.packageType == "APPL" else {
            throw ManifestValidationError.notAnApplicationBundle(found: manifest.packageType)
        }
    }
}

public enum PlistDecodeError: Error, Equatable, Sendable {
    case notADictionary
    case invalidVersion(String)
    case invalidBoolean(String)
    case unreadablePropertyList
}

public enum MenuBarPlistDecoder {
    public static func decode(_ data: Data) throws -> MenuBarManifest {
        let object: Any
        do {
            object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw PlistDecodeError.unreadablePropertyList
        }
        guard let dict = dictionary(from: object) else {
            throw PlistDecodeError.notADictionary
        }

        let versionRaw = string(dict, "LSMinimumSystemVersion") ?? ""
        let version: SystemVersion
        do {
            version = try SystemVersion.parse(versionRaw)
        } catch {
            throw PlistDecodeError.invalidVersion(versionRaw)
        }

        let hidesDockIcon: Bool
        if let raw = dict["LSUIElement"] {
            guard let value = strictBool(raw) else {
                throw PlistDecodeError.invalidBoolean("LSUIElement")
            }
            hidesDockIcon = value
        } else {
            hidesDockIcon = false
        }

        return MenuBarManifest(
            bundleIdentifier: string(dict, "CFBundleIdentifier") ?? "",
            bundleName: string(dict, "CFBundleName") ?? "",
            bundleExecutable: string(dict, "CFBundleExecutable") ?? "",
            packageType: string(dict, "CFBundlePackageType"),
            minimumSystemVersion: version,
            hidesDockIcon: hidesDockIcon
        )
    }

    private static func dictionary(from object: Any) -> [String: Any]? {
        if let dict = object as? [String: Any] {
            return dict
        }
        guard let ns = object as? NSDictionary else { return nil }
        var result: [String: Any] = [:]
        for case let (key as String, value) in ns {
            result[key] = value
        }
        return result
    }

    private static func string(_ dict: [String: Any], _ key: String) -> String? {
        dict[key] as? String
    }

    /// Accepts a property-list boolean and rejects integers, including `1`.
    private static func strictBool(_ value: Any) -> Bool? {
        guard let bool = value as? Bool else { return nil }
        guard let number = value as? NSNumber else { return bool }
        let objCType = String(cString: number.objCType)
        switch objCType {
        case "c", "C", "B":
            return bool
        default:
            return nil
        }
    }
}
