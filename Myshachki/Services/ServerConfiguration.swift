import Foundation

struct ServerConfiguration {
    let baseURL: URL

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? URL(string: "https://unconsecrative-lustrelessly-jeanie.ngrok-free.dev")!
    }
}
