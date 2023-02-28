import SwiftUI

struct ViewOne: View {

    let id: String
    let userRepository: UserRepository

    @StateObject private var viewModel = ViewOneViewModel()

    init(id: String, userRepository: UserRepository) {
        self.id = id
        self.userRepository = userRepository
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
        .onLoad {
            viewModel.id = id
            viewModel.userRepository = userRepository
        }
        .onAppear {
            viewModel.onAppear()
        }
    }
}

struct ViewOne_Previews: PreviewProvider {

    static var previews: some View {
        ViewOne(
            id: "test id",
            userRepository: .init()
        )
    }
}
