import Combine
import Foundation

@MainActor
final class ServerConfiguration: ObservableObject {
    static let defaultBaseURL = URL(string: "https://unconsecrative-lustrelessly-jeanie.ngrok-free.dev")!

    @Published private(set) var baseURL: URL

    private let defaults: UserDefaults
    private let storageKey = "cheeseek.serverBaseURL"

    init(baseURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let baseURL {
            self.baseURL = baseURL
        } else if let stored = defaults.string(forKey: storageKey),
                  let url = Self.normalizedURL(from: stored) {
            self.baseURL = url
        } else {
            self.baseURL = Self.defaultBaseURL
        }
    }

    var baseURLString: String {
        baseURL.absoluteString
    }

    func updateBaseURL(from rawValue: String) throws {
        guard let url = Self.normalizedURL(from: rawValue) else {
            throw ServerConfigurationError.invalidURL
        }
        baseURL = url
        defaults.set(url.absoluteString, forKey: storageKey)
    }

    private static func normalizedURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

enum ServerConfigurationError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Enter a valid http:// or https:// backend URL."
        }
    }
}
