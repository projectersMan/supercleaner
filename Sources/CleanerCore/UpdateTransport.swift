import CryptoKit
import Darwin
import Foundation

public enum UpdateDownloadError: Error, LocalizedError, Sendable, Equatable {
    case disallowedURL, responseRejected, sizeLimit, redirectLimit, timedOut, failed, outputExists
    public var errorDescription: String? {
        switch self {
        case .disallowedURL: L10n.text("更新地址不在已配置的 HTTPS 来源内")
        case .responseRejected: L10n.text("更新源返回无效状态或内容长度")
        case .sizeLimit: L10n.text("更新下载超过大小限制")
        case .redirectLimit: L10n.text("更新源重定向超过限制")
        case .timedOut: L10n.text("更新下载超时")
        case .failed: L10n.text("更新下载失败，当前版本保持不变")
        case .outputExists: L10n.text("更新暂存目标已存在或不是安全的新文件")
        }
    }
}

public struct UpdateDownloadPolicy: Sendable {
    public let allowedHosts: Set<String>
    public let maximumBytes: Int64
    public let timeout: TimeInterval
    public let maximumRedirects: Int
    public init(allowedHosts: Set<String>, maximumBytes: Int64, timeout: TimeInterval = 60, maximumRedirects: Int = 3) {
        self.allowedHosts = Set(allowedHosts.map { $0.lowercased() })
        self.maximumBytes = max(1, min(maximumBytes, 536_870_912)); self.timeout = max(0.05, min(timeout, 300))
        self.maximumRedirects = max(0, min(maximumRedirects, 3))
    }
    public func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), allowedHosts.contains(host),
              Self.validHost(host),
              url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.fragment == nil,
              !url.absoluteString.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw UpdateDownloadError.disallowedURL }
    }
    public func validateRedirect(_ url: URL, count: Int) throws {
        guard count > 0, count <= maximumRedirects else { throw UpdateDownloadError.redirectLimit }
        try validate(url)
    }
    public static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.count <= 253, host == host.lowercased() else { return false }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

public struct DownloadedUpdate: Sendable {
    public let fileURL: URL
    public let sourceURL: URL
    public let byteCount: Int64
    public let sha256: String
    public init(fileURL: URL, sourceURL: URL, byteCount: Int64, sha256: String) {
        self.fileURL = fileURL; self.sourceURL = sourceURL; self.byteCount = byteCount; self.sha256 = sha256
    }
}

public protocol UpdateTransport: Sendable {
    func download(from url: URL, to destination: URL, policy: UpdateDownloadPolicy, progress: @escaping @Sendable (Int64, Int64?) -> Void) async throws -> DownloadedUpdate
}

/// Streaming, ephemeral HTTPS with system TLS validation. Redirects are checked
/// before following; output is exclusive, bounded, synchronized and discarded
/// on failure. No cookies, credentials, persistent cache or trust override.
public struct HTTPSUpdateTransport: UpdateTransport {
    private let configuration: @Sendable () -> URLSessionConfiguration
    public init(configuration: @escaping @Sendable () -> URLSessionConfiguration = { .ephemeral }) { self.configuration = configuration }
    public func download(from url: URL, to destination: URL, policy: UpdateDownloadPolicy, progress: @escaping @Sendable (Int64, Int64?) -> Void = { _, _ in }) async throws -> DownloadedUpdate {
        try Task.checkCancellation()
        try policy.validate(url)
        let operation = try StreamingUpdateDownload(url: url, destination: destination, policy: policy, configuration: configuration(), progress: progress)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { operation.start($0) }
        } onCancel: { operation.finish(.failure(CancellationError())) }
    }
}

