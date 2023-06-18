import SwiftUI

public struct AccessibilityIdentifierLeafModifier: ViewModifier {

    @Environment(\.parentAccessibilityBranch) private var branch

    private let leaf: String

    public init(leaf: String) {
        self.leaf = leaf
    }

    public func body(content: Content) -> some View {
        if let branch = branch {
            content
                .accessibilityIdentifier("\(branch).\(leaf)")
                .environment(\.parentAccessibilityBranch, nil)
        } else {
            content
        }
    }
}

public extension View {

    func accessibilityIdentifierLeaf(_ leaf: String) -> ModifiedContent<Self, AccessibilityIdentifierLeafModifier> {
        modifier(AccessibilityIdentifierLeafModifier(leaf: leaf))
    }
}
