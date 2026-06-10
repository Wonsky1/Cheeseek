import Foundation

protocol WalkSessionStoring {
    func loadSessions() async throws -> [WalkSession]
    func saveSession(_ session: WalkSession) async throws
    func replaceSessions(_ sessions: [WalkSession]) async throws
}

final class FileWalkSessionStore: WalkSessionStoring {
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let folderName = "Myshachki"
    private let fileName = "walk-sessions.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSessions() async throws -> [WalkSession] {
        let url = try fileURL()
        guard fileManager.fileExists(atPath: url.path()) else { return [] }
        let data = try Data(contentsOf: url)
        return try decoder.decode([WalkSession].self, from: data)
    }

    func saveSession(_ session: WalkSession) async throws {
        var sessions = try await loadSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        try await replaceSessions(sessions)
    }

    func replaceSessions(_ sessions: [WalkSession]) async throws {
        try ensureDirectory()
        let data = try encoder.encode(sessions)
        try data.write(to: try fileURL(), options: .atomic)
    }

    private func ensureDirectory() throws {
        let url = try directoryURL()
        if !fileManager.fileExists(atPath: url.path()) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func directoryURL() throws -> URL {
        let base = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appending(path: folderName, directoryHint: .isDirectory)
    }

    private func fileURL() throws -> URL {
        try directoryURL().appending(path: fileName)
    }
}

final class PreviewWalkSessionStore: WalkSessionStoring {
    private var sessions: [WalkSession] = []

    func loadSessions() async throws -> [WalkSession] { sessions }
    func saveSession(_ session: WalkSession) async throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }
    func replaceSessions(_ sessions: [WalkSession]) async throws { self.sessions = sessions }
}
