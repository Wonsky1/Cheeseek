import Foundation

enum MapPerspectiveMode: String, CaseIterable, Codable {
    case flat
    case threeD

    var buttonTitle: String {
        switch self {
        case .flat:
            "3D"
        case .threeD:
            "Flat"
        }
    }

    var buttonSystemImage: String {
        switch self {
        case .flat:
            "cube.transparent"
        case .threeD:
            "map"
        }
    }

    var isThreeDimensional: Bool {
        self == .threeD
    }
}

enum MapStyleMode: String, CaseIterable, Codable {
    case light
    case dark

    var buttonTitle: String {
        switch self {
        case .light:
            "Dark"
        case .dark:
            "Light"
        }
    }

    var buttonSystemImage: String {
        switch self {
        case .light:
            "moon.fill"
        case .dark:
            "sun.max.fill"
        }
    }

    var isDark: Bool {
        self == .dark
    }
}
