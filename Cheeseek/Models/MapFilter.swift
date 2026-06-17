import Foundation

enum MapFilter: String, CaseIterable, Identifiable {
    case me = "Me"

    var id: String { rawValue }
}
