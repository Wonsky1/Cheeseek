import Foundation

protocol CoverageStoring {
    func loadCoverage(userId: UUID, areaId: String) throws -> Set<String>
    func saveCoverage(userId: UUID, areaId: String, coveredFeatureIDs: Set<String>) throws
}

final class CoverageStore: CoverageStoring {
    private struct CoveragePayload: Codable {
        let coveredFeatureIDs: [String]
        let updatedAt: Date
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadCoverage(userId: UUID, areaId: String) throws -> Set<String> {
        guard let data = defaults.data(forKey: storageKey(userId: userId, areaId: areaId)) else { return [] }
        let payload = try decoder.decode(CoveragePayload.self, from: data)
        return Set(payload.coveredFeatureIDs)
    }

    func saveCoverage(userId: UUID, areaId: String, coveredFeatureIDs: Set<String>) throws {
        let payload = CoveragePayload(coveredFeatureIDs: coveredFeatureIDs.sorted(), updatedAt: .now)
        let data = try encoder.encode(payload)
        defaults.set(data, forKey: storageKey(userId: userId, areaId: areaId))
    }

    private func storageKey(userId: UUID, areaId: String) -> String {
        "myshachki.coverage.\(userId.uuidString).\(areaId)"
    }
}

final class InMemoryCoverageStore: CoverageStoring {
    private var coverageByKey: [String: Set<String>] = [:]

    func loadCoverage(userId: UUID, areaId: String) throws -> Set<String> {
        coverageByKey[storageKey(userId: userId, areaId: areaId)] ?? []
    }

    func saveCoverage(userId: UUID, areaId: String, coveredFeatureIDs: Set<String>) throws {
        coverageByKey[storageKey(userId: userId, areaId: areaId)] = coveredFeatureIDs
    }

    private func storageKey(userId: UUID, areaId: String) -> String {
        "\(userId.uuidString)-\(areaId)"
    }
}
