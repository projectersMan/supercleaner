import Darwin
import Foundation

/// One directory catalogue for discovery, ownership revalidation and runtime
/// hints. A root is a search boundary, never a deletion candidate itself.
public struct ApplicationAssociationRoot: Sendable {
    public enum Matching: Sendable {
        case standard, exactIdentifier, byHostPreference, cookie, diagnostic
    }
    public let url: URL
    public let kind: ApplicationAssociation.Kind
    public let containsUserData: Bool
    public let isSystem: Bool
    public let matching: Matching
    public let removalPolicy: ApplicationAssociation.RemovalPolicy

    public init(url: URL, kind: ApplicationAssociation.Kind, containsUserData: Bool = false,
                isSystem: Bool = false, matching: Matching = .standard,
                removalPolicy: ApplicationAssociation.RemovalPolicy = .recoverable) {
        self.url = url.standardizedFileURL; self.kind = kind
        self.containsUserData = containsUserData; self.isSystem = isSystem
        self.matching = matching; self.removalPolicy = removalPolicy
    }

    static func standard(home: URL) -> [Self] { ApplicationAssociationPathRegistry.roots(home: home) }

    func ownership(of child: URL, application: InstalledApplication) -> ApplicationAssociation.OwnershipBasis? {
        let raw = child.lastPathComponent
        guard !raw.hasPrefix("."), !application.bundleIdentifier.isEmpty else { return nil }
        let name = raw.lowercased()
        // Chrome app shims have their own identities and may survive removal of
        // the browser. The browser's identifier prefix is not ownership of them.
        if kind == .cache, application.bundleIdentifier.lowercased() == "com.google.chrome",
           name.hasPrefix("com.google.chrome.app.") { return nil }
        let identifiers = [application.bundleIdentifier] + (application.associatedBundleIdentifiers ?? [])
        for rawIdentifier in identifiers where !rawIdentifier.isEmpty {
            let identifier = rawIdentifier.lowercased()
            switch matching {
            case .diagnostic: return nil // Individual files use the diagnostic parser.
            case .exactIdentifier:
                if name == identifier { return .bundleIdentifier }
                if (application.applicationGroups ?? []).contains(raw) { return .applicationGroup }
                continue
            case .byHostPreference:
                guard name.hasPrefix(identifier + "."), name.hasSuffix(".plist") else { continue }
                let suffix = String(raw.dropFirst(rawIdentifier.count + 1).dropLast(6))
                if UUID(uuidString: suffix) != nil { return .bundleIdentifier }
            case .cookie:
                if [identifier, identifier + ".binarycookies", identifier + ".cookies"].contains(name) { return .bundleIdentifier }
            case .standard:
                var stem = name
                let suffixes: [String]
                switch kind {
                case .preference, .launchAgent, .launchDaemon: suffixes = [".plist"]
                case .installationReceipt: suffixes = [".plist", ".bom"]
                case .savedState: suffixes = [".savedstate"]
                case .plugin, .searchIndex:
                    suffixes = [".app", ".qlgenerator", ".prefpane", ".service", ".plugin", ".bundle", ".saver", ".component", ".vst", ".vst3", ".mdimporter", ".osax"]
                default: suffixes = []
                }
                for suffix in suffixes where stem.hasSuffix(suffix) {
                    stem.removeLast(suffix.count)
                    break
                }
                if kind == .preference,
                   ApplicationAssociationPathRegistry.preferenceClues(for: application.bundleIdentifier).contains(where: { $0.lowercased() == stem }),
                   !(application.associatedBundleIdentifiers ?? []).contains(where: { $0.lowercased() == stem }) {
                    return .compatibilityHint
                }
                if stem == identifier || stem.hasPrefix(identifier + ".") { return .bundleIdentifier }
                if kind == .sharedContainer {
                    if (application.applicationGroups ?? []).contains(raw) { return .applicationGroup }
                    // A group-looking name without a declaration is only a clue.
                    if stem == "group." + identifier || stem.hasPrefix("group." + identifier + ".") { return .displayName }
                }
                var aliases = [application.name, application.bundleURL.deletingPathExtension().lastPathComponent]
                    .map { $0.lowercased() }.filter { !$0.isEmpty }
                let vendor = child.deletingLastPathComponent().lastPathComponent.lowercased()
                let parts = application.bundleIdentifier.lowercased().split(separator: ".")
                if parts.count > 2, vendor == String(parts[1]), supportsVendorChildren {
                    aliases += aliases.filter { $0.hasPrefix(vendor + " ") }.map { String($0.dropFirst(vendor.count + 1)) }
                }
                if aliases.contains(stem) { return .displayName }
            }
        }
        if kind == .preference, matching == .standard,
           ApplicationAssociationPathRegistry.preferenceClues(for: application.bundleIdentifier)
            .contains(where: { name == $0.lowercased() + ".plist" }) { return .compatibilityHint }
        return nil
    }

