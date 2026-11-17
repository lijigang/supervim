import Foundation

public enum PermissionKind: Equatable, Sendable {
    case accessibility
    case inputMonitoring
}

public enum PermissionGrant: Equatable, Sendable {
    case granted
    case missing
}

/// Result of an Input Monitoring probe. Unknown is not a grant.
public enum ListenEventAccess: Equatable, Sendable {
    case granted
    case denied
    case unknown

    /// A grant requires the HID listen probe and the preflight to agree.
    /// A denied probe stays denied. Everything else, including a disagreement, is unknown.
    public static func resolve(
        hidGranted: Bool,
        hidDenied: Bool,
        hidUnknown: Bool,
        preflightGranted: Bool
    ) -> ListenEventAccess {
        if hidGranted, !hidDenied, !hidUnknown, preflightGranted {
            return .granted
        }
        if hidDenied, !hidGranted, !hidUnknown {
            return .denied
        }
        return .unknown
    }
}

public struct PermissionStatus: Equatable, Sendable {
    public var accessibility: PermissionGrant
    public var inputMonitoring: PermissionGrant

    public init(accessibility: PermissionGrant, inputMonitoring: PermissionGrant) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }

    /// Only an explicit grant counts. Unknown and denied Input Monitoring are missing.
    public init(accessibilityTrusted: Bool, listenEvent: ListenEventAccess) {
        self.accessibility = accessibilityTrusted ? .granted : .missing
        self.inputMonitoring = listenEvent == .granted ? .granted : .missing
    }
}

public struct PrivacyPaneLink: Equatable, Sendable {
    public var kind: PermissionKind
    public var title: String
    public var destination: String

    public init(kind: PermissionKind, title: String, destination: String) {
        self.kind = kind
        self.title = title
        self.destination = destination
    }
}

public struct PermissionGuidance: Equatable, Sendable {
    public var isVisible: Bool
    public var title: String
    public var body: String
    public var links: [PrivacyPaneLink]
    public var checkAgainTitle: String
    public var menuTitle: String
    public var notice: String

    public init(
        isVisible: Bool,
        title: String,
        body: String,
        links: [PrivacyPaneLink],
        checkAgainTitle: String,
        menuTitle: String,
        notice: String
    ) {
        self.isVisible = isVisible
        self.title = title
        self.body = body
        self.links = links
        self.checkAgainTitle = checkAgainTitle
        self.menuTitle = menuTitle
        self.notice = notice
    }
}

public protocol PermissionStatusProviding: Sendable {
    func currentPermissionStatus() -> PermissionStatus
}

public protocol PrivacyPaneOpening: Sendable {
    func openPrivacyPane(destination: String) -> Bool
}

/// Decides when the permission guide is visible and which System Settings pane to open.
///
/// Opening a pane does not mean the grant is active. This process may still lack the
/// permission until it is quit and reopened, and that is not verified. An unsigned
/// rebuild may need the user to allow Supervim again.
public final class PermissionGuide: @unchecked Sendable {
    private let status: any PermissionStatusProviding
    private let opener: any PrivacyPaneOpening

    public init(status: any PermissionStatusProviding, opener: any PrivacyPaneOpening) {
        self.status = status
        self.opener = opener
    }

    public func refresh() -> PermissionGuidance {
        compose(status.currentPermissionStatus(), notice: "")
    }

    public func openLink(_ kind: PermissionKind) -> PermissionGuidance {
        let current = compose(status.currentPermissionStatus(), notice: "")
        guard let link = current.links.first(where: { $0.kind == kind }) else {
            return current
        }
        let opened = opener.openPrivacyPane(destination: link.destination)
        let notice = opened ? "" : Self.couldNotOpenNotice
        return compose(status.currentPermissionStatus(), notice: notice)
    }

    private func compose(_ status: PermissionStatus, notice: String) -> PermissionGuidance {
        var links: [PrivacyPaneLink] = []
        if status.accessibility == .missing {
            links.append(Self.accessibilityLink)
        }
        if status.inputMonitoring == .missing {
            links.append(Self.inputMonitoringLink)
        }
        guard !links.isEmpty else {
            return PermissionGuidance(
                isVisible: false,
                title: "",
                body: "",
                links: [],
                checkAgainTitle: Self.checkAgainTitle,
                menuTitle: Self.menuTitle,
                notice: ""
            )
        }
        return PermissionGuidance(
            isVisible: true,
            title: Self.windowTitle,
            body: Self.body(lead: Self.lead(for: status)),
            links: links,
            checkAgainTitle: Self.checkAgainTitle,
            menuTitle: Self.menuTitle,
            notice: notice
        )
    }

    private static func lead(for status: PermissionStatus) -> String {
        if status.accessibility == .missing, status.inputMonitoring == .missing {
            return "Supervim needs Accessibility and Input Monitoring. Open the System Settings pane for each one and turn Supervim on."
        }
        if status.accessibility == .missing {
            return "Supervim needs Accessibility. Open the System Settings pane and turn Supervim on."
        }
        return "Supervim needs Input Monitoring. Open the System Settings pane and turn Supervim on."
    }

    private static func body(lead: String) -> String {
        """
        \(lead)

        Granting a permission does not guarantee that this process receives it without quitting and reopening Supervim. Whether that happens depends on the system version and whether the permission database refreshes. It is not verified.

        An unsigned Supervim may need to be allowed again after it is rebuilt, because the code-directory hash can change.
        """
    }

    private static let windowTitle = "Supervim Needs Permissions"
    private static let checkAgainTitle = "Check Again"
    private static let menuTitle = "Permissions"
    private static let couldNotOpenNotice = "Could not open System Settings."

    private static let accessibilityLink = PrivacyPaneLink(
        kind: .accessibility,
        title: "Open Accessibility Settings",
        destination: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    )

    private static let inputMonitoringLink = PrivacyPaneLink(
        kind: .inputMonitoring,
        title: "Open Input Monitoring Settings",
        destination: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ListenEvent"
    )
}

public struct PermissionLaunchStep: Equatable, Sendable {
    public var guidance: PermissionGuidance
    public var shouldStartRuntime: Bool

    public init(guidance: PermissionGuidance, shouldStartRuntime: Bool) {
        self.guidance = guidance
        self.shouldStartRuntime = shouldStartRuntime
    }
}

/// Shows the guide while a permission is missing. After the guide disappears,
/// asks the caller to run `SupervimRuntime.start` once. A start that does not
/// come up can be asked again. `noteRuntimeStarted` records that the hook path ran.
public final class PermissionLaunchGate: @unchecked Sendable {
    private let guide: PermissionGuide
    private var runtimeIsUp = false

    public init(guide: PermissionGuide) {
        self.guide = guide
    }

    public func refresh() -> PermissionLaunchStep {
        step(guide.refresh())
    }

    public func openLink(_ kind: PermissionKind) -> PermissionLaunchStep {
        step(guide.openLink(kind))
    }

    public func noteRuntimeStarted() {
        runtimeIsUp = true
    }

    private func step(_ guidance: PermissionGuidance) -> PermissionLaunchStep {
        PermissionLaunchStep(
            guidance: guidance,
            shouldStartRuntime: !guidance.isVisible && !runtimeIsUp
        )
    }
}
