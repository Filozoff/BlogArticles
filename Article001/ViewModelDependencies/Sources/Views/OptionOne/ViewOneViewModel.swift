import Foundation

@MainActor
class ViewOneViewModel: ObservableObject {
    
    @Published var id = "nil"
    @Published var name = ""

    var userRepository: UserRepository?

    @Published private(set) var isFetchingData = false

    private var currentTask: Task<Void, Error>?

    init() {
        print("\(Self.self): \(#function)")
    }

    deinit {
        print("\(Self.self): \(#function)")
        currentTask?.cancel()
    }

    private func fetchUserData() {
        guard !isFetchingData else { return }
        isFetchingData = true
        currentTask = Task { [weak self] in
            do {
                print("Fetching data...")
                guard let id = self?.id,
                      let repository = self?.userRepository
                else { return }

                let name = try await repository.fetchName(id: id)
                self?.name = name
                print("Fetched")
            } catch {
                print(error.localizedDescription)
            }

            self?.isFetchingData = false
        }
    }
}


// MARK: - Actions

extension ViewOneViewModel {

    func onAppear() {
        fetchUserData()
    }
}
