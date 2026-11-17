import Foundation
import SupervimCore

/// A one-line count of the accessibility nodes a scan walked.
public enum AccessibilityTreeSummary {
    public static func counts(
        in root: AccessibilityElement,
        limits: TreeWalkLimits
    ) -> (nodes: Int, roles: [String: Int]) {
        var nodes = 0
        var roles: [String: Int] = [:]
        func visit(_ node: AccessibilityElement, depth: Int) {
            if nodes >= limits.maxNodes || depth > limits.maxDepth {
                return
            }
            nodes += 1
            let role = node.role ?? "none"
            roles[role, default: 0] += 1
            if depth == limits.maxDepth {
                return
            }
            for child in node.children {
                if nodes >= limits.maxNodes {
                    return
                }
                visit(child, depth: depth + 1)
            }
        }
        visit(root, depth: 0)
        return (nodes, roles)
    }

    public static func line(bundle: String, nodes: Int, roles: [String: Int]) -> String {
        let name = bundle.isEmpty ? "-" : bundle
        let parts = roles.keys.sorted().map { "\($0):\(roles[$0] ?? 0)" }.joined(separator: ",")
        return "ax-summary bundle=\(name) nodes=\(nodes) roles=\(parts)"
    }
}
