import Foundation
import CoreFoundation

public enum ApplicationDockError: Error, Sendable {
    case invalidPreferences, managedPreferences, preferencesChanged, writeFailed, refreshFailed
}

/// Data keeps unrecognized Dock fields intact without sharing untyped values across actors.
public protocol DockPreferencesAccess: Sendable {
    func read(_ key: String) throws -> Data?
    func replace(_ key: String, expected: Data?, value: Data) throws
    func refresh() throws
}

public struct SystemDockPreferences: DockPreferencesAccess {
    public init() {}
    private var domain: CFString { "com.apple.dock" as CFString }

    public func read(_ key: String) throws -> Data? {
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw ApplicationDockError.writeFailed
        }
        guard let value = CFPreferencesCopyValue(key as CFString, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    public func replace(_ key: String, expected: Data?, value: Data) throws {
        guard !CFPreferencesAppValueIsForced(key as CFString, domain) else { throw ApplicationDockError.managedPreferences }
        guard try Self.equal(read(key), expected) else { throw ApplicationDockError.preferencesChanged }
        let object = try PropertyListSerialization.propertyList(from: value, format: nil)
        CFPreferencesSetValue(key as CFString, object as CFPropertyList, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
              try Self.equal(read(key), value) else { throw ApplicationDockError.writeFailed }
    }

    private static func equal(_ lhs: Data?, _ rhs: Data?) throws -> Bool {
        guard let lhs, let rhs else { return lhs == rhs }
        let a = try PropertyListSerialization.propertyList(from: lhs, format: nil) as AnyObject
        let b = try PropertyListSerialization.propertyList(from: rhs, format: nil)
        return (a as? NSObject)?.isEqual(b) == true
    }

    public func refresh() throws {
        // Refresh only this user's Dock, once per batch. No shell or global preference reset.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-u", NSUserName(), "-TERM", "Dock"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 || process.terminationStatus == 1 else { throw ApplicationDockError.refreshFailed }
    }
}

/// Saves only affected tiles. The journal survives app restarts and is committed before Dock edits.
public actor ApplicationDockService {
    private let directory: URL
    private let preferences: any DockPreferencesAccess
    private let exists: @Sendable (URL) -> Bool
    private static let keys = ["persistent-apps", "recent-apps"]

    private struct Tile: Codable {
        let application: URL
        let key: String
        let position: Int
        let data: Data
    }
    private struct Journal: Codable {
        let applications: [URL]
        var tiles: [Tile]
        var removed: Set<String> = []
        var restored: Set<String> = []
        var refreshPending = false
    }

    public init(directory: URL, preferences: any DockPreferencesAccess = SystemDockPreferences(),
                exists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        self.directory = directory
        self.preferences = preferences
        self.exists = exists
    }

    public func prepare(receiptID: UUID, plan: CleanupPlan) throws {
        let applications = plan.selectedItems.compactMap { item -> URL? in
            let candidate = item.candidate
            guard candidate.category == .application, candidate.source == .application,
                  candidate.url.isFileURL, candidate.url.pathExtension.lowercased() == "app" else { return nil }
            return candidate.url.standardizedFileURL
        }
        guard !applications.isEmpty else { return }
        guard !FileManager.default.fileExists(atPath: journalURL(receiptID).path) else { return }
        let paths = Set(applications.map(\.path))
        var tiles = [Tile]()
        for key in Self.keys {
            for (position, tile) in try Self.array(preferences.read(key)).enumerated() {
                guard let url = Self.applicationURL(tile), paths.contains(url.path) else { continue }
                tiles.append(Tile(application: url, key: key, position: position, data: try Self.encode(tile)))
            }
        }
        try save(Journal(applications: applications, tiles: tiles), receiptID)
    }

    public func synchronize(receipt: OperationReceipt) throws {
        let url = journalURL(receipt.id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var journal = try PropertyListDecoder().decode(Journal.self, from: Data(contentsOf: url))
        let applications = Set(journal.applications.map(\.path))
        let removedResults = receipt.results.filter {
            applications.contains($0.originalURL.standardizedFileURL.path) && $0.status == .succeeded
                && $0.verificationNotBefore == nil && [.quarantined, .trashed, .permanentlyDeleted].contains($0.disposition)
                && !journal.removed.contains($0.originalURL.standardizedFileURL.path) && !exists($0.originalURL)
        }
        let restoredResults = receipt.results.filter {
            applications.contains($0.originalURL.standardizedFileURL.path) && $0.disposition == .restored
                && [.restored, .restoreConflict].contains($0.status)
                && !journal.restored.contains($0.originalURL.standardizedFileURL.path)
                && $0.destinationURL.map(exists) == true
        }
        guard !removedResults.isEmpty || !restoredResults.isEmpty || journal.refreshPending else { return }
        for key in Self.keys {
            let before = try preferences.read(key)
            var tiles = try Self.array(before)
            var changed = false
            for result in removedResults {
                let original = result.originalURL.standardizedFileURL
                let saved = journal.tiles.filter { $0.key == key && $0.application.path == original.path }
                let savedGUIDs = Set(try saved.compactMap { try Self.guid(Self.tile($0.data)) })
                let matched = tiles.enumerated().filter { _, tile in
                    guard let path = Self.applicationURL(tile)?.path else { return false }
                    if path == original.path { return true }
                    // Finder can update the tile URL after the application moves to quarantine.
                    return result.destinationURL?.standardizedFileURL.path == path
                        && Self.guid(tile).map(savedGUIDs.contains) == true
                }
                for (position, tile) in matched {
                    let guid = Self.guid(tile)
                    if !saved.contains(where: { (try? Self.guid(Self.tile($0.data))) == guid }) {
                        journal.tiles.append(Tile(application: original, key: key, position: position,
                            data: try Self.encode(Self.retarget(tile, to: original))))
                    }
                }
                let positions = Set(matched.map(\.offset))
                if !positions.isEmpty {
                    tiles = tiles.enumerated().filter { !positions.contains($0.offset) }.map(\.element)
                    changed = true
                }
            }
            for result in restoredResults {
                guard let destination = result.destinationURL else { continue }
                // Never duplicate a tile the user has already put back.
                if tiles.contains(where: { Self.applicationURL($0)?.path == destination.standardizedFileURL.path }) { continue }
                let saved = journal.tiles.filter { $0.key == key && $0.application.path == result.originalURL.standardizedFileURL.path }
                    .sorted { $0.position < $1.position }
                for tile in saved {
                    var restored = try Self.retarget(Self.tile(tile.data), to: destination)
                    if let guid = Self.guid(restored), tiles.contains(where: { Self.guid($0) == guid }) {
                        restored["GUID"] = UInt32.random(in: 1...UInt32.max)
                    }
                    tiles.insert(restored, at: min(tile.position, tiles.count))
                    changed = true
                }
            }
            if changed {
                journal.refreshPending = true
                try save(journal, receipt.id)
                try preferences.replace(key, expected: before, value: Self.encode(tiles))
            }
        }
        if journal.refreshPending {
            try preferences.refresh()
            journal.refreshPending = false
        }
        journal.removed.formUnion(removedResults.map { $0.originalURL.standardizedFileURL.path })
        journal.restored.formUnion(restoredResults.map { $0.originalURL.standardizedFileURL.path })
        try save(journal, receipt.id)
    }

    private func journalURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".plist") }
    private func save(_ journal: Journal, _ id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        try encoder.encode(journal).write(to: journalURL(id), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL(id).path)
    }
    private static func encode(_ value: Any) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }
    private static func array(_ data: Data?) throws -> [[String: Any]] {
        guard let data else { return [] }
        guard let array = try PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            throw ApplicationDockError.invalidPreferences
        }
        return array
    }
    private static func tile(_ data: Data) throws -> [String: Any] {
        guard let tile = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ApplicationDockError.invalidPreferences
        }
        return tile
    }
    private static func guid(_ tile: [String: Any]) -> String? { (tile["GUID"] as? NSNumber)?.stringValue }
    private static func applicationURL(_ tile: [String: Any]) -> URL? {
        guard tile["tile-type"] as? String == "file-tile",
              let data = tile["tile-data"] as? [String: Any], let file = data["file-data"] as? [String: Any],
              let text = file["_CFURLString"] as? String else { return nil }
        let url: URL?
        if text.hasPrefix("/") { url = URL(fileURLWithPath: text) }
        else { url = URL(string: text) }
        guard let url, url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost" else { return nil }
        return url.standardizedFileURL
    }
    private static func retarget(_ tile: [String: Any], to url: URL) -> [String: Any] {
        var tile = tile
        var data = tile["tile-data"] as? [String: Any] ?? [:]
        data["file-data"] = ["_CFURLString": url.standardizedFileURL.absoluteString, "_CFURLStringType": 15]
        // The saved bookmark can track a different copy after a conflicting restore.
        data.removeValue(forKey: "book")
        tile["tile-data"] = data
        return tile
    }
}
