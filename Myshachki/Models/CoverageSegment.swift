import CoreLocation
import Foundation

struct CoverageSegment: Identifiable {
    let id: String
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D

    var coordinates: [CLLocationCoordinate2D] {
        [start, end]
    }
}

enum CoverageSegmentCodec {
    private static let prefix = "route:v1"
    private static let scale = 100_000.0

    static func segments(from points: [TrackPoint]) -> [CoverageSegment] {
        guard points.count > 1 else { return [] }
        var seenIDs: Set<String> = []
        return zip(points, points.dropFirst()).compactMap { previous, current in
            guard let segment = segment(from: previous.coordinate, to: current.coordinate) else { return nil }
            guard seenIDs.insert(segment.id).inserted else { return nil }
            return segment
        }
    }

    static func decode(_ id: String) -> CoverageSegment? {
        let parts = id.split(separator: ":")
        guard parts.count == 6,
              parts[0] == "route",
              parts[1] == "v1",
              let startLatitude = Int(parts[2]),
              let startLongitude = Int(parts[3]),
              let endLatitude = Int(parts[4]),
              let endLongitude = Int(parts[5]) else {
            return nil
        }

        return CoverageSegment(
            id: id,
            start: coordinate(latitude: startLatitude, longitude: startLongitude),
            end: coordinate(latitude: endLatitude, longitude: endLongitude)
        )
    }

    private static func segment(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CoverageSegment? {
        let startKey = key(for: start)
        let endKey = key(for: end)
        guard startKey != endKey else { return nil }
        let ordered = isOrdered(startKey, before: endKey) ? (startKey, endKey) : (endKey, startKey)
        let id = "\(prefix):\(ordered.0.latitude):\(ordered.0.longitude):\(ordered.1.latitude):\(ordered.1.longitude)"
        return CoverageSegment(
            id: id,
            start: coordinate(latitude: ordered.0.latitude, longitude: ordered.0.longitude),
            end: coordinate(latitude: ordered.1.latitude, longitude: ordered.1.longitude)
        )
    }

    private static func key(for coordinate: CLLocationCoordinate2D) -> (latitude: Int, longitude: Int) {
        (
            latitude: Int((coordinate.latitude * scale).rounded()),
            longitude: Int((coordinate.longitude * scale).rounded())
        )
    }

    private static func isOrdered(
        _ lhs: (latitude: Int, longitude: Int),
        before rhs: (latitude: Int, longitude: Int)
    ) -> Bool {
        if lhs.latitude != rhs.latitude {
            return lhs.latitude < rhs.latitude
        }
        return lhs.longitude < rhs.longitude
    }

    private static func coordinate(latitude: Int, longitude: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: Double(latitude) / scale, longitude: Double(longitude) / scale)
    }
}
