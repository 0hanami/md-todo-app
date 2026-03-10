import Foundation

/// Strategies for resolving file version conflicts.
public enum ConflictResolutionStrategy: Sendable {
    /// Keep the most recently modified version.
    case keepNewest
    /// Keep the local (current) version.
    case keepLocal
    /// Keep the remote (conflict) version.
    case keepRemote
    /// Merge both versions by appending remote todos not in local.
    case merge
}

/// Resolves NSFileVersion conflicts on iCloud Documents files.
public final class ConflictResolver: Sendable {

    public init() {}

    /// Resolves all unresolved conflicts for the file at the given URL.
    ///
    /// - Parameters:
    ///   - url: The file URL with conflicts.
    ///   - strategy: How to resolve the conflict.
    /// - Returns: The content of the winning version, or nil if no conflicts found.
    /// - Throws: File reading or version resolution errors.
    public func resolveConflicts(
        at url: URL,
        strategy: ConflictResolutionStrategy = .keepNewest
    ) throws -> String? {
        guard let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url),
              !conflictVersions.isEmpty else {
            return nil
        }

        let currentVersion = NSFileVersion.currentVersionOfItem(at: url)
        let currentDate = currentVersion?.modificationDate ?? Date.distantPast

        var resolvedContent: String?

        switch strategy {
        case .keepNewest:
            resolvedContent = try resolveByKeepingNewest(
                url: url,
                currentDate: currentDate,
                conflictVersions: conflictVersions
            )

        case .keepLocal:
            resolvedContent = try String(contentsOf: url, encoding: .utf8)

        case .keepRemote:
            if let newest = conflictVersions
                .sorted(by: { ($0.modificationDate ?? .distantPast) > ($1.modificationDate ?? .distantPast) })
                .first {
                resolvedContent = try String(contentsOf: newest.url, encoding: .utf8)
            }

        case .merge:
            resolvedContent = try mergeContent(url: url, conflictVersions: conflictVersions)
        }

        // Mark all conflicts as resolved
        for version in conflictVersions {
            version.isResolved = true
        }

        try NSFileVersion.removeOtherVersionsOfItem(at: url)

        return resolvedContent
    }

    // MARK: - Private

    private func resolveByKeepingNewest(
        url: URL,
        currentDate: Date,
        conflictVersions: [NSFileVersion]
    ) throws -> String {
        var newestDate = currentDate
        var newestURL = url

        for version in conflictVersions {
            let versionDate = version.modificationDate ?? .distantPast
            if versionDate > newestDate {
                newestDate = versionDate
                newestURL = version.url
            }
        }

        return try String(contentsOf: newestURL, encoding: .utf8)
    }

    private func mergeContent(url: URL, conflictVersions: [NSFileVersion]) throws -> String {
        let localContent = try String(contentsOf: url, encoding: .utf8)
        var localLines = Set(localContent.components(separatedBy: "\n"))

        var mergedContent = localContent

        for version in conflictVersions {
            let remoteContent = try String(contentsOf: version.url, encoding: .utf8)
            let remoteLines = remoteContent.components(separatedBy: "\n")

            for line in remoteLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !localLines.contains(line) {
                    // Only merge checkbox lines to avoid duplicating headers
                    if trimmed.hasPrefix("- [ ]") || trimmed.hasPrefix("- [x]") || trimmed.hasPrefix("- [X]") {
                        mergedContent += "\n" + line
                        localLines.insert(line)
                    }
                }
            }
        }

        return mergedContent
    }
}
