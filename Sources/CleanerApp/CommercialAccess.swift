import CleanerCore
import Foundation
import Security

struct CommercialClientError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private struct CommercialServiceError: LocalizedError, Sendable {
    let statusCode: Int
    let message: String
    var errorDescription: String? { message }
}

struct CommercialPendingOrder: Codable, Sendable {
    let orderID: String
    let pollToken: String
    let email: String
}

struct CommercialCredentialState: Codable, Sendable {
    let deviceID: UUID
    var email: String?
    var licenseKey: String?
    var signedLicense: SignedLicense?
    var lastTrustedTime: Date?
    var pendingOrder: CommercialPendingOrder?
    var completedOrder: CommercialPendingOrder?
}

protocol CommercialCredentialStorage: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

struct CommercialKeychainStorage: CommercialCredentialStorage {
    private let service = "com.supercleaner.commerce.v1"
    private let account = "device-license-state"

    func read() throws -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CommercialClientError(message: L10n.text("无法读取商业授权钥匙串：{0}", String(status)))
        }
        return data
    }

    func write(_ data: Data) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw CommercialClientError(message: L10n.text("无法保存商业授权钥匙串：{0}", String(update)))
        }
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw CommercialClientError(message: L10n.text("无法保存商业授权钥匙串：{0}", String(status)))
        }
    }
}

private final class CommercialRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct CommercialDevice: Codable, Identifiable, Sendable {
    let deviceID: UUID
    let deviceName: String
    let activatedAt: Int64
    var id: UUID { deviceID }
}

struct CommercialSnapshot: Sendable {
    let deviceID: UUID
    let email: String?
    let offlineValidUntil: Date?
    let hasPendingOrder: Bool
}

private struct CommercialOrderRequest: Encodable, Sendable { let email: String; let deviceID: UUID }
private struct CommercialOrderResponse: Decodable, Sendable { let orderID: String; let pollToken: String; let checkoutURL: URL }
private struct CommercialOrderStatusRequest: Encodable, Sendable { let orderID: String; let pollToken: String }
private struct CommercialOrderStatusResponse: Decodable, Sendable { let status: String; let licenseKey: String? }
private struct CommercialActivationRequest: Encodable, Sendable {
    let email: String; let licenseKey: String; let deviceID: UUID; let deviceName: String
}
private struct CommercialCredentialsRequest: Encodable, Sendable { let email: String; let licenseKey: String }
private struct CommercialDeactivationRequest: Encodable, Sendable { let email: String; let licenseKey: String; let deviceID: UUID }
private struct CommercialDevicesResponse: Decodable, Sendable { let devices: [CommercialDevice] }
private struct CommercialDeactivationResponse: Decodable, Sendable { let deactivated: Bool }
private struct CommercialErrorResponse: Decodable, Sendable { let error: String }

