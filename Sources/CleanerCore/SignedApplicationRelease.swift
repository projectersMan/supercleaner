import CryptoKit
import Darwin
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Offline public-key release gate for Sparkle's published XML wire format.
/// It does not install anything or access a private key / Keychain.
public enum SignedApplicationRelease {
    public static func validate(appcast: URL, archive: URL, configuration: ReleaseConfiguration,
                                expectedBuild: String, minimumOS: String) throws -> String {
        try configuration.validate(requireComplete: true)
        guard let publicKey = configuration.applicationPublicKey else { throw ReleaseConfigurationError.missing }
        let key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        let data = try UpdateFileContent.read(appcast, maximumBytes: 2_097_152)
        let marker = Data("<!-- sparkle-signatures:\n".utf8)
        guard let boundary = data.range(of: marker),
              data.range(of: marker, in: boundary.upperBound..<data.endIndex) == nil,
              let block = String(data: data[boundary.upperBound...], encoding: .utf8),
              block.hasSuffix("-->\n") else { throw ApplicationUpdateError.untrustedFeed }
        let content = Data(data[..<boundary.lowerBound])
        let lines = block.dropLast(4).split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count == 2, lines[0].hasPrefix("edSignature: "), lines[1].hasPrefix("length: "),
              let signature = Data(base64Encoded: String(lines[0].dropFirst(13))), signature.count == 64,
              String(lines[1].dropFirst(8)) == String(content.count), key.isValidSignature(signature, for: content),
              let xml = String(data: content, encoding: .utf8), !xml.localizedCaseInsensitiveContains("<!DOCTYPE"),
              !xml.localizedCaseInsensitiveContains("<!ENTITY") else { throw ApplicationUpdateError.untrustedFeed }
        let delegate = ReleaseAppcastParser()
        let parser = XMLParser(data: content)
        parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse(), delegate.isValid, delegate.version == expectedBuild,
              delegate.minimumOS == minimumOS, let url = URL(string: delegate.archiveURL),
              url.lastPathComponent == archive.lastPathComponent,
              let archiveSignature = Data(base64Encoded: delegate.signature), archiveSignature.count == 64,
              let length = UInt64(delegate.length) else { throw ApplicationUpdateError.invalidArchive }
        _ = try ApplicationUpdatePolicy.buildNumber(expectedBuild)
        try ApplicationUpdatePolicy(configuration: configuration).validateArchive(
            archiveURL: url, length: length, installationType: delegate.installationType)
        return try withMappedArchive(archive, expectedLength: length) { bytes in
            guard key.isValidSignature(archiveSignature, for: bytes) else { throw ApplicationUpdateError.invalidArchive }
            return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func withMappedArchive<T>(_ url: URL, expectedLength: UInt64, body: (Data) throws -> T) throws -> T {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ApplicationUpdateError.invalidArchive }
        defer { close(fd) }
        var before = stat()
        guard fstat(fd, &before) == 0, before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              before.st_size > 0, before.st_size <= 536_870_912, UInt64(before.st_size) == expectedLength,
              let pointer = mmap(nil, Int(before.st_size), PROT_READ, MAP_PRIVATE, fd, 0), pointer != MAP_FAILED else { throw ApplicationUpdateError.invalidArchive }
        defer { munmap(pointer, Int(before.st_size)) }
        let value = try body(Data(bytesNoCopy: pointer, count: Int(before.st_size), deallocator: .none))
        var after = stat(); var entry = stat()
        guard fstat(fd, &after) == 0, lstat(url.path, &entry) == 0,
              before.st_dev == entry.st_dev, before.st_ino == entry.st_ino,
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec, before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec else { throw ApplicationUpdateError.invalidArchive }
        return value
    }
}

private final class ReleaseAppcastParser: NSObject, XMLParserDelegate {
    private var stack: [String] = []
    private var itemCount = 0, enclosureCount = 0, versionCount = 0, osCount = 0
    private var text = ""
    private var failed = false
    var version = "", minimumOS = "", archiveURL = "", signature = "", length = "", installationType = "application"
    var isValid: Bool { !failed && stack.isEmpty && itemCount == 1 && enclosureCount == 1 && versionCount == 1 && osCount == 1 }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(name); text = ""
        if stack.count > 16 { failed = true; parser.abortParsing() }
        if stack.count == 1, name != "rss" || attributes["xmlns:sparkle"] != "http://www.andymatuschak.org/xml-namespaces/sparkle" { failed = true }
        if name == "item" { itemCount += 1; if stack != ["rss", "channel", "item"] { failed = true } }
        if name == "sparkle:version" { versionCount += 1 }
        if name == "sparkle:minimumSystemVersion" { osCount += 1 }
        if name == "enclosure" {
            enclosureCount += 1
            if stack != ["rss", "channel", "item", "enclosure"] { failed = true }
            archiveURL = attributes["url"] ?? ""; signature = attributes["sparkle:edSignature"] ?? ""
            length = attributes["length"] ?? ""; installationType = attributes["sparkle:installationType"] ?? "application"
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "sparkle:version" || name == "sparkle:minimumSystemVersion" {
            if stack != ["rss", "channel", "item", name] { failed = true }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if name == "sparkle:version" { version = value } else { minimumOS = value }
        }
        stack.removeLast(); text = ""
    }
}
