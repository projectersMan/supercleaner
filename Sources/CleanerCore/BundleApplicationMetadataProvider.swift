import Foundation
import Security

public protocol ApplicationMetadataProviding: Sendable {
    func metadata(for bundleURL: URL) -> ApplicationBundleMetadata?
}

public struct BundleApplicationMetadataProvider: ApplicationMetadataProviding {
    private let includeSharedDeclarations: Bool
    public init(includeSharedDeclarations: Bool = false) { self.includeSharedDeclarations = includeSharedDeclarations }

    public func metadata(for bundleURL: URL) -> ApplicationBundleMetadata? {
        guard let bundle = Bundle(url: bundleURL), let identifier = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)
        var code: SecStaticCode?
        var signing: CFDictionary?
        var team: String?
        var groups: [String]?
        if SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &code) == errSecSuccess, let code,
           SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), nil) == errSecSuccess,
           SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess,
           let facts = signing as? [String: Any] {
            team = facts[kSecCodeInfoTeamIdentifier as String] as? String
            let entitlements = facts[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
            groups = (entitlements?["com.apple.security.application-groups"] as? [String])?.sorted()
        }
        let sharedDeclarations = includeSharedDeclarations ? ApplicationGroupDeclarationScanner().scan(bundleURL)
            : ApplicationGroupDeclarations(groups: groups ?? [], complete: false)
        groups = sharedDeclarations.groups
        return ApplicationBundleMetadata(bundleIdentifier: identifier, name: name, version: version, teamIdentifier: team, applicationGroups: groups,
            associatedBundleIdentifiers: Array(Set(embeddedIdentifiers(in: bundleURL, identifier: identifier, team: team)
                + sharedDeclarations.bundleIdentifiers.filter { $0 != identifier })).sorted(),
            applicationGroupsComplete: sharedDeclarations.complete)
    }

    private func embeddedIdentifiers(in bundleURL: URL, identifier: String, team: String?) -> [String] {
        let manager = FileManager.default
        var found = Set<String>(), entries = 0
        var queue: [(URL, Int)] = ["XPCServices", "PlugIns", "Extensions", "Helpers", "Applications", "Library/LoginItems", "Library/LaunchServices", "Library/SystemExtensions"].map {
            (bundleURL.appendingPathComponent("Contents/" + $0), 0)
        }
        while !queue.isEmpty, entries < 512 {
            let (root, depth) = queue.removeFirst()
            guard root.resolvingSymlinksInPath().path == root.standardizedFileURL.path,
                  let children = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles) else { continue }
            for child in children.sorted(by: { $0.path < $1.path }) {
                entries += 1
                guard entries <= 512, let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true, values.isSymbolicLink != true,
                      child.resolvingSymlinksInPath().path == child.standardizedFileURL.path else { continue }
                if ["app", "xpc", "appex", "bundle"].contains(child.pathExtension.lowercased()),
                   let bundle = Bundle(url: child), let childID = bundle.bundleIdentifier, childID != identifier {
                    var sameTeam = false
                    if let team {
                        var code: SecStaticCode?, info: CFDictionary?
                        if SecStaticCodeCreateWithPath(child as CFURL, [], &code) == errSecSuccess, let code,
                           SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), nil) == errSecSuccess,
                           SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
                           let facts = info as? [String: Any] { sameTeam = facts[kSecCodeInfoTeamIdentifier as String] as? String == team }
                    }
                    if childID.hasPrefix(identifier + ".") || sameTeam { found.insert(childID) }
                }
                if child.pathExtension.lowercased() != "framework" { queue.append((child, depth + 1)) }
            }
        }
        return found.sorted()
    }
}