actor CommercialAccess {
    private let configuration: Result<CommercialConfiguration, Error>
    private let storage: any CommercialCredentialStorage
    private let session: URLSession
    private let readNow: @Sendable () -> Date
    private var state: CommercialCredentialState?
    private var automaticRefreshTask: Task<Void, Error>?
    private var lastAutomaticRefreshAttempt: ContinuousClock.Instant?
    private let maximumResponseBytes = 65_536

    init(configuration: Result<CommercialConfiguration, Error>, storage: any CommercialCredentialStorage,
         sessionConfiguration: URLSessionConfiguration = .ephemeral,
         now: @escaping @Sendable () -> Date = Date.init) {
        self.configuration = configuration
        self.storage = storage
        readNow = now
        let policy = sessionConfiguration
        policy.httpCookieStorage = nil
        policy.urlCache = nil
        policy.requestCachePolicy = .reloadIgnoringLocalCacheData
        policy.timeoutIntervalForRequest = 30
        policy.timeoutIntervalForResource = 45
        session = URLSession(configuration: policy, delegate: CommercialRedirectPolicy(), delegateQueue: nil)
    }

    static func live() -> CommercialAccess {
        CommercialAccess(configuration: Result { try CommercialConfiguration.load() }, storage: CommercialKeychainStorage())
    }

    func require(_ feature: CommercialFeature) async throws {
        if feature.isSafetyRight { return }
        let configuration = try configuration.get()
        var current = try credentials()
        var now = readNow()
        var store = try LicenseStore(publicKey: configuration.licensePublicKey, signedLicense: current.signedLicense,
            productID: configuration.productID, deviceID: current.deviceID, now: now, lastTrustedTime: current.lastTrustedTime)
        if let claims = store.claims, TimeInterval(claims.offlineValidUntil) <= now.timeIntervalSince1970 {
            current.lastTrustedTime = max(current.lastTrustedTime ?? now, now)
            try persist(current)
            let renewal = await Task { try await refreshIfNeeded() }.result
            current = try credentials()
            now = readNow()
            store = try LicenseStore(publicKey: configuration.licensePublicKey, signedLicense: current.signedLicense,
                productID: configuration.productID, deviceID: current.deviceID, now: now, lastTrustedTime: current.lastTrustedTime)
            if case let .failure(error) = renewal, !store.isAllowed(feature, now: now) { throw error }
        }
        try store.require(feature, now: now)
        current.lastTrustedTime = max(current.lastTrustedTime ?? now, now)
        try persist(current)
    }

    /// The signed lease determines renewal timing; the service owns its duration.
    /// Fresh credentials never require a request. A failed background renewal
    /// keeps valid offline rights and retries at most once per monotonic minute.
    func refreshIfNeeded() async throws -> Bool {
        let configuration = try configuration.get()
        var current = try credentials()
        let now = readNow()
        let store = try LicenseStore(publicKey: configuration.licensePublicKey, signedLicense: current.signedLicense,
            productID: configuration.productID, deviceID: current.deviceID, now: now, lastTrustedTime: current.lastTrustedTime)
        guard let claims = store.claims else { return false }
        let midpoint = claims.issuedAt + (claims.offlineValidUntil - claims.issuedAt) / 2
        guard now.timeIntervalSince1970 >= TimeInterval(midpoint) else { return false }
        current.lastTrustedTime = max(current.lastTrustedTime ?? now, now)
        try persist(current)
        if let automaticRefreshTask {
            try await automaticRefreshTask.value
            return true
        }
        let instant = ContinuousClock.now
        if let lastAutomaticRefreshAttempt, lastAutomaticRefreshAttempt.duration(to: instant) < .seconds(60) {
            throw CommercialClientError(message: L10n.text("自动刷新暂不可用；将在一分钟后重试，也可在设置中手动刷新。"))
        }
        lastAutomaticRefreshAttempt = instant
        let task = Task { try await refresh(deviceName: Self.currentDeviceName) }
        automaticRefreshTask = task
        let result = await task.result
        automaticRefreshTask = nil
        try result.get()
        return true
    }

    static var currentDeviceName: String { Host.current().localizedName ?? ProcessInfo.processInfo.hostName }

    func signedAuthorization() async throws -> (SignedLicense, UUID) {
        try await require(.newCleanup)
        let current = try credentials()
        guard let signed = current.signedLicense else { throw CommercialClientError(message: L10n.text("请在设置中购买或激活买断授权。")) }
        return (signed, current.deviceID)
    }

    func snapshot() throws -> CommercialSnapshot {
        let configuration = try configuration.get()
        let current = try credentials()
        let store = try LicenseStore(publicKey: configuration.licensePublicKey, signedLicense: current.signedLicense,
            productID: configuration.productID, deviceID: current.deviceID, now: readNow(), lastTrustedTime: current.lastTrustedTime)
        return CommercialSnapshot(deviceID: current.deviceID, email: current.email,
            offlineValidUntil: store.claims.map { Date(timeIntervalSince1970: TimeInterval($0.offlineValidUntil)) },
            hasPendingOrder: current.pendingOrder != nil)
    }

    func purchase(email: String) async throws -> URL {
        let configuration = try configuration.get()
        let email = try validatedEmail(email)
        let current = try credentials()
        let order: CommercialOrderResponse = try await request("v1/orders", payload: CommercialOrderRequest(email: email, deviceID: current.deviceID))
        guard order.checkoutURL.scheme == "https", order.checkoutURL.host == configuration.apiBaseURL.host,
              order.checkoutURL.port == configuration.apiBaseURL.port, order.checkoutURL.user == nil,
              order.checkoutURL.password == nil, !order.orderID.isEmpty, order.pollToken.utf8.count >= 43 else {
            throw CommercialClientError(message: L10n.text("支付服务返回了不安全的收银台地址。"))
        }
        var updated = try credentials()
        updated.pendingOrder = CommercialPendingOrder(orderID: order.orderID, pollToken: order.pollToken, email: email)
        try persist(updated)
        return order.checkoutURL
    }

    func checkPayment(deviceName: String) async throws -> Bool {
        let current = try credentials()
        guard let pending = current.pendingOrder else { throw CommercialClientError(message: L10n.text("没有待检查的购买订单。")) }
        let response: CommercialOrderStatusResponse = try await request("v1/orders/status",
            payload: CommercialOrderStatusRequest(orderID: pending.orderID, pollToken: pending.pollToken))
        switch response.status {
        case "pending": return false
        case "paid":
            guard let key = response.licenseKey, !key.isEmpty else { throw CommercialClientError(message: L10n.text("支付服务未返回激活凭据。")) }
            try await activate(email: pending.email, licenseKey: key, deviceName: deviceName)
            var activated = try credentials()
            activated.completedOrder = pending
            activated.pendingOrder = nil
            try persist(activated)
            return true
        case "closed", "revoked":
            var updated = try credentials()
            updated.pendingOrder = nil
            try persist(updated)
            throw CommercialClientError(message: L10n.text("订单已关闭或撤销，请重新购买或联系支持。"))
        default: throw CommercialClientError(message: L10n.text("支付服务返回了未知订单状态。"))
        }
    }

    func activate(email: String, licenseKey: String, deviceName: String) async throws {
        let email = try validatedEmail(email)
        let key = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.utf8.count <= 512 else { throw CommercialClientError(message: L10n.text("请输入有效的激活码。")) }
        let current = try credentials()
        let response: Result<SignedLicense, Error> = await Task {
            try await request("v1/licenses/activate",
                payload: CommercialActivationRequest(email: email, licenseKey: key, deviceID: current.deviceID, deviceName: deviceName))
        }.result
        switch response {
        case let .success(license): try accept(license, email: email, key: key)
        case let .failure(error):
            if let serviceError = error as? CommercialServiceError, serviceError.statusCode == 409 {
                var unactivated = try credentials()
                if unactivated.signedLicense == nil {
                    // An authenticated device-limit rejection must still let a
                    // replacement Mac release an old slot. It grants no rights.
                    unactivated.email = email
                    unactivated.licenseKey = key
                    try persist(unactivated)
                }
            }
            throw error
        }
    }

    func refresh(deviceName: String) async throws {
        let original = try credentials()
        let credentials = try activationCredentials(original)
        let response: Result<SignedLicense, Error> = await Task {
            try await request("v1/licenses/refresh", payload: CommercialActivationRequest(
                email: credentials.email, licenseKey: credentials.licenseKey, deviceID: original.deviceID, deviceName: deviceName))
        }.result
        let current = try self.credentials()
        let sameCredentials = current.deviceID == original.deviceID && current.email == original.email
            && current.licenseKey == original.licenseKey && current.signedLicense == original.signedLicense
        switch response {
        case let .success(license):
            guard sameCredentials else {
                throw CommercialClientError(message: L10n.text("刷新期间授权已更改，请重新检查当前授权。"))
            }
            try accept(license, email: credentials.email, key: credentials.licenseKey)
        case let .failure(error):
            guard sameCredentials else {
                throw CommercialClientError(message: L10n.text("刷新期间授权已更改，请重新检查当前授权。"))
            }
            if let serviceError = error as? CommercialServiceError, serviceError.statusCode == 403 {
                var revoked = current
                revoked.signedLicense = nil
                try persist(revoked)
            }
            throw error
        }
    }

    func activationCodeForCopy() throws -> String {
        try activationCredentials(try credentials()).licenseKey
    }

    func devices() async throws -> [CommercialDevice] {
        let credentials = try activationCredentials(try self.credentials())
        let response: CommercialDevicesResponse = try await request("v1/licenses/devices", payload: credentials)
        return response.devices
    }

    func deactivate(_ deviceID: UUID) async throws {
        var current = try credentials()
        let credentials = try activationCredentials(current)
        let response: CommercialDeactivationResponse = try await request("v1/licenses/deactivate", payload:
            CommercialDeactivationRequest(email: credentials.email, licenseKey: credentials.licenseKey, deviceID: deviceID))
        guard response.deactivated else { throw CommercialClientError(message: L10n.text("服务端未确认设备解绑。")) }
        if current.deviceID == deviceID {
            current = try self.credentials()
            if current.email == credentials.email, current.licenseKey == credentials.licenseKey {
                current.signedLicense = nil
                try persist(current)
            }
        }
    }

    private func credentials() throws -> CommercialCredentialState {
        if let state { return state }
        if let data = try storage.read() {
            let loaded = try JSONDecoder().decode(CommercialCredentialState.self, from: data)
            state = loaded
            return loaded
        }
        let created = CommercialCredentialState(deviceID: UUID(), email: nil, licenseKey: nil, signedLicense: nil,
            lastTrustedTime: nil, pendingOrder: nil)
        try persist(created)
        return created
    }

    private func persist(_ updated: CommercialCredentialState) throws {
        try storage.write(JSONEncoder().encode(updated))
        state = updated
    }

    private func activationCredentials(_ current: CommercialCredentialState) throws -> CommercialCredentialsRequest {
        guard let email = current.email, let key = current.licenseKey else {
            throw CommercialClientError(message: L10n.text("请先使用购买邮箱和激活码激活。"))
        }
        return CommercialCredentialsRequest(email: email, licenseKey: key)
    }

    private func validatedEmail(_ input: String) throws -> String {
        let email = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.utf8.count <= 254, !email.contains(where: \.isWhitespace) else {
            throw CommercialClientError(message: L10n.text("请输入有效的购买邮箱。"))
        }
        return email
    }

    private func accept(_ license: SignedLicense, email: String, key: String) throws {
        let configuration = try configuration.get()
        var current = try credentials()
        let now = readNow()
        // Only a new authenticated HTTPS response may replace a poisoned local
        // clock baseline. Cached credentials always retain rollback validation.
        let verified = try LicenseStore(publicKey: configuration.licensePublicKey, signedLicense: license,
            productID: configuration.productID, deviceID: current.deviceID, now: now, lastTrustedTime: nil)
        try verified.require(.newCleanup, now: now)
        guard let claims = verified.claims, claims.email.lowercased() == email else { throw CommercialClientError(message: L10n.text("授权邮箱与激活信息不一致。")) }
        current.email = email
        current.licenseKey = key
        current.signedLicense = license
        current.lastTrustedTime = Date(timeIntervalSince1970: TimeInterval(claims.issuedAt))
        try persist(current)
    }

    private func request<Payload: Encodable & Sendable, Response: Decodable & Sendable>(_ path: String, payload: Payload) async throws -> Response {
        let configuration = try configuration.get()
        let url = configuration.apiBaseURL.appendingPathComponent(path)
        guard url.scheme == "https", url.host == configuration.apiBaseURL.host else {
            throw CommercialClientError(message: L10n.text("商业服务必须使用同源 HTTPS 地址。"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(payload)
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let response = response as? HTTPURLResponse,
              response.url == url, response.expectedContentLength <= Int64(maximumResponseBytes) else {
            throw CommercialClientError(message: L10n.text("商业服务响应无效或超过大小限制。"))
        }
        guard response.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true else {
            throw CommercialClientError(message: L10n.text("商业服务没有返回 JSON 响应。"))
        }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumResponseBytes else { throw CommercialClientError(message: L10n.text("商业服务响应无效或超过大小限制。")) }
            data.append(byte)
        }
        guard (200..<300).contains(response.statusCode) else {
            let error = try JSONDecoder().decode(CommercialErrorResponse.self, from: data)
            throw CommercialServiceError(statusCode: response.statusCode, message: error.error)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
