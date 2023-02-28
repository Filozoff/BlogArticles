import Foundation

@MainActor
class ViewTwoViewModel: ObservableObject {

    @Published var name = ""

    let id: String
    let userRepository: UserRepository

    @Published private(set) var isFetchingData = false

    private var currentTask: Task<Void, Error>?

    init(id: String, userRepository: UserRepository) {
        print("\(Self.self): \(#function)")
        self.id = id
        self.userRepository = userRepository
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

extension ViewTwoViewModel {

    func onAppear() {
        fetchUserData()
    }
}
