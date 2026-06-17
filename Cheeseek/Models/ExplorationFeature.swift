import CoreLocation
import Foundation

struct ExplorationFeature: Identifiable, Hashable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let center: CLLocationCoordinate2D
    let discoveryRadiusMeters: CLLocationDistance

    static func == (lhs: ExplorationFeature, rhs: ExplorationFeature) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
