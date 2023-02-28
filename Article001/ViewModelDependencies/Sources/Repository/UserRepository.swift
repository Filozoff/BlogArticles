import Foundation

class UserRepository {

    init() { }

    func fetchName(id: String) async throws -> String {
        try await Task.sleep(for: .seconds(5))
        return "Jan"
    }
}