    var supportsVendorChildren: Bool { [.applicationSupport, .cache, .log, .webData].contains(kind) }

    func isVendorDirectory(_ child: URL, for applications: [InstalledApplication]) -> Bool {
        guard supportsVendorChildren else { return false }
        let vendor = child.lastPathComponent.lowercased()
        let known = ["google", "microsoft", "jetbrains", "adobe", "apple", "logitech", "objective development", "better365"]
        return known.contains(vendor) || applications.contains {
            let parts = $0.bundleIdentifier.lowercased().split(separator: ".")
            let productNames = [$0.name.lowercased(), $0.bundleURL.deletingPathExtension().lastPathComponent.lowercased()]
            return parts.count > 2 && String(parts[1]) == vendor && !productNames.contains(vendor)
        }
    }
}

public enum ApplicationAssociationPathRegistry {
    /// Legacy product relationships recovered from XApp's configuration are
    /// discovery clues. Only independently validated bundle metadata can make a
    /// non-primary identifier removable; a compatibility table cannot do that.
    static func preferenceClues(for identifier: String) -> [String] {
        switch identifier.lowercased() {
        case "com.logi.optionsplus":
            return ["com.logi.optionsplus.driverhost", "com.logi.optionsplus.logivoice", "com.logi.cp-dev-mgr"]
        case "com.bjango.istatmenus":
            return ["com.bjango.istatmenus.agent", "com.bjango.istatmenus.menubar.7", "com.bjango.istatmenus.status", "com.bjango.istatmenus6.extras"]
        default: return []
        }
    }

