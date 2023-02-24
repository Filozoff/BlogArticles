import SwiftUI

struct OnLoadViewModifier: ViewModifier {

    typealias Action = () -> ()

    @State private var isLoaded = false

    private let action: Action

    init(action: @escaping Action) {
        self.action = action
    }

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isLoaded else { return }
                isLoaded = true
                action()
            }
    }
}

extension View {

    func onLoad(perform action: @escaping OnLoadViewModifier.Action) -> some View {
        modifier(OnLoadViewModifier(action: action))
    }
}
