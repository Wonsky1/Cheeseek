import CoreLocation
import Foundation

protocol MockRouteProviding {
    func routes() -> [RouteOverlay]
}

struct MockRouteProvider: MockRouteProviding {
    func routes() -> [RouteOverlay] {
        []
    }
}
