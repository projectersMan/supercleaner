import CleanerCore
import CryptoKit
import Foundation

private struct UpdateProtocolReply: Sendable {
    var status = 200
    var data = Data("fixture update".utf8)
    var length: Int?
    var delay: TimeInterval = 0
    var redirect: URL?
}

private final class UpdateFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var routes: [String: UpdateProtocolReply] = [:]
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    private let stopLock = NSLock()
    private var stopped = false
    static func configure(_ values: [String: UpdateProtocolReply]) { stateLock.withLock { routes = values; requests = [] } }
    static func recordedRequests() -> [URLRequest] { stateLock.withLock { requests } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.stateLock.withLock { () -> UpdateProtocolReply in
            Self.requests.append(request)
            return Self.routes[request.url?.path ?? ""] ?? UpdateProtocolReply(status: 404)
        }
        let deliver: @Sendable () -> Void = { [self] in
            guard !stopLock.withLock({ stopped }), let url = request.url else { return }
            if let redirect = reply.redirect {
                let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": redirect.absoluteString])!
                client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: redirect), redirectResponse: response)
                return
            }
            var headers = ["Set-Cookie": "must-not-persist=1"]
            if let length = reply.length { headers["Content-Length"] = String(length) }
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            for offset in stride(from: 0, to: reply.data.count, by: 7) {
                if stopLock.withLock({ stopped }) { return }
                client?.urlProtocol(self, didLoad: reply.data.subdata(in: offset..<min(offset + 7, reply.data.count)))
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver) }
        else { deliver() }
    }
    override func stopLoading() { stopLock.withLock { stopped = true } }
}

func runUpdateTransportContracts() async throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent("update-transport-" + UUID().uuidString)
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let transport = HTTPSUpdateTransport(configuration: {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateFixtureProtocol.self]
        configuration.httpAdditionalHeaders = ["Authorization": "must-not-send"]
        return configuration
    })
    let host = "updates.fixture.test"
    let url = URL(string: "https://\(host)/ok")!
    let policy = UpdateDownloadPolicy(allowedHosts: [host], maximumBytes: 64, timeout: 3)
    let payload = Data("fixture update".utf8)
    UpdateFixtureProtocol.configure(["/ok": .init(data: payload, length: payload.count)])
    let output = directory.appendingPathComponent("ok")
    let result = try await transport.download(from: url, to: output, policy: policy)
    let disk = try Data(contentsOf: output)
    let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    require(result.byteCount == Int64(payload.count) && disk == payload && result.sha256 == hash, "HTTPS delegate must stream actual bytes and SHA256 to an exclusive file")
    let requests = UpdateFixtureProtocol.recordedRequests()
    require(!requests.isEmpty && requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil && $0.value(forHTTPHeaderField: "Cookie") == nil }, "network updates must not transmit credentials or persistent cookies")
    do { _ = try await transport.download(from: url, to: output, policy: policy); require(false, "existing download output was overwritten") } catch UpdateDownloadError.outputExists { }
    let preserved = try Data(contentsOf: output)
    require(preserved == payload, "exclusive-output failure must preserve preexisting contents")
    for invalid in ["http://\(host)/ok", "https://other.test/ok", "https://\(host):8443/ok", "https://user:password@\(host)/ok", "https://\(host)/ok#fragment", "file:///etc/passwd"] {
        let rejected = directory.appendingPathComponent(UUID().uuidString)
        do { _ = try await transport.download(from: URL(string: invalid)!, to: rejected, policy: policy); require(false, "disallowed update URL accepted") } catch UpdateDownloadError.disallowedURL { }
        require(!manager.fileExists(atPath: rejected.path), "URL rejection must happen before creating an output")
    }
    for (path, reply) in [
        ("/status", UpdateProtocolReply(status: 500)),
        ("/header-limit", UpdateProtocolReply(data: Data([1]), length: 1_000)),
        ("/stream-limit", UpdateProtocolReply(data: Data(repeating: 1, count: 65))),
        ("/truncated", UpdateProtocolReply(data: Data([1]), length: 32)),
    ] {
        UpdateFixtureProtocol.configure([path: reply])
        let rejected = directory.appendingPathComponent(UUID().uuidString)
        do { _ = try await transport.download(from: URL(string: "https://\(host)\(path)")!, to: rejected, policy: policy); require(false, "invalid HTTP/body response accepted: \(path)") } catch is UpdateDownloadError { }
        require(!manager.fileExists(atPath: rejected.path), "failed HTTP download must discard only its partial file")
    }
    let redirect = URL(string: "https://\(host)/redirect")!
    UpdateFixtureProtocol.configure(["/redirect": .init(redirect: url), "/ok": .init(data: payload)])
    let redirected = try await transport.download(from: redirect, to: directory.appendingPathComponent("redirected"), policy: policy)
    require(redirected.sourceURL.path == "/ok", "native URLSession delegate must follow validated redirects")
    for target in [URL(string: "http://\(host)/evil")!, URL(string: "https://other.test/evil")!] {
        UpdateFixtureProtocol.configure(["/redirect": .init(redirect: target), "/evil": .init()])
        let rejected = directory.appendingPathComponent(UUID().uuidString)
        do { _ = try await transport.download(from: redirect, to: rejected, policy: policy); require(false, "redirect escaped source policy") } catch is UpdateDownloadError { }
        require(!UpdateFixtureProtocol.recordedRequests().contains { $0.url?.path == "/evil" }, "disallowed redirect must be rejected before contacting target")
        require(!manager.fileExists(atPath: rejected.path), "redirect failure must remove partial download")
    }
    UpdateFixtureProtocol.configure(["/redirect": .init(redirect: redirect)])
    do { _ = try await transport.download(from: redirect, to: directory.appendingPathComponent("loop"), policy: policy); require(false, "redirect loop was unlimited") } catch is UpdateDownloadError { }
    require(UpdateFixtureProtocol.recordedRequests().count <= 4, "redirect budget must bound actual outgoing requests")
    UpdateFixtureProtocol.configure(["/slow": .init(delay: 4)])
    let slow = URL(string: "https://\(host)/slow")!
    let cancelledURL = directory.appendingPathComponent("cancelled")
    let task = Task { try await transport.download(from: slow, to: cancelledURL, policy: policy) }
    try await Task.sleep(for: .milliseconds(50)); task.cancel()
    do { _ = try await task.value; require(false, "cancelled streaming update completed") } catch is CancellationError { }
    require(!manager.fileExists(atPath: cancelledURL.path), "cancel must close and discard partial file")
    let timedOutURL = directory.appendingPathComponent("timeout")
    do { _ = try await transport.download(from: slow, to: timedOutURL, policy: .init(allowedHosts: [host], maximumBytes: 64, timeout: 0.05)); require(false, "resource deadline ignored") } catch is UpdateDownloadError { }
    require(!manager.fileExists(atPath: timedOutURL.path), "deadline must discard partial file without changing successful output")
    print("PASS: streaming HTTPS, credential isolation, real delegate redirects, limits, cancellation and exclusive output")
}
