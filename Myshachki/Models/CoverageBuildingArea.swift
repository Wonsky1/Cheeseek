import CoreLocation
import Foundation

struct CoverageBuildingArea: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let coveredSideCount: Int

    var isFullyCovered: Bool {
        coveredSideCount > 1
    }
}

struct CoverageBuildingSide {
    let id: String
    let buildingID: String
    let area: CoverageBuildingArea
}

enum CoverageBuildingCodec {
    private static let prefix = "building:v1"
    private static let latitudeCellSize = 0.00028
    private static let longitudeCellSize = 0.00035
    private static let sideOffsetMeters = 28.0
    private static let parcelWidthMeters = 30.0
    private static let parcelDepthMeters = 24.0

    static func sideIDs(from points: [TrackPoint]) -> Set<String> {
        Set(sides(from: points).map(\.id))
    }

    static func areas(from ids: Set<String>) -> [CoverageBuildingArea] {
        let sides = ids.compactMap { decode($0) }
        let groups = Dictionary(grouping: sides, by: \.buildingID)
        return groups.map { buildingID, sides in
            let template = sides.sorted { $0.id < $1.id }[0].area
            return CoverageBuildingArea(
                id: buildingID,
                coordinates: template.coordinates,
                coveredSideCount: Set(sides.map(\.id)).count
            )
        }
        .sorted { $0.id < $1.id }
    }

    static func buildingIDs(from ids: Set<String>) -> Set<String> {
        Set(ids.compactMap { decode($0)?.buildingID })
    }

    static func sides(from points: [TrackPoint]) -> [CoverageBuildingSide] {
        guard points.count > 1 else { return [] }
        var seenIDs: Set<String> = []
        return zip(points, points.dropFirst()).flatMap { previous, current in
            sides(from: previous.coordinate, to: current.coordinate)
        }
        .filter { seenIDs.insert($0.id).inserted }
    }

    static func decode(_ id: String) -> CoverageBuildingSide? {
        let parts = id.split(separator: ":")
        guard parts.count == 6,
              parts[0] == "building",
              parts[1] == "v1",
              let latitudeCell = Int(parts[2]),
              let longitudeCell = Int(parts[3]),
              Int(parts[4]) != nil,
              let angleIndex = Int(parts[5]) else {
            return nil
        }

        let center = coordinate(latitudeCell: latitudeCell, longitudeCell: longitudeCell)
        let buildingID = "\(prefix):\(latitudeCell):\(longitudeCell)"
        let coordinates = rectangle(
            center: center,
            widthMeters: parcelWidthMeters,
            depthMeters: parcelDepthMeters,
            angleRadians: angle(for: angleIndex)
        )

        return CoverageBuildingSide(
            id: id,
            buildingID: buildingID,
            area: CoverageBuildingArea(id: buildingID, coordinates: coordinates, coveredSideCount: 1)
        )
    }

    private static func sides(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> [CoverageBuildingSide] {
        let vector = metersVector(from: start, to: end)
        let length = hypot(vector.x, vector.y)
        guard length >= LocationManager.minimumMovementDistance else { return [] }

        let unit = (x: vector.x / length, y: vector.y / length)
        let normal = (x: -unit.y, y: unit.x)
        let midpoint = CLLocationCoordinate2D(
            latitude: (start.latitude + end.latitude) / 2,
            longitude: (start.longitude + end.longitude) / 2
        )
        let angleIndex = quantizedAngleIndex(x: unit.x, y: unit.y)

        return [-1.0, 1.0].compactMap { side in
            let center = offset(midpoint, eastMeters: normal.x * sideOffsetMeters * side, northMeters: normal.y * sideOffsetMeters * side)
            let cell = cellKey(for: center)
            let sideIndex = quantizedAngleIndex(x: normal.x * side, y: normal.y * side)
            let id = "\(prefix):\(cell.latitude):\(cell.longitude):\(sideIndex):\(angleIndex)"
            return decode(id)
        }
    }

    private static func cellKey(for coordinate: CLLocationCoordinate2D) -> (latitude: Int, longitude: Int) {
        (
            latitude: Int((coordinate.latitude / latitudeCellSize).rounded()),
            longitude: Int((coordinate.longitude / longitudeCellSize).rounded())
        )
    }

    private static func coordinate(latitudeCell: Int, longitudeCell: Int) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: Double(latitudeCell) * latitudeCellSize,
            longitude: Double(longitudeCell) * longitudeCellSize
        )
    }

    private static func metersVector(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let metersPerLatitudeDegree = 111_320.0
        let metersPerLongitudeDegree = metersPerLatitudeDegree * cos(start.latitude * .pi / 180)
        return (
            x: (end.longitude - start.longitude) * metersPerLongitudeDegree,
            y: (end.latitude - start.latitude) * metersPerLatitudeDegree
        )
    }

    private static func offset(_ coordinate: CLLocationCoordinate2D, eastMeters: Double, northMeters: Double) -> CLLocationCoordinate2D {
        let metersPerLatitudeDegree = 111_320.0
        let metersPerLongitudeDegree = metersPerLatitudeDegree * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + northMeters / metersPerLatitudeDegree,
            longitude: coordinate.longitude + eastMeters / metersPerLongitudeDegree
        )
    }

    private static func rectangle(
        center: CLLocationCoordinate2D,
        widthMeters: Double,
        depthMeters: Double,
        angleRadians: Double
    ) -> [CLLocationCoordinate2D] {
        let corners = [
            (-widthMeters / 2, -depthMeters / 2),
            (widthMeters / 2, -depthMeters / 2),
            (widthMeters / 2, depthMeters / 2),
            (-widthMeters / 2, depthMeters / 2)
        ]
        return corners.map { x, y in
            let rotatedX = x * cos(angleRadians) - y * sin(angleRadians)
            let rotatedY = x * sin(angleRadians) + y * cos(angleRadians)
            return offset(center, eastMeters: rotatedX, northMeters: rotatedY)
        }
    }

    private static func quantizedAngleIndex(x: Double, y: Double) -> Int {
        let angle = atan2(y, x)
        let normalized = angle < 0 ? angle + 2 * .pi : angle
        return Int((normalized / (.pi / 4)).rounded()) % 8
    }

    private static func angle(for index: Int) -> Double {
        Double(index) * .pi / 4
    }
}
