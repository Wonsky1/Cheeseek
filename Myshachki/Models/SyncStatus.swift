import Foundation

enum SyncStatus: String, Codable, CaseIterable {
    case localOnly
    case readyToSync
    case syncing
    case synced
    case failed

    var label: String {
        switch self {
        case .localOnly: "Saved locally"
        case .readyToSync: "Ready to sync"
        case .syncing: "Syncing"
        case .synced: "Synced"
        case .failed: "Sync failed"
        }
    }
}
