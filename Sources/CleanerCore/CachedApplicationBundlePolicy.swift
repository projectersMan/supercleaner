import Foundation
import Security

/// Sealed program resources in an owned update cache are not live app data.
enum CachedApplicationBundlePolicy {
    static func verifies(_ bundle: URL, owner: InstalledApplication) -> Bool {
        guard bundle.pathExtension.lowercased() == "app",
              Bundle(url: bundle)?.bundleIdentifier == owner.bundleIdentifier else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue:
                kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode), nil) == errSecSuccess else { return false }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let facts = information as? [String: Any],
              facts[kSecCodeInfoIdentifier as String] as? String == owner.bundleIdentifier else { return false }
        if let team = owner.teamIdentifier {
            return facts[kSecCodeInfoTeamIdentifier as String] as? String == team
        }
        return true
    }
}
