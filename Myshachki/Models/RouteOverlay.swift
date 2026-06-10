import CoreLocation
import Foundation

struct RouteOverlay: Identifiable {
    let id: UUID
    let owner: MapFilter
    let title: String
    let coordinates: [CLLocationCoordinate2D]
    let style: RouteStyle
}
