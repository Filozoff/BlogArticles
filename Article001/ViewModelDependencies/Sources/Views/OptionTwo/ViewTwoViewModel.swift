import Foundation

@MainActor
class ViewTwoViewModel: ObservableObject {

    @Published var name = ""

    let id: String
    let nameRepository: NameRepository

    init(id: String, name: String, nameRepository: NameRepository) {
        self.id = id
        self.name = name
        self.nameRepository = nameRepository
        print("\(Self.self): \(#function)")
    }

    deinit {
        print("\(Self.self): \(#function)")
    }

    private func fetchNames() {
        Task {
            do {
                print("Fetching data...")
                _ = try await nameRepository.fetchNames()
                print("Fetched")
            } catch {
                print(error.localizedDescription)
            }
        }
    }
}

// MARK: - Actions

extension ViewTwoViewModel {

    func onAppear() {
        fetchNames()
    }
}
