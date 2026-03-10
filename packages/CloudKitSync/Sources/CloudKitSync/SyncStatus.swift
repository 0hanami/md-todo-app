import Foundation

/// Represents the current synchronization state.
public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case synced
    case offline
    case conflict(local: Date, remote: Date)
    case error(String)

    public var displayText: String {
        switch self {
        case .idle: return ""
        case .syncing: return "Syncing..."
        case .synced: return "iCloud Drive"
        case .offline: return "Offline"
        case .conflict: return "Conflict"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    public var isAvailable: Bool {
        switch self {
        case .synced, .idle, .syncing: return true
        default: return false
        }
    }
}

/// Storage location for todo files.
public enum StorageLocation: String, Sendable {
    case local
    case icloud
}
