import Foundation

class NameRepository {

    init() { }

    func fetchNames() async throws -> [String] {
        try await Task.sleep(for: .seconds(2))
        return [
            "Anna",
            "Jason",
            "Dwayne"
        ]
    }
}
