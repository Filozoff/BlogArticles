import SwiftUI

struct ViewOne: View {

    let id: String
    let name: String
    let nameRepository: NameRepository

    @StateObject private var viewModel = ViewOneViewModel()

    init(id: String, name: String, nameRepository: NameRepository) {
        self.id = id
        self.name = name
        self.nameRepository = nameRepository
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Your ID: \(viewModel.id)")
            HStack {
                Text("Name: ")
                TextField("type name", text: $viewModel.name)
            }
            NavigationLink("Next View", value: RootView.Page.nextView)
        }
        .padding()
        .onLoad {
            viewModel.id = id
            viewModel.name = name
            viewModel.nameRepository = nameRepository
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
            name: "test name",
            nameRepository: .init()
        )
    }
}