    public static func roots(home: URL, userTemporaryDirectories: [URL]? = nil) -> [ApplicationAssociationRoot] {
        typealias Kind = ApplicationAssociation.Kind
        var result: [ApplicationAssociationRoot] = []
        func library(_ leaf: String, _ kind: Kind, data: Bool = false, system: Bool = false,
                     matching: ApplicationAssociationRoot.Matching = .standard,
                     removal: ApplicationAssociation.RemovalPolicy = .recoverable) {
            let base = system ? URL(fileURLWithPath: "/Library") : home.appendingPathComponent("Library")
            result.append(.init(url: base.appendingPathComponent(leaf), kind: kind,
                containsUserData: data, isSystem: system, matching: matching, removalPolicy: system ? .referenceOnly : removal))
        }
        for system in [false, true] {
            library("Application Support", .applicationSupport, data: true, system: system)
            library("Caches", .cache, system: system)
            library("Preferences", .preference, system: system)
            library("Preferences/ByHost", .preference, system: system, matching: .byHostPreference)
            library("Logs", .log, system: system)
            library("LaunchAgents", .launchAgent, system: system, removal: .referenceOnly)
            library("LaunchDaemons", .launchDaemon, system: system, removal: .referenceOnly)
            // Plug-ins can be registered or loaded by a different host process.
            // Discovery must not imply that deleting their directory unregisters it.
            for leaf in ["QuickLook", "PreferencePanes", "Services", "Internet Plug-Ins", "Input Methods",
                         "ScriptingAdditions", "Screen Savers", "Audio/Plug-Ins/Components",
                         "Audio/Plug-Ins/VST", "Audio/Plug-Ins/VST3", "Audio/Plug-Ins/HAL"] {
                library(leaf, .plugin, data: true, system: system, removal: .referenceOnly)
            }
            library("Spotlight", .searchIndex, system: system, removal: .referenceOnly)
        }
        library("Saved Application State", .savedState)
        library("Containers", .container, data: true, matching: .exactIdentifier)
        library("Group Containers", .sharedContainer, data: true)
        library("Application Scripts", .applicationScripts, data: true, matching: .exactIdentifier)
        library("Cookies", .cookies, data: true, matching: .cookie)
        library("HTTPStorages", .webData, data: true)
        library("WebKit", .webData, data: true)
        library("Autosave Information", .applicationSupport, data: true)
        library("Scripts", .plugin, data: true, removal: .referenceOnly)
        library("StartupItems", .launchDaemon, removal: .referenceOnly)
        library("StartupItems", .launchDaemon, system: true, removal: .referenceOnly)
        library("PrivilegedHelperTools", .privilegedHelper, system: true, removal: .referenceOnly)
        library("Receipts", .installationReceipt, system: true, removal: .referenceOnly)
        result.append(.init(url: URL(fileURLWithPath: "/private/var/db/receipts"), kind: .installationReceipt,
            isSystem: true, removalPolicy: .referenceOnly))
        result.append(.init(url: URL(fileURLWithPath: "/Applications/Utilities"), kind: .plugin,
            isSystem: true, removalPolicy: .referenceOnly))
        result += diagnosticRoots(home: home)
        let temporary = userTemporaryDirectories ?? currentUserTemporaryDirectories(home: home)
        let current = currentUserTemporaryDirectories(home: home)
        for url in temporary where validTemporaryRoot(url, home: home, current: current) {
            result.append(.init(url: url, kind: .temporary, matching: .exactIdentifier))
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.url.path).inserted }
    }

    public static func diagnosticRoots(home: URL) -> [ApplicationAssociationRoot] {
        [false, true].flatMap { system in
            ["Application Support/CrashReporter", "Logs/DiagnosticReports", "Logs/CrashReporter"].map { leaf in
                let base = system ? URL(fileURLWithPath: "/Library") : home.appendingPathComponent("Library")
                return .init(url: base.appendingPathComponent(leaf), kind: .diagnosticReport,
                    isSystem: system, matching: .diagnostic, removalPolicy: system ? .referenceOnly : .recoverable)
            }
        }
    }

    /// confstr resolves the current user's real directories. Never search every
    /// user's /var/folders or use arbitrary TMPDIR environment contents.
    public static func currentUserTemporaryDirectories(home: URL) -> [URL] {
        guard home.resolvingSymlinksInPath().standardizedFileURL == FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL else { return [] }
        return [_CS_DARWIN_USER_CACHE_DIR, _CS_DARWIN_USER_TEMP_DIR].compactMap { name in
            let count = confstr(name, nil, 0)
            guard count > 1, count <= 16_384 else { return nil }
            var buffer = [CChar](repeating: 0, count: count)
            guard confstr(name, &buffer, count) == count else { return nil }
            let path = String(decoding: buffer.prefix(count - 1).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
            guard (url.path.hasPrefix("/private/var/folders/") || url.path.hasPrefix("/var/folders/")),
                  ["C", "T"].contains(url.lastPathComponent),
                  let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
                  (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { return nil }
            return url
        }
    }

    private static func validTemporaryRoot(_ url: URL, home: URL, current: [URL]) -> Bool {
        guard url.isFileURL, !url.pathComponents.contains(".."), !url.path.contains("\n"),
              url.standardizedFileURL.path != home.standardizedFileURL.path else { return false }
        return current.contains(url.standardizedFileURL)
            || url.standardizedFileURL.path.hasPrefix(home.standardizedFileURL.path + "/")
    }
}