private final class StreamingUpdateDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let url: URL
    private let destination: URL
    private let policy: UpdateDownloadPolicy
    private let configuration: URLSessionConfiguration
    private let progress: @Sendable (Int64, Int64?) -> Void
    private let handle: FileHandle
    private let inode: UInt64
    private let device: Int32
    private var session: URLSession?
    private var continuation: CheckedContinuation<DownloadedUpdate, any Error>?
    private var outcome: Result<DownloadedUpdate, any Error>?
    private var byteCount: Int64 = 0
    private var expectedBytes: Int64?
    private var redirects = 0
    private var responseAccepted = false
    private var sourceURL: URL
    private var digest = SHA256()

    init(url: URL, destination: URL, policy: UpdateDownloadPolicy, configuration: URLSessionConfiguration, progress: @escaping @Sendable (Int64, Int64?) -> Void) throws {
        guard destination.isFileURL else { throw UpdateDownloadError.outputExists }
        let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw UpdateDownloadError.outputExists }
        var facts = stat()
        guard fstat(fd, &facts) == 0 else { close(fd); throw UpdateDownloadError.failed }
        self.url = url; self.sourceURL = url; self.destination = destination; self.policy = policy; self.configuration = configuration; self.progress = progress
        handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true); inode = UInt64(facts.st_ino); device = facts.st_dev
    }
    func start(_ continuation: CheckedContinuation<DownloadedUpdate, any Error>) {
        lock.lock()
        if let outcome { lock.unlock(); continuation.resume(with: outcome); return }
        self.continuation = continuation
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
        configuration.httpAdditionalHeaders = nil
        configuration.httpShouldSetCookies = false; configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = min(15, policy.timeout); configuration.timeoutIntervalForResource = policy.timeout
        configuration.waitsForConnectivity = false
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let task = session.dataTask(with: request)
        lock.unlock()
        task.resume()
        DispatchQueue.global().asyncAfter(deadline: .now() + policy.timeout) { self.finish(.failure(UpdateDownloadError.timedOut)) }
    }
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        do {
            try lock.withLock {
                redirects += 1
                guard let target = request.url else { throw UpdateDownloadError.disallowedURL }
                try policy.validateRedirect(target, count: redirects)
            }
            var sanitized = URLRequest(url: request.url!); sanitized.httpMethod = "GET"
            sanitized.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            completionHandler(sanitized)
        } catch { finish(.failure(error)); completionHandler(nil) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
        do {
            try lock.withLock {
                guard outcome == nil, let http = response as? HTTPURLResponse, http.statusCode == 200, let finalURL = http.url else { throw UpdateDownloadError.responseRejected }
                try policy.validate(finalURL)
                if http.expectedContentLength >= 0 {
                    guard http.expectedContentLength <= policy.maximumBytes else { throw UpdateDownloadError.sizeLimit }
                    expectedBytes = http.expectedContentLength
                }
                sourceURL = finalURL; responseAccepted = true
            }
            completionHandler(.allow)
        } catch { finish(.failure(error)); completionHandler(.cancel) }
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            let state = try lock.withLock { () -> (Int64, Int64?)? in
                guard outcome == nil else { return nil }
                guard responseAccepted, Int64(data.count) <= policy.maximumBytes - byteCount else { throw UpdateDownloadError.sizeLimit }
                try handle.write(contentsOf: data); digest.update(data: data); byteCount += Int64(data.count)
                return (byteCount, expectedBytes)
            }
            if let state { progress(state.0, state.1) }
        } catch { finish(.failure(error)) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if error != nil { finish(.failure(UpdateDownloadError.failed)); return }
        do {
            let completed = try lock.withLock { () -> DownloadedUpdate? in
                guard outcome == nil else { return nil }
                guard responseAccepted, byteCount > 0, expectedBytes == nil || expectedBytes == byteCount else { throw UpdateDownloadError.responseRejected }
                try handle.synchronize()
                return DownloadedUpdate(fileURL: destination, sourceURL: sourceURL, byteCount: byteCount,
                    sha256: digest.finalize().map { String(format: "%02x", $0) }.joined())
            }
            if let completed { finish(.success(completed)) }
        } catch { finish(.failure(error)) }
    }
    func finish(_ result: Result<DownloadedUpdate, any Error>) {
        let completion = lock.withLock { () -> (CheckedContinuation<DownloadedUpdate, any Error>?, URLSession?)? in
            guard outcome == nil else { return nil }
            outcome = result
            try? handle.close()
            if case .failure = result {
                var facts = stat()
                if lstat(destination.path, &facts) == 0, UInt64(facts.st_ino) == inode, facts.st_dev == device, facts.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) { _ = unlink(destination.path) }
            }
            let pending = continuation; continuation = nil
            let oldSession = session; session = nil
            return (pending, oldSession)
        }
        guard let completion else { return }
        completion.1?.invalidateAndCancel()
        completion.0?.resume(with: result)
    }
}
