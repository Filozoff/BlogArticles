import SwiftUI

public struct AccessibilityIdentifierBranchModifier: ViewModifier {

    @Environment(\.parentAccessibilityBranch) private var parentBranch

    private let branch: String

    public init(branch: String) {
        self.branch = branch
    }

    public func body(content: Content) -> some View {
        content
            .environment(\.parentAccessibilityBranch, makeGroupPath())
    }

    private func makeGroupPath() -> String {
        guard let parentBranch = parentBranch else { return branch }
        return "\(parentBranch).\(branch)"
    }
}

public extension View {

    func accessibilityIdentifierBranch(_ branch: String) -> ModifiedContent<Self, AccessibilityIdentifierBranchModifier> {
        modifier(AccessibilityIdentifierBranchModifier(branch: branch))
    }
}
