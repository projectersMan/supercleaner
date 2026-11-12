import Foundation

/// Description of a registered-client JSON manifest format. Product paths,
/// field names and version naming conventions live in the rule pack.
public struct CacheReferenceDescriptor: Codable, Hashable, Sendable {
    public let registryDirectory: String
    public let manifestFile: String
    public let entriesKey: String
    public let nameKey: String
    public let revisionKey: String
    public let revisionOverridesKey: String?
    public let artifactPattern: String
    public let replaceNameHyphensWithUnderscores: Bool
}

enum CacheReferenceInventory {
    enum State { case unused, referenced, unknown, metadata }

    static func state(of candidate: URL, descriptor: CacheReferenceDescriptor) -> State {
        let root = candidate.deletingLastPathComponent()
        let name = candidate.lastPathComponent
        guard name.range(of: descriptor.artifactPattern, options: .regularExpression) != nil else { return .metadata }
        let links = root.appendingPathComponent(descriptor.registryDirectory)
        guard let clients = try? FileManager.default.contentsOfDirectory(at: links, includingPropertiesForKeys: nil) else { return .unknown }
        var complete = true
        for client in clients {
            guard let bytes = boundedData(client), let text = String(data: bytes, encoding: .utf8),
                  text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") else { complete = false; continue }
            let package = URL(fileURLWithPath: text.trimmingCharacters(in: .whitespacesAndNewlines))
            // Inaccessible registrations are unknown, not proof that their client vanished.
            do { _ = try FileManager.default.attributesOfItem(atPath: package.path) }
            catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) { continue }
                complete = false; continue
            }
            guard let data = boundedData(package.appendingPathComponent(descriptor.manifestFile)),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let artifacts = object[descriptor.entriesKey] as? [[String: Any]] else { complete = false; continue }
            for artifact in artifacts {
                guard let artifactName = artifact[descriptor.nameKey] as? String, let revision = artifact[descriptor.revisionKey] as? String else { complete = false; continue }
                var revisions = [revision]
                if let key = descriptor.revisionOverridesKey, let value = artifact[key] {
                    guard let overrides = value as? [String: String] else { complete = false; continue }
                    revisions += overrides.values
                }
                if revisions.contains(where: { (descriptor.replaceNameHyphensWithUnderscores ? artifactName.replacingOccurrences(of: "-", with: "_") : artifactName) + "-" + $0 == name }) { return .referenced }
            }
        }
        return complete ? .unused : .unknown
    }

    private static func boundedData(_ url: URL) -> Data? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1_048_576 else { return nil }
        return try? Data(contentsOf: url)
    }
}
