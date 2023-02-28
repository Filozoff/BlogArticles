import SwiftUI

struct ViewTwo: View {

    @StateObject private var viewModel: ViewTwoViewModel

    init(viewModel: @escaping @autoclosure ReturnClosure<ViewTwoViewModel>) {
        _viewModel = .init(wrappedValue: viewModel())
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Your ID: \(viewModel.id)")
            HStack {
                Text("Name: ")
                TextField("type name", text: $viewModel.name)
                if viewModel.isFetchingData {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .padding()
            .background(.quaternary)
            .cornerRadius(10)
            .disabled(viewModel.isFetchingData)

            NavigationLink("Next View", value: RootView.Page.nextView)
        }
        .padding()
        .onAppear {
            viewModel.onAppear()
        }
    }
}

struct ViewTwo_Previews: PreviewProvider {

    static var previews: some View {
        ViewTwo(
            viewModel: .init(
                id: "test id",
                userRepository: .init()
            )
        )
    }
}
