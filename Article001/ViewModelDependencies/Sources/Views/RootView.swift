import SwiftUI

struct RootView: View {

    @State private var tabSelection = TabSelection.options
    @State private var path = [Page]()
    @State private var isVisible = true

    private let nameRepository = NameRepository()

    init() { }

    var body: some View {
        TabView(selection: $tabSelection) {
            options()
                .tabItem {
                    Label("Options", systemImage: "list.bullet.circle")
                }
                .tag(TabSelection.options)

            Color.clear
                .tabItem {
                    Label("Empty", systemImage: "circle")
                }
                .tag(TabSelection.empty)
        }
    }

    @MainActor
    @ViewBuilder
    private func options() -> some View {
        NavigationStack(path: $path) {
            List {
                Toggle("Toggle", isOn: $isVisible)
                if isVisible {
                    NavigationLink("Option one", value: Page.optionOne(id: "1234"))
                    NavigationLink("Option two", value: Page.optionTwo(id: "5678"))
                }
            }
            .animation(.default, value: isVisible)
            .navigationTitle("Options")
            .navigationDestination(for: Page.self) {
                switch $0 {
                case .optionOne(let id):
                    ViewOne(
                        id: id,
                        name: "",
                        nameRepository: nameRepository
                    )

                case .optionTwo(let id):
                    ViewTwo(
                        viewModel: .init(
                            id: id,
                            name: "",
                            nameRepository: nameRepository
                        )
                    )

                case .nextView:
                    NavigationLink("Next view", value: Page.nextView)
                }
            }
        }
    }
}

extension RootView {

    enum Page: Hashable {
        case optionOne(id: String)
        case optionTwo(id: String)
        case nextView
    }
}

extension RootView {

    enum TabSelection: Hashable {
        case empty
        case options
    }
}

struct RootView_Previews: PreviewProvider {

    static var previews: some View {
        RootView()
    }
}
