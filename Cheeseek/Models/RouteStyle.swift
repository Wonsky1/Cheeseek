import SwiftUI

struct RouteStyle: Equatable {
    let color: Color
    let lineWidth: Double
    let dash: [CGFloat]

    static let completed = RouteStyle(color: Color.teal, lineWidth: 5, dash: [])
    static let active = RouteStyle(color: Color.blue, lineWidth: 6, dash: [])
}
