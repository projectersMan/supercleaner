import Foundation
import Security

/// A missing declaration and an unreadable declaration are different results.
struct ApplicationGroupDeclarations: Sendable {
    let groups: [String]
    let complete: Bool
    var bundleIdentifiers: [String] = []
}

struct ApplicationGroupDeclarationScanner {
    private let readCode: (URL) -> ApplicationGroupDeclarations

    init(readCode: @escaping (URL) -> ApplicationGroupDeclarations = Self.signedDeclarations) {
        self.readCode = readCode
    }

    func scan(
        _ bundle: URL,
        deadline: Date? = nil,
        maximumEntries: Int = .max
    ) -> ApplicationGroupDeclarations {
        let root = bundle.resolvingSymlinksInPath().standardizedFileURL
        let main = readCode(root)
        var groups = Set(main.groups)
        var identifiers = Set(Bundle(url: root)?.bundleIdentifier.map { [$0] } ?? [])
        var complete = main.complete
        var inspectedEntries = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isExecutableKey]
        guard let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            errorHandler: { _, _ in complete = false; return true }) else {
            return .init(groups: groups.sorted(), complete: false)
        }
        for case let entry as URL in entries {
            guard !Task.isCancelled else { complete = false; break }
            guard inspectedEntries < maximumEntries,
                  deadline.map({ Date() < $0 }) ?? true else {
                complete = false
                break
            }
            inspectedEntries += 1
            guard let values = try? entry.resourceValues(forKeys: Set(keys)) else { complete = false; continue }
            if values.isSymbolicLink == true {
                // Internal framework links are reached by their physical path elsewhere.
                // External directory links may hide additional executable bundles.
                let target = entry.resolvingSymlinksInPath().standardizedFileURL
                var directory: ObjCBool = false
                if !target.path.hasPrefix(root.path + "/"),
                   FileManager.default.fileExists(atPath: target.path, isDirectory: &directory), directory.boolValue {
                    complete = false
                }
                entries.skipDescendants()
                continue
            }
            let extensionName = entry.pathExtension.lowercased()
            let isCodeBundle = values.isDirectory == true && (["app", "appex", "xpc"].contains(extensionName)
                || (extensionName == "bundle" && Bundle(url: entry)?.executableURL != nil))
            if isCodeBundle {
                if let identifier = Bundle(url: entry)?.bundleIdentifier { identifiers.insert(identifier) }
                else { complete = false }
            }
            var isCodeFile = false
            if values.isRegularFile == true, values.isExecutable == true {
                do {
                    let file = try FileHandle(forReadingFrom: entry)
                    defer { try? file.close() }
                    let magic = [UInt8](try file.read(upToCount: 4) ?? Data())
                    isCodeFile = [[0xfe, 0xed, 0xfa, 0xce], [0xce, 0xfa, 0xed, 0xfe],
                        [0xfe, 0xed, 0xfa, 0xcf], [0xcf, 0xfa, 0xed, 0xfe],
                        [0xca, 0xfe, 0xba, 0xbe], [0xbe, 0xba, 0xfe, 0xca],
                        [0xca, 0xfe, 0xba, 0xbf], [0xbf, 0xba, 0xfe, 0xca]].contains(magic)
                } catch { complete = false }
            }
            if isCodeBundle || isCodeFile {
                let declarations = readCode(entry)
                groups.formUnion(declarations.groups)
                complete = complete && declarations.complete
            }
        }
        return .init(groups: groups.sorted(), complete: complete, bundleIdentifiers: identifiers.sorted())
    }

    private static func signedDeclarations(_ url: URL) -> ApplicationGroupDeclarations {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(url as CFURL, [], &code)
        if created == errSecCSUnsigned { return .init(groups: [], complete: true) }
        guard created == errSecSuccess, let code else { return .init(groups: [], complete: false) }
        let validity = SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSBasicValidateOnly), nil)
        if validity == errSecCSUnsigned { return .init(groups: [], complete: true) }
        guard validity == errSecSuccess else { return .init(groups: [], complete: false) }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let facts = information as? [String: Any] else { return .init(groups: [], complete: false) }
        guard let rawEntitlements = facts[kSecCodeInfoEntitlementsDict as String] else { return .init(groups: [], complete: true) }
        guard let entitlements = rawEntitlements as? [String: Any] else { return .init(groups: [], complete: false) }
        guard let rawGroups = entitlements["com.apple.security.application-groups"] else { return .init(groups: [], complete: true) }
        guard let groups = rawGroups as? [String], groups.allSatisfy({ !$0.isEmpty }) else { return .init(groups: [], complete: false) }
        return .init(groups: groups.sorted(), complete: true)
    }
}
