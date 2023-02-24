import Foundation

@MainActor
class ViewOneViewModel: ObservableObject {
    
    @Published var id = "nil"
    @Published var name = ""

    var nameRepository: NameRepository?

    init() {
        print("\(Self.self): \(#function)")
    }

    deinit {
        print("\(Self.self): \(#function)")
    }

    private func fetchNames() {
        Task {
            do {
                print("Fetching data...")
                guard let repository = nameRepository else { return }
                _ = try await repository.fetchNames()
                print("Fetched")
            } catch {
                print(error.localizedDescription)
            }
        }
    }
}


// MARK: - Actions

extension ViewOneViewModel {

    func onAppear() {
        fetchNames()
    }
}
