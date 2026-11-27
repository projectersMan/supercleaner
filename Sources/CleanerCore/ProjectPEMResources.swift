import CryptoKit
import Foundation
import Security

/// Public certificates are not credentials. Unknown, mixed or malformed PEMs
/// remain protected; parsing a certificate never grants trust to its issuer.
enum ProjectPublicPEM {
    static let maximumBytes = 1_048_576

    static func containsOnlyPublicMaterial(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        if data.count <= 65_536 {
            let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            if lines.count >= 3, ["PUBLIC KEY", "RSA PUBLIC KEY"].contains(where: {
                lines.first == "-----BEGIN \($0)-----" && lines.last == "-----END \($0)-----"
            }), let payload = Data(base64Encoded: lines.dropFirst().dropLast().joined()), !payload.isEmpty { return true }
        }
        return containsOnlyCertificates(data, allowingDescriptions: false)
    }

    static func containsOnlyCertificates(_ data: Data, allowingDescriptions: Bool) -> Bool {
        guard data.count <= maximumBytes, let text = String(data: data, encoding: .utf8) else { return false }
        var payload = ""
        var insideCertificate = false
        var certificates = 0
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if insideCertificate {
                if line == "-----END CERTIFICATE-----" {
                    guard let der = Data(base64Encoded: payload), SecCertificateCreateWithData(nil, der as CFData) != nil else { return false }
                    certificates += 1
                    insideCertificate = false
                } else {
                    guard !line.contains("-----") else { return false }
                    payload.append(contentsOf: line)
                }
            } else if line == "-----BEGIN CERTIFICATE-----" {
                payload = ""
                insideCertificate = true
            } else if !line.isEmpty && !line.hasPrefix("#") {
                // OpenSSL's printed certificate descriptions are permitted only
                // when the entire file also matches its installed RECORD hash.
                guard allowingDescriptions, !line.contains("-----") else { return false }
            }
        }
        return certificates > 0 && !insideCertificate
    }
}

/// A scan-local index of unchanged, installed Python PEM resources. Only SSL
/// test fixtures may contain sample private keys; other package files must be
/// public certificate bundles. New/modified keys and all .env files stay blocked.
struct PythonEnvironmentPEMResources {
    let environment: URL?
    private struct Record: Equatable {
        let hash: String
        let bytes: UInt64
    }
    private var indexes = [String: [String: Record]]()

    init(environment: URL?) { self.environment = environment }

    mutating func contains(_ file: URL, data: Data, context: ScanContext) async throws -> Bool {
        guard let environment, file.path.hasPrefix(environment.path + "/") else { return false }
        var site = file.deletingLastPathComponent()
        while site.path.hasPrefix(environment.path + "/"), site.lastPathComponent != "site-packages" { site.deleteLastPathComponent() }
        guard site.lastPathComponent == "site-packages" else { return false }
        let layout = Array(site.pathComponents.dropFirst(environment.pathComponents.count))
        guard layout.count == 3, ["lib", "lib64"].contains(layout[0]), layout[1].hasPrefix("python3.") else { return false }
        let relative = String(file.path.dropFirst(site.path.count + 1))
        let components = relative.split(separator: "/")
        let testFixture = components.dropFirst().dropLast().contains { $0 == "test" || $0 == "tests" }
        guard testFixture || ProjectPublicPEM.containsOnlyCertificates(data, allowingDescriptions: true) else { return false }
        if indexes[site.path] == nil { indexes[site.path] = try await loadRecords(in: site, context: context) }
        guard let record = indexes[site.path]?[relative], record.bytes == UInt64(data.count) else { return false }
        let hash = Data(SHA256.hash(data: data)).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return record.hash == "sha256=" + hash
    }

    private func loadRecords(in site: URL, context: ScanContext) async throws -> [String: Record] {
        let fs = context.fileSystem
        guard let children = try? await fs.children(of: site) else { return [:] }
        var records = [String: Record]()
        var conflicts = Set<String>()
        for directory in children where directory.lastPathComponent.hasSuffix(".dist-info") {
            try Task.checkCancellation()
            let url = directory.appendingPathComponent("RECORD")
            guard (try? await fs.identity(at: directory))?.kind == .directory,
                  (try? await fs.identity(at: url))?.kind == .file else { continue }
            do {
                let path = try context.pathPolicy.validateCandidate(url)
                guard path.literal.path == path.physical.path else { continue }
                try context.protectionPolicy.validate(url)
                let data = try await fs.readData(at: url, maximumBytes: 4_194_304)
                guard let text = String(data: data, encoding: .utf8) else { continue }
                for line in text.split(whereSeparator: \.isNewline) {
                    // Quoted/ambiguous CSV paths fail closed. Their resources
                    // receive the ordinary PEM checks rather than an exception.
                    let fields = line.split(separator: ",", omittingEmptySubsequences: false)
                    guard fields.count == 3, !fields[0].contains("\""), fields[0].hasSuffix(".pem"),
                          fields[1].hasPrefix("sha256="), let bytes = UInt64(fields[2]), bytes <= UInt64(ProjectPublicPEM.maximumBytes) else { continue }
                    let key = String(fields[0])
                    let record = Record(hash: String(fields[1]), bytes: bytes)
                    if let existing = records[key], existing != record { conflicts.insert(key) }
                    records[key] = record
                }
            } catch is CancellationError { throw CancellationError() }
            catch { continue }
        }
        for key in conflicts { records.removeValue(forKey: key) }
        return records
    }
}
